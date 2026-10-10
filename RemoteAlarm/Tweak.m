#import <Foundation/Foundation.h>
#import <dispatch/dispatch.h>
#import <dlfcn.h>
#import <substrate.h>
#if __has_include(<ptrauth.h>)
#import <ptrauth.h>
#endif
#include <stdint.h>
#include <string.h>

// The notification and bulletin classes are private to SpringBoard.
// Declare the selectors so both architecture slices compile under ARC.
@interface NSObject (N2TPrivateBulletin)
- (NSString *)sectionIdentifier;
- (id)bulletin;
- (NSString *)message;
@end

// Private entry points from the original No2Theft dylib bundled in
// No2Theft Enhanced 1.3.2. Kept separate to preserve the known-good package.
#if defined(__arm64e__)
#define N2T_NOTIFICATION 0x6ccc
#define N2T_PIN_PROMPT   0x7e64
#define N2T_ALARM_SOUND  0x82dc
#define N2T_NOTIFY_SIG   0xd503237f
#define N2T_PIN_SIG      0xd503237f
#define N2T_SOUND_SIG    0xd503237f
#else
#define N2T_NOTIFICATION 0x4e88
#define N2T_PIN_PROMPT   0x5fa0
#define N2T_ALARM_SOUND  0x6380
#define N2T_NOTIFY_SIG   0xd10203ff
#define N2T_PIN_SIG      0xd10143ff
#define N2T_SOUND_SIG    0xa9be4ff4
#endif

static void *no2Base;
static void *no2Handle;
static BOOL *no2IsRunning;
static BOOL *no2Password;
static BOOL *no2PinEnable;
static BOOL *no2SMSRemote;
static BOOL *no2EmailRemote;
static BOOL *no2Enable;
static NSString *__unsafe_unretained *no2TriggerPhrase;
static void (*priorNotification)(id, SEL, id);
static CFAbsoluteTime lastRemoteAlarm;
static BOOL isInstalled;

static BOOL safeInstruction(uintptr_t offset, uint32_t expected) {
    if (!no2Base) return NO;
    uint32_t actual;
    memcpy(&actual, (uint8_t *)no2Base + offset, sizeof(actual));
    return actual == expected;
}

static void callOriginal(uintptr_t offset) {
    void *ptr = (uint8_t *)no2Base + offset;
#if defined(__arm64e__)
    ptr = ptrauth_sign_unauthenticated(ptr, ptrauth_key_function_pointer, 0);
#endif
    ((void (*)(void))ptr)();
}

static BOOL originalBinaryAvailable(void) {
    if (!no2Handle)
        no2Handle = dlopen("/var/jb/Library/MobileSubstrate/DynamicLibraries/No2Theft.dylib",
                           RTLD_NOW | RTLD_NOLOAD);
    if (!no2Handle) return NO;
    void *anchor = dlsym(no2Handle, "audioPlayer");
    Dl_info info;
    if (!anchor || !dladdr(anchor, &info) || !info.dli_fbase) return NO;
    no2Base = info.dli_fbase;
    no2IsRunning = (BOOL *)dlsym(no2Handle, "isRunning");
    no2Password = (BOOL *)dlsym(no2Handle, "password");
    no2PinEnable = (BOOL *)dlsym(no2Handle, "pinEnable");
    no2SMSRemote = (BOOL *)dlsym(no2Handle, "smsRemote");
    no2EmailRemote = (BOOL *)dlsym(no2Handle, "emailRemote");
    no2Enable = (BOOL *)dlsym(no2Handle, "enable");
    no2TriggerPhrase = (NSString *__unsafe_unretained *)dlsym(no2Handle, "triggerPhrase");
    return no2IsRunning && no2Password && no2PinEnable &&
           no2SMSRemote && no2EmailRemote && no2TriggerPhrase;
}

static BOOL remotePhraseMatched(id event) {
    if (!event || !no2TriggerPhrase) return NO;
    if ((!*no2SMSRemote && !*no2EmailRemote) ||
        (no2Enable && !*no2Enable)) return NO;
    NSString *phrase = *no2TriggerPhrase;
    if (![phrase isKindOfClass:[NSString class]] || phrase.length == 0) return NO;
    @try {
        if (![event respondsToSelector:@selector(sectionIdentifier)] ||
            ![[event sectionIdentifier] isEqualToString:@"com.apple.MobileSMS"]) return NO;
        if (![event respondsToSelector:@selector(bulletin)]) return NO;
        id bulletin = [event bulletin];
        if (![bulletin respondsToSelector:@selector(message)]) return NO;
        id message = [bulletin message];
        return [message isKindOfClass:[NSString class]] && [message isEqualToString:phrase];
    } @catch (NSException *exception) {
        return NO;
    }
}

static void startOriginalAlarm(void) {
    if (!isInstalled || !no2IsRunning || *no2IsRunning || !no2Base) return;
    // Enter the same state as a failed passcode attempt, rather than
    // playing a second, independent audio player.
    if (no2PinEnable && *no2PinEnable) callOriginal(N2T_PIN_PROMPT);
    *no2Password = NO;
    *no2IsRunning = YES;
    callOriginal(N2T_ALARM_SOUND);
    // Existing N2TSOSFlashlight starts when the native alarm player plays.
    // The original SMS callback already handled its configured email.
}

static void interceptedRemoteSMS(id self, SEL selector, id event) {
    BOOL matched = remotePhraseMatched(event);
    if (priorNotification) priorNotification(self, selector, event);
    if (!matched) return;
    CFAbsoluteTime now = CFAbsoluteTimeGetCurrent();
    if (now - lastRemoteAlarm < 5.0) return;
    lastRemoteAlarm = now;
    dispatch_async(dispatch_get_main_queue(), ^{
        @try { startOriginalAlarm(); }
        @catch (NSException *exception) {
            NSLog(@"[No2Theft Remote Alarm] Trigger failed: %@", exception.name);
        }
    });
}

static void installRemoteAlarm(unsigned retry) {
    if (isInstalled) return;
    if (originalBinaryAvailable()) {
        if (!safeInstruction(N2T_NOTIFICATION, N2T_NOTIFY_SIG) ||
            !safeInstruction(N2T_PIN_PROMPT, N2T_PIN_SIG) ||
            !safeInstruction(N2T_ALARM_SOUND, N2T_SOUND_SIG)) {
            NSLog(@"[No2Theft Remote Alarm] Unknown binary; leaving original unchanged");
            return;
        }
        MSHookFunction((uint8_t *)no2Base + N2T_NOTIFICATION,
                       (void *)interceptedRemoteSMS,
                       (void **)&priorNotification);
        isInstalled = priorNotification != NULL;
        NSLog(@"[No2Theft Remote Alarm] Installed=%d", isInstalled);
        if (isInstalled) return;
    }
    if (retry < 12)
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 2 * NSEC_PER_SEC),
                       dispatch_get_main_queue(), ^{ installRemoteAlarm(retry + 1); });
}

__attribute__((constructor))
static void initializeRemoteAlarm(void) {
    @autoreleasepool {
        dispatch_async(dispatch_get_main_queue(), ^{ installRemoteAlarm(0); });
    }
}

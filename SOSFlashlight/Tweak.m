#import <Foundation/Foundation.h>
#import <AVFoundation/AVFoundation.h>
#import <CoreFoundation/CoreFoundation.h>
#import <dispatch/dispatch.h>
#import <dlfcn.h>
#import <substrate.h>

static NSString *const kPreferencesDomain = @"com.elias.no2theft3";
static NSString *const kPreferenceKey = @"sosFlashlight";

static BOOL (*originalPlay)(AVAudioPlayer *, SEL) = NULL;
static void (*originalStop)(AVAudioPlayer *, SEL) = NULL;
static void (*originalPause)(AVAudioPlayer *, SEL) = NULL;

static AVAudioPlayer *activeAlarmPlayer = nil;
static AVCaptureDevice *flashlight = nil;
static dispatch_source_t sosTimer = nil;
static AVAudioPlayer *__unsafe_unretained *no2AlarmPlayerSlot = NULL;
static BOOL *no2IsRunning = NULL;
static BOOL sosEnabled = NO;
static unsigned pulseIndex = 0, ticksLeft = 0, ticksSinceStart = 0;

// One Morse time unit = 200 ms; dot=1 unit, dash=3,
// between symbols=1, between letters=3, between SOS repetitions=7.
typedef struct { BOOL lit; unsigned ticks; } SOSPulse;
static const SOSPulse sosPulses[] = {
    {YES,2},{NO,2},{YES,2},{NO,2},{YES,2},{NO,6},
    {YES,6},{NO,2},{YES,6},{NO,2},{YES,6},{NO,6},
    {YES,2},{NO,2},{YES,2},{NO,2},{YES,2},{NO,14}
};
static const unsigned sosPulseCount = sizeof(sosPulses)/sizeof(sosPulses[0]);

static BOOL readPreference(void) {
    CFStringRef domain = (__bridge CFStringRef)kPreferencesDomain;
    CFPreferencesAppSynchronize(domain);
    CFPropertyListRef value = CFPreferencesCopyAppValue((__bridge CFStringRef)kPreferenceKey, domain);
    BOOL enabled = NO;
    if (value && CFGetTypeID(value) == CFBooleanGetTypeID())
        enabled = CFBooleanGetValue((CFBooleanRef)value);
    if (value) CFRelease(value);
    return enabled;
}

// The original No2Theft 1.3.1 binary exports its alarm AVAudioPlayer
// and its running flag. Resolve without changing or patching that binary.
static void resolveNo2TheftSymbols(void) {
    if (no2AlarmPlayerSlot) return;
    void *module = dlopen("/var/jb/Library/MobileSubstrate/DynamicLibraries/No2Theft.dylib",
                          RTLD_NOW | RTLD_NOLOAD);
    if (module) {
        no2AlarmPlayerSlot = (AVAudioPlayer *__unsafe_unretained *)dlsym(module, "audioPlayer");
        no2IsRunning = (BOOL *)dlsym(module, "isRunning");
        // Keep this NOLOAD reference alive while symbol addresses are used.
    }
    if (!no2AlarmPlayerSlot)
        no2AlarmPlayerSlot = (AVAudioPlayer *__unsafe_unretained *)dlsym(RTLD_DEFAULT, "audioPlayer");
    if (!no2IsRunning)
        no2IsRunning = (BOOL *)dlsym(RTLD_DEFAULT, "isRunning");
}

static BOOL isNo2TheftAlarmPlayer(AVAudioPlayer *player) {
    if (!player) return NO;
    if (player == activeAlarmPlayer) return YES;
    resolveNo2TheftSymbols();
    if (no2AlarmPlayerSlot && *no2AlarmPlayerSlot == player) return YES;

    // Fallback if a build assigns the global immediately after play.
    // Require No2Theft's active alarm flag to avoid identifying other audio.
    if (no2IsRunning && *no2IsRunning) {
        NSString *path = player.url.path;
        if ([path containsString:@"/No2Theft/Alarm Sounds/"] ||
            [path hasSuffix:@"/Library/Ringtones/Alarm.m4a"])
            return YES;
    }
    return NO;
}

static void setFlashlight(BOOL on) {
    if (!flashlight)
        flashlight = [AVCaptureDevice defaultDeviceWithMediaType:AVMediaTypeVideo];
    if (!flashlight || !flashlight.hasTorch) return;
    NSError *error = nil;
    if (![flashlight lockForConfiguration:&error]) return;
    @try {
        if (on) {
            if (![flashlight setTorchModeOnWithLevel:AVCaptureMaxAvailableTorchLevel error:&error])
                flashlight.torchMode = AVCaptureTorchModeOn;
        } else {
            flashlight.torchMode = AVCaptureTorchModeOff;
        }
    } @catch (NSException *exception) {
        // An unavailable/contended camera must not crash SpringBoard.
    } @finally {
        [flashlight unlockForConfiguration];
    }
}

static void stopSOS(void) {
    NSCAssert([NSThread isMainThread], @"SOS state must run on the main thread");
    if (sosTimer) {
        dispatch_source_cancel(sosTimer);
        sosTimer = nil;
    }
    activeAlarmPlayer = nil;
    pulseIndex = ticksLeft = ticksSinceStart = 0;
    setFlashlight(NO);
}

static void tickSOS(void) {
    if (!sosTimer) return;
    if (!sosEnabled || !activeAlarmPlayer) { stopSOS(); return; }

    // Stop if the original tweak reports alarm stopped AND its sound is no
    // longer active. Explicit stop/pause calls are also hooked below.
    if (ticksSinceStart > 15 && no2IsRunning && !*no2IsRunning &&
        !activeAlarmPlayer.isPlaying) {
        stopSOS();
        return;
    }
    ticksSinceStart++;
    if (ticksLeft == 0) {
        SOSPulse next = sosPulses[pulseIndex];
        setFlashlight(next.lit);
        ticksLeft = next.ticks;
        pulseIndex = (pulseIndex + 1) % sosPulseCount;
    }
    ticksLeft--;
}

static void startSOS(AVAudioPlayer *player) {
    if (!sosEnabled || !player) return;
    if (sosTimer) {
        if (activeAlarmPlayer == player) return;
        stopSOS();
    }
    activeAlarmPlayer = player;
    pulseIndex = ticksLeft = ticksSinceStart = 0;
    sosTimer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, dispatch_get_main_queue());
    if (!sosTimer) { activeAlarmPlayer = nil; return; }
    dispatch_source_set_event_handler(sosTimer, ^{ tickSOS(); });
    dispatch_source_set_timer(sosTimer, dispatch_time(DISPATCH_TIME_NOW, 0),
                              NSEC_PER_MSEC * 100, NSEC_PER_MSEC * 15);
    dispatch_resume(sosTimer);
}

static BOOL sosPlay(AVAudioPlayer *self, SEL command) {
    BOOL result = originalPlay ? originalPlay(self, command) : NO;
    if (result && isNo2TheftAlarmPlayer(self)) {
        dispatch_async(dispatch_get_main_queue(), ^{ startSOS(self); });
    }
    return result;
}

static void sosStop(AVAudioPlayer *self, SEL command) {
    if (isNo2TheftAlarmPlayer(self))
        dispatch_async(dispatch_get_main_queue(), ^{ if (activeAlarmPlayer == self) stopSOS(); });
    if (originalStop) originalStop(self, command);
}

static void sosPause(AVAudioPlayer *self, SEL command) {
    if (isNo2TheftAlarmPlayer(self))
        dispatch_async(dispatch_get_main_queue(), ^{ if (activeAlarmPlayer == self) stopSOS(); });
    if (originalPause) originalPause(self, command);
}

static void preferencesChanged(CFNotificationCenterRef center, void *observer,
                               CFStringRef name, const void *object, CFDictionaryRef userInfo) {
    dispatch_async(dispatch_get_main_queue(), ^{
        sosEnabled = readPreference();
        if (!sosEnabled && sosTimer) stopSOS();
    });
}

__attribute__((constructor))
static void installSOSFlashlight(void) {
    @autoreleasepool {
        sosEnabled = readPreference();
        CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(),
            NULL, preferencesChanged,
            CFSTR("com.elias.no2theft3.preferences-changed"),
            NULL, CFNotificationSuspensionBehaviorDeliverImmediately);
        Class playerClass = objc_getClass("AVAudioPlayer");
        if (playerClass) {
            MSHookMessageEx(playerClass, @selector(play), (IMP)sosPlay, (IMP *)&originalPlay);
            MSHookMessageEx(playerClass, @selector(stop), (IMP)sosStop, (IMP *)&originalStop);
            MSHookMessageEx(playerClass, @selector(pause), (IMP)sosPause, (IMP *)&originalPause);
        }
    }
}

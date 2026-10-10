#import <Foundation/Foundation.h>
#import <dispatch/dispatch.h>
#import <dlfcn.h>
#import <substrate.h>
#if __has_include(<ptrauth.h>)
#import <ptrauth.h>
#endif
#include <stdint.h>
#include <string.h>

// iOS 16 No2Theft Enhanced v1.3.5 only.
// Defers the legacy original SMS function rather than allowing it
// to execute inline during PIN presentation / SMTP setup.
// Preserves firstNumber, secondNumber and the SMS GPS add-on.
// Never changes the stable No2Theft dylib or user preferences.

#if defined(__arm64e__)
#define N2T_SMS_OFFSET   0x7f74
#define N2T_SMS_PROLOGUE 0xd503237f
#else
#define N2T_SMS_OFFSET   0x6094
#define N2T_SMS_PROLOGUE 0xd100c3ff
#endif

static void (*originalSMSRoutine)(void);
static BOOL *smsEnabled;
static BOOL installed;
static void *no2Handle;
static void *no2Base;
static NSString *const statusFile =
    @"/var/mobile/Library/Preferences/uk.551.no2theft.smsflowfix.status.plist";

static void Record(NSString *stage) {
    [@{@"date":[NSDate date],@"stage":stage}
        writeToFile:statusFile atomically:YES];
}

static void DeferredOriginalSMS(void) {
    if (!originalSMSRoutine) return;

    // Run unaltered when the feature is switched off.
    if (!smsEnabled || !*smsEnabled) {
        originalSMSRoutine();
        return;
    }

    // The original binary runs camera -> email -> SMS inline.
    // Give its alert UI and SMTP setup time to return to the
    // SpringBoard run loop before calling the original SMS sender.
    Record(@"sms_deferred_from_alarm");
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.5*NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        @try {
            Record(@"sms_original_started");
            originalSMSRoutine();
            Record(@"sms_original_returned");
        } @catch (NSException *error) {
            Record(@"sms_original_exception");
            NSLog(@"[N2T SMS Flow Fix] Original SMS routine threw %@", error.name);
        }
    });
}

static void Install(unsigned attempt) {
    if (installed) return;
    if (!no2Handle)
        no2Handle = dlopen("/var/jb/Library/MobileSubstrate/DynamicLibraries/No2Theft.dylib",
                          RTLD_NOW|RTLD_NOLOAD);

    void *anchor = no2Handle ? dlsym(no2Handle, "_Z11takepicturebP8NSString") : NULL;
    smsEnabled = no2Handle ? (BOOL *)dlsym(no2Handle, "sendSMS") : NULL;

    Dl_info info={0};
    if(anchor && smsEnabled && dladdr(anchor,&info) && info.dli_fbase &&
       info.dli_fname && strstr(info.dli_fname,"No2Theft.dylib")) {
        no2Base=info.dli_fbase;
        uint32_t prologue=0;
        void *target=(uint8_t *)no2Base+N2T_SMS_OFFSET;
        memcpy(&prologue,target,sizeof(prologue));
        if (prologue != N2T_SMS_PROLOGUE) {
            Record(@"signature_mismatch_no_hook");
            return;
        }
#if defined(__arm64e__)
        target=ptrauth_sign_unauthenticated(target,ptrauth_key_function_pointer,0);
#endif
        MSHookFunction(target,(void *)DeferredOriginalSMS,(void **)&originalSMSRoutine);
        installed=originalSMSRoutine!=NULL;
        Record(installed?@"sms_flow_hook_installed":@"sms_flow_hook_failed");
        if(installed)return;
    }
    if(attempt>=20){Record(@"original_sms_unavailable");return;}
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW,NSEC_PER_SEC),
                   dispatch_get_main_queue(),^{Install(attempt+1);});
}

__attribute__((constructor)) static void N2TInitSMSFlowFix(void) {
    @autoreleasepool {
        if(![[NSProcessInfo processInfo].processName isEqualToString:@"SpringBoard"])return;
        dispatch_async(dispatch_get_main_queue(),^{Install(0);});
    }
}

#import <Foundation/Foundation.h>
#import <dispatch/dispatch.h>
#import <dlfcn.h>
#import <substrate.h>

// Experimental diagnostic: allow No2Theft's existing alarm actions to
// continue by returning early from its legacy camera helper.
// No modifications to the installed No2Theft.dylib or stable v1.3.5.
static void (*previousPhoto)(BOOL, NSString *);
static void *no2Handle;
static BOOL installed;
static NSString *const statusPath =
    @"/var/mobile/Library/Preferences/uk.551.no2theft.photoguard.status.plist";

static void Record(NSString *stage) {
    [@{@"date":[NSDate date],@"stage":stage}
        writeToFile:statusPath atomically:YES];
}

static void SkipLegacyPhoto(BOOL isAlarm, NSString *name) {
    // v1.3.5 calls this before continuing into its regular alarm
    // notification routines. Do not run the crashing legacy capture.
    (void)isAlarm;
    (void)name;
    Record(@"photo_bypassed");
}

static void Install(unsigned attempt) {
    if(installed)return;
    if(!no2Handle)
        no2Handle=dlopen("/var/jb/Library/MobileSubstrate/DynamicLibraries/No2Theft.dylib",
                        RTLD_LAZY|RTLD_NOLOAD);
    void *target=no2Handle?dlsym(no2Handle,"_Z11takepicturebP8NSString"):NULL;
    if(target) {
        MSHookFunction(target,(void *)SkipLegacyPhoto,(void **)&previousPhoto);
        installed=previousPhoto!=NULL;
        Record(installed?@"photo_bypass_installed":@"photo_bypass_hook_failed");
        if(installed)return;
    }
    if(attempt>=20) {Record(@"photo_symbol_unavailable");return;}
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW,NSEC_PER_SEC),
                   dispatch_get_main_queue(),^{Install(attempt+1);});
}

__attribute__((constructor)) static void Initialize(void) {
    @autoreleasepool {
        if(![[NSProcessInfo processInfo].processName isEqualToString:@"SpringBoard"])return;
        dispatch_async(dispatch_get_main_queue(),^{Install(0);});
    }
}

#import <Foundation/Foundation.h>
#import <dispatch/dispatch.h>
#import <dlfcn.h>
#import <substrate.h>

// The stable v1.3.5 package is not modified. This is a standalone,
// removable exception guard for the original No2Theft photo routine.
// The exported symbol was confirmed in both arm64 and arm64e slices.
static void (*originalTakePicture)(BOOL, NSString *);
static void *sourceHandle;
static BOOL installed;
static const char *const photoSymbol="_Z11takepicturebP8NSString";
static NSString *const statusPath=@"/var/mobile/Library/Preferences/uk.551.no2theft.photoguard.status.plist";

static void Record(NSString *status,NSString *exceptionName) {
    NSMutableDictionary *item=[@{@"date":[NSDate date],@"stage":status} mutableCopy];
    if(exceptionName.length && exceptionName.length<120)
        item[@"exception"]=exceptionName;
    // No SMS contents, photo contents, GPS or user data are logged.
    [item writeToFile:statusPath atomically:YES];
}

static void GuardedTakePicture(BOOL isAlarm,NSString *photoName) {
    if(!originalTakePicture)return;
    @try {
        originalTakePicture(isAlarm,photoName);
    } @catch(NSException *exception) {
        // iOS 16 can throw out of AVCaptureStillImageOutput while the
        // old No2Theft takepicture() spins a nested CFRunLoop on SpringBoard.
        // Catch at the original function boundary, not globally.
        Record(@"photo_exception_caught",exception.name?:@"unknown");
        NSLog(@"[No2Theft Photo Guard] Caught exception during legacy photo capture: %@",
              exception.name?:@"unknown");
        // The photo for this event may be lost; leave alarms/SMS/GPS alone.
    }
}

static void Install(unsigned retry) {
    if(installed)return;
    if(!sourceHandle) {
        sourceHandle=dlopen("/var/jb/Library/MobileSubstrate/DynamicLibraries/No2Theft.dylib",
                           RTLD_LAZY|RTLD_NOLOAD);
    }
    void *target=sourceHandle?dlsym(sourceHandle,photoSymbol):NULL;
    if(target) {
        MSHookFunction(target,(void *)GuardedTakePicture,(void **)&originalTakePicture);
        installed=(originalTakePicture!=NULL);
        Record(installed?@"guard_installed":@"guard_hook_failed",nil);
        if(installed)return;
    }
    if(retry>=20) {
        Record(@"photo_symbol_unavailable",nil);
        return;
    }
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW,(int64_t)(NSEC_PER_SEC)),
                   dispatch_get_main_queue(),^{Install(retry+1);});
}

__attribute__((constructor))static void InitializePhotoGuard(void) {
    @autoreleasepool {
        if(![[NSProcessInfo processInfo].processName isEqualToString:@"SpringBoard"])return;
        dispatch_async(dispatch_get_main_queue(),^{Install(0);});
    }
}

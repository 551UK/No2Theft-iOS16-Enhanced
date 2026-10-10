#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import <dispatch/dispatch.h>
#import <dlfcn.h>
#import <spawn.h>
#import <sys/wait.h>
#import <signal.h>
#import <unistd.h>
#import <math.h>
#import <stdio.h>
#import <substrate.h>

extern char **environ;

// Works alongside the stock No2Theft 1.3.5 binary. It never creates an
// SMS, changes recipients, or reads the Messages database. It modifies only
// a No2Theft alert already queued with an invalid 0,0 Maps link or
// an IP-based Maps link from the SMS remote command.
static BOOL (*originalSMS)(id, SEL, id, id, id);
static NSRegularExpression *mapExpression;
static NSMutableArray<NSDictionary *> *pendingMessages;
static BOOL gpsInProgress;
static NSString *recentGPS;
static NSDate *recentGPSDate;

static NSString *const statusPath=@"/var/mobile/Library/Preferences/uk.551.no2theft.smslocationfix.status.plist";
static NSString *const gpsPath=@"/var/jb/Applications/N2TLocation.app/N2TLocation";
static NSString *const resultDirectory=@"/var/mobile/Library/Preferences";

static void LogStage(NSString *stage) {
    // Deliberately exclude sender, phone number, coordinates and SMS body.
    [@{@"date":[NSDate date],@"stage":stage} writeToFile:statusPath atomically:YES];
}

static BOOL IsNo2TheftSMS(NSString *message) {
    return [message containsString:@"Your password has been inputted wrong several times at this location"] ||
           [message containsString:@"SMS remote action has been received"] ||
           [message containsString:@"Your password was inputted wrong several times or might have initiated a remote command"];
}

static NSRange MapRangeToCorrect(NSString *message) {
    NSTextCheckingResult *match=[mapExpression firstMatchInString:message
        options:0 range:NSMakeRange(0,message.length)];
    if(!match || match.range.location==NSNotFound) return NSMakeRange(NSNotFound,0);
    // The remote SMS command uses IP-derived location coordinates (often
    // London). Replace its map link even when it is not 0,0.
    if ([message containsString:@"SMS remote action has been received"])
        return match.range;
    NSString *link=[message substringWithRange:match.range];
    NSRange query=[link rangeOfString:@"?q=" options:NSCaseInsensitiveSearch];
    if(query.location==NSNotFound) return NSMakeRange(NSNotFound,0);
    NSString *coordinates=[link substringFromIndex:NSMaxRange(query)];
    double lat=999,lon=999;
    if(sscanf(coordinates.UTF8String,"%lf,%lf",&lat,&lon)==2 &&
        fabs(lat)<0.0000001 && fabs(lon)<0.0000001) return match.range;
    return NSMakeRange(NSNotFound,0);
}

static NSString *AllowedURL(id value) {
    if(![value isKindOfClass:NSString.class] || [value length]>256) return nil;
    NSString *s=(NSString *)value;
    if(![s hasPrefix:@"https://maps.google.com/maps?q="]) return nil;
    NSString *coords=[s substringFromIndex:[@"https://maps.google.com/maps?q=" length]];
    double lat=999,lon=999;
    if(sscanf(coords.UTF8String,"%lf,%lf",&lat,&lon)!=2) return nil;
    if(!isfinite(lat)||!isfinite(lon)||fabs(lat)>90||fabs(lon)>180||
       (fabs(lat)<0.0000001&&fabs(lon)<0.0000001)) return nil;
    return s;
}

static NSDictionary *GetFreshGPS(void) {
    if(![[NSFileManager defaultManager] isExecutableFileAtPath:gpsPath])
        return @{@"status":@"helper_missing"};
    NSString *token=NSUUID.UUID.UUIDString;
    NSString *file=[resultDirectory stringByAppendingPathComponent:
        [NSString stringWithFormat:@"uk.551.no2theft.onceloc.%@.plist",token]];
    pid_t pid=0;
    char *argv[]={(char *)gpsPath.fileSystemRepresentation,"--once",
                  (char *)token.UTF8String,NULL};
    int code=posix_spawn(&pid,gpsPath.fileSystemRepresentation,NULL,NULL,argv,environ);
    if(code) return @{@"status":@"spawn_failure"};
    NSDictionary *reply=nil;
    NSDate *until=[NSDate dateWithTimeIntervalSinceNow:20];
    while([until timeIntervalSinceNow]>0) {
        NSDictionary *item=[NSDictionary dictionaryWithContentsOfFile:file];
        if([item[@"requestID"] isEqualToString:token] &&
           ![item[@"status"] isEqualToString:@"starting"]) {
            reply=item;
            break;
        }
        [NSThread sleepForTimeInterval:0.25];
    }
    if(!reply)kill(pid,SIGTERM);
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY,0),^{
        waitpid(pid,NULL,0);
    });
    [[NSFileManager defaultManager] removeItemAtPath:file error:NULL];
    return reply?:@{@"status":@"gps_timeout"};
}

static void DeliverPending(NSString *url) {
    NSArray<NSDictionary *> *batch=[pendingMessages copy];
    [pendingMessages removeAllObjects];
    gpsInProgress=NO;
    if(url) {
        recentGPS=[url copy];
        recentGPSDate=[NSDate date];
    }
    for(NSDictionary *entry in batch) {
        id receiver=entry[@"receiver"];
        NSString *message=entry[@"message"];
        id center=entry[@"service"];
        if(center==(id)NSNull.null)center=nil;
        id recipient=entry[@"recipient"];
        SEL selector=@selector(sendSMSWithText:serviceCenter:toAddress:);
        NSRange bad=MapRangeToCorrect(message);
        if(bad.location!=NSNotFound) {
            NSString *replacement=url?:@"GPS location unavailable";
            message=[message stringByReplacingCharactersInRange:bad withString:replacement];
        }
        // Call the original implementation, not this hook, for exactly
        // the recipient selected by the original No2Theft binary.
        @try {
            originalSMS(receiver,selector,message,center,recipient);
            LogStage(url?@"sms_original_called_with_gps":@"sms_original_called_without_gps");
        } @catch(__unused NSException *exception) {
            LogStage(@"sms_original_exception");
        }
    }
}

static void QueueSMSOnMain(NSDictionary *entry) {
    if(!pendingMessages)pendingMessages=[NSMutableArray new];
    [pendingMessages addObject:entry];
    if(gpsInProgress)return;
    if(recentGPS && recentGPSDate &&
       [[NSDate date] timeIntervalSinceDate:recentGPSDate]<30) {
        DeliverPending(recentGPS);
        return;
    }
    gpsInProgress=YES;
    LogStage(@"requesting_fresh_gps");
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY,0),^{
        NSDictionary *result=GetFreshGPS();
        NSString *url=[result[@"status"] isEqualToString:@"success"]
                           ?AllowedURL(result[@"mapURL"]):nil;
        dispatch_async(dispatch_get_main_queue(),^{
            DeliverPending(url);
        });
    });
}

static BOOL HookSMS(id self,SEL selector,id text,id serviceCenter,id recipient) {
    if(!originalSMS)return NO;
    if(![text isKindOfClass:NSString.class] ||
       ![recipient isKindOfClass:NSString.class] ||
       !IsNo2TheftSMS(text) ||
       ZeroMapRange(text).location==NSNotFound)
        return originalSMS(self,selector,text,serviceCenter,recipient);
    NSDictionary *entry=@{@"receiver":self,@"message":[text copy],
                          @"service":serviceCenter?:NSNull.null,
                          @"recipient":[recipient copy]};
    LogStage([text containsString:@"SMS remote action has been received"]
                 ? @"intercepted_remote_ip_location"
                 : @"intercepted_zero_location");
    if([NSThread isMainThread])QueueSMSOnMain(entry);
    else dispatch_async(dispatch_get_main_queue(),^{QueueSMSOnMain(entry);});
    // Queued. Actual send result isn't available synchronously.
    return YES;
}

static void Install(void) {
    Class cls=objc_getClass("CTMessageCenter");
    SEL method=@selector(sendSMSWithText:serviceCenter:toAddress:);
    if(!cls || !class_getInstanceMethod(cls,method)) {
        LogStage(@"sms_class_or_method_missing");
        return;
    }
    MSHookMessageEx(cls,method,(IMP)HookSMS,(IMP *)&originalSMS);
    LogStage(originalSMS?@"sms_hook_installed":@"sms_hook_failed");
}

__attribute__((constructor))static void Entry(void) {
    @autoreleasepool {
        if(![[NSProcessInfo processInfo].processName isEqualToString:@"SpringBoard"])return;
        mapExpression=[NSRegularExpression regularExpressionWithPattern:
            @"https?://maps\\.google\\.com/maps\\?q=[^\\s<>\"']+"
            options:NSRegularExpressionCaseInsensitive error:NULL];
        dlopen("/System/Library/Frameworks/CoreTelephony.framework/CoreTelephony",RTLD_LAZY);
        dispatch_async(dispatch_get_main_queue(),^{Install();});
    }
}

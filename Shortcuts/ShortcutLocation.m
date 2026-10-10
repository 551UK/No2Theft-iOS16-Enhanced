#import <Foundation/Foundation.h>
#import <objc/message.h>
#import <objc/runtime.h>
#import <dlfcn.h>
#import <CoreLocation/CoreLocation.h>
#import <unistd.h>
#import <sys/stat.h>
#import <math.h>
#import <stdatomic.h>

static NSString * const kResultDirectory = @"/var/mobile/Library/Preferences";
static NSString *gToken;
static NSString *gStatus;
static NSString *gMapsURL;
static atomic_bool gWorkflowFinished;
static atomic_bool gWorkflowStarted;

static id MsgGet(id obj, NSString *key) {
    if (!obj) return nil;
    SEL sel = NSSelectorFromString(key);
    if ([obj respondsToSelector:sel]) {
        @try { return ((id (*)(id,SEL))objc_msgSend)(obj,sel); }
        @catch (__unused NSException *e) { return nil; }
    }
    return nil;
}
static BOOL IsMapURL(NSString *s) {
    if (![s isKindOfClass:[NSString class]]) return NO;
    NSString *l = s.lowercaseString;
    return ([l hasPrefix:@"https://maps.apple.com/"] ||
            [l hasPrefix:@"http://maps.apple.com/"] ||
            [l hasPrefix:@"https://maps.google.com/"] ||
            [l hasPrefix:@"https://www.google.com/maps"]);
}
static NSString *FindURL(id object, NSUInteger depth) {
    if (!object || depth > 9) return nil;
    if ([object isKindOfClass:[NSURL class]]) return FindURL([(NSURL *)object absoluteString],depth+1);
    if ([object isKindOfClass:[NSString class]]) {
        NSString *str = object;
        if (IsMapURL(str)) return str;
        NSRegularExpression *re = [NSRegularExpression regularExpressionWithPattern:
           @"https?://(?:maps\\.apple\\.com|maps\\.google\\.com|www\\.google\\.com/maps)[^\\s\\\"<>]+"
           options:NSRegularExpressionCaseInsensitive error:nil];
        NSTextCheckingResult *match = [re firstMatchInString:str options:0 range:NSMakeRange(0,str.length)];
        return match ? [str substringWithRange:match.range] : nil;
    }
    if ([object isKindOfClass:[NSArray class]]) {
        for (id value in object) { NSString *s = FindURL(value,depth+1); if (s) return s; }
        return nil;
    }
    if ([object isKindOfClass:[NSDictionary class]]) {
        for (id value in [(NSDictionary *)object allValues]) {
            NSString *s = FindURL(value,depth+1); if (s) return s;
        }
        return nil;
    }
    if ([object isKindOfClass:[CLLocation class]]) {
        CLLocationCoordinate2D c = [(CLLocation *)object coordinate];
        if (CLLocationCoordinate2DIsValid(c) && isfinite(c.latitude) && isfinite(c.longitude) &&
            !(c.latitude == 0 && c.longitude == 0))
            return [NSString stringWithFormat:@"https://maps.google.com/maps?q=%.7f,%.7f",c.latitude,c.longitude];
    }
    if ([object isKindOfClass:[NSData class]]) {
        NSData *data = object;
        NSError *err = nil;
        id pl = [NSPropertyListSerialization propertyListWithData:data options:0 format:NULL error:&err];
        if (pl) { NSString *s = FindURL(pl,depth+1); if (s) return s; }
        // Some Shortcuts results contain a keyed archive of WFContentItem/NSURL.
        @try {
            id decoded = [NSKeyedUnarchiver unarchiveTopLevelObjectWithData:data error:&err];
            if (decoded) { NSString *s = FindURL(decoded,depth+1); if (s) return s; }
        } @catch (__unused NSException *e) {}
        return nil;
    }
    for (NSString *property in @[@"archivedOutput",@"archivedOutputs",@"output",@"outputs",@"outputValue",
                                 @"outputContentItems",@"contentItems",@"contentItem",@"value",@"location",
                                 @"URL",@"url",@"internalRepresentation",@"object"]) {
        id value = MsgGet(object,property);
        if (value && value != object) {
            NSString *s = FindURL(value,depth+1);
            if (s) return s;
        }
    }
    return nil;
}
static void Record(NSString *status, NSString *url) {
    if (!gToken.length) return;
    // Token is supplied by our SpringBoard tweak as a freshly generated UUID.
    NSString *path = [kResultDirectory stringByAppendingPathComponent:
       [NSString stringWithFormat:@"uk.551.no2theft.shortcutloc.%@.plist",gToken]];
    NSMutableDictionary *record = [@{@"status":status ?: @"unknown",
                                      @"date":[NSDate date],
                                      @"requestID":gToken} mutableCopy];
    if (IsMapURL(url)) record[@"mapURL"] = url;
    [record writeToFile:path atomically:YES];
    chmod(path.fileSystemRepresentation,0600);
}
@interface N2TWorkflowDelegate : NSObject
@end
@implementation N2TWorkflowDelegate
- (void)outOfProcessWorkflowController:(id)controller didStartFromWorkflowReference:(id)reference {
    (void)controller; (void)reference;
    atomic_store(&gWorkflowStarted,true);
}
- (void)outOfProcessWorkflowController:(id)controller didFinishWithResult:(id)result dialogAttribution:(id)dialog {
    (void)controller; (void)dialog;
    if (atomic_load(&gWorkflowFinished)) return;
    NSError *error = MsgGet(result,@"error");
    BOOL cancelled = NO;
    SEL cancelledSel = sel_registerName("isCancelled");
    if (result && [result respondsToSelector:cancelledSel])
        cancelled = ((BOOL (*)(id,SEL))objc_msgSend)(result,cancelledSel);
    if (error) gStatus = [NSString stringWithFormat:@"workflow_error_%ld",(long)error.code];
    else if (cancelled) gStatus = @"cancelled";
    else {
        gMapsURL = FindURL(result,0);
        gStatus = gMapsURL ? @"success" : (result ? @"no_map_output" : @"no_result");
    }
    atomic_store(&gWorkflowFinished,true);
}
@end
static void SetObj(id o, const char *s, id v) {
    SEL selector=sel_registerName(s);
    if (o && [o respondsToSelector:selector]) ((void(*)(id,SEL,id))objc_msgSend)(o,selector,v);
}
static void SetBool(id o, const char *s, BOOL v) {
    SEL selector=sel_registerName(s);
    if (o && [o respondsToSelector:selector]) ((void(*)(id,SEL,BOOL))objc_msgSend)(o,selector,v);
}
static void SetNumber(id o, const char *s, unsigned long long v) {
    SEL selector=sel_registerName(s);
    if (o && [o respondsToSelector:selector]) ((void(*)(id,SEL,unsigned long long))objc_msgSend)(o,selector,v);
}
static id NewObject(NSString *cls) {
    return [NSClassFromString(cls) alloc];
}
static NSData *MakeWorkflow(void) {
    NSDictionary *getLocation = @{
        @"WFWorkflowActionIdentifier": @"is.workflow.actions.getcurrentlocation",
        @"WFWorkflowActionParameters": @{@"UUID":[NSUUID UUID].UUIDString}};
    NSDictionary *getLink = @{
        @"WFWorkflowActionIdentifier": @"is.workflow.actions.getmapslink",
        @"WFWorkflowActionParameters": @{@"UUID":[NSUUID UUID].UUIDString}};
    NSDictionary *workflow=@{
        @"WFWorkflowClientVersion":@"1307.2",
        @"WFWorkflowClientRelease":@"6.0",
        @"WFWorkflowMinimumClientVersion":@900,
        @"WFWorkflowMinimumClientVersionString":@"900",
        @"WFWorkflowTypes":@[],
        @"WFWorkflowInputContentItemClasses":@[],
        @"WFWorkflowIcon":@{@"WFWorkflowIconStartColor":@4282601983,
                            @"WFWorkflowIconGlyphNumber":@61440},
        @"WFWorkflowActions":@[getLocation,getLink]
    };
    return [NSPropertyListSerialization dataWithPropertyList:workflow
          format:NSPropertyListBinaryFormat_v1_0 options:0 error:NULL];
}
static void RunLocationShortcut(void) {
    if (!dlopen("/System/Library/PrivateFrameworks/WorkflowKit.framework/WorkflowKit",RTLD_NOW|RTLD_GLOBAL)
      || !dlopen("/System/Library/PrivateFrameworks/VoiceShortcutClient.framework/VoiceShortcutClient",RTLD_NOW|RTLD_GLOBAL)) {
        gStatus=@"workflow_framework_unavailable"; return;
    }
    NSData *data=MakeWorkflow();
    id descriptor=((id(*)(id,SEL,id))objc_msgSend)(NewObject(@"WFWorkflowDataRunDescriptor"),
                          sel_registerName("initWithWorkflowData:"),data);
    id request=((id(*)(id,SEL,id,unsigned long long))objc_msgSend)(NewObject(@"WFWorkflowRunRequest"),
                         sel_registerName("initWithInput:presentationMode:"),nil,0);
    id context=((id(*)(id,SEL,id))objc_msgSend)(NewObject(@"WFWorkflowRunningContext"),
                         sel_registerName("initWithWorkflowIdentifier:"),
                         [NSString stringWithFormat:@"uk.551.no2theft.shortcutloc.%@",gToken]);
    if (!descriptor || !request || !context) {gStatus=@"workflow_class_unavailable";return;}
    SetObj(request,"setRunSource:",@"PersonalAutomation");
    SetObj(request,"setAutomationType:",@"PersonalAutomation");
    SetObj(request,"setParentBundleIdentifier:",@"com.apple.shortcuts");
    SetBool(request,"setAllowsDialogNotifications:",NO);
    SetBool(request,"setAllowsHandoff:",NO);
    SetBool(request,"setDonateInteraction:",NO);
    SetBool(request,"setLogRunEvent:",NO);
    SetNumber(request,"setOutputBehavior:",0);
    SetNumber(request,"setPresentationMode:",0);
    SetObj(context,"setIdentifier:",[NSString stringWithFormat:@"uk.551.no2theft.shortcutloc.%@",gToken]);
    SetObj(context,"setRootWorkflowIdentifier:",[NSString stringWithFormat:@"uk.551.no2theft.shortcutloc.%@",gToken]);
    SetObj(context,"setWorkflowIdentifier:",[NSString stringWithFormat:@"uk.551.no2theft.shortcutloc.%@",gToken]);
    SetObj(context,"setRunSource:",@"PersonalAutomation");
    SetObj(context,"setAutomationType:",@"PersonalAutomation");
    SetObj(context,"setOriginatingBundleIdentifier:",@"com.apple.shortcuts");
    SetBool(context,"setAllowsDialogNotifications:",NO);
    SetNumber(context,"setOutputBehavior:",0);
    SetNumber(context,"setPresentationMode:",0);

    id allocated=NewObject(@"WFOutOfProcessWorkflowController"), controller=nil;
    SEL initializer4=sel_registerName("initWithEnvironment:runningContext:databaseProvider:presentationMode:");
    SEL initializer3=sel_registerName("initWithEnvironment:runningContext:presentationMode:");
    if ([allocated respondsToSelector:initializer4])
        controller=((id(*)(id,SEL,long long,id,id,long long))objc_msgSend)(allocated,initializer4,0,context,nil,0);
    else if ([allocated respondsToSelector:initializer3])
        controller=((id(*)(id,SEL,long long,id,long long))objc_msgSend)(allocated,initializer3,0,context,0);
    if (!controller) { gStatus=@"controller_unavailable"; return; }
    N2TWorkflowDelegate *delegate=[N2TWorkflowDelegate new];
    SetObj(controller,"setDelegate:",delegate);
    SEL run=sel_registerName("runWorkflowWithDescriptor:request:error:");
    if (![controller respondsToSelector:run]) {gStatus=@"run_method_unavailable";return;}
    NSError *error=nil;
    BOOL accepted=((BOOL(*)(id,SEL,id,id,NSError**))objc_msgSend)(controller,run,descriptor,request,&error);
    if (!accepted) {gStatus=[NSString stringWithFormat:@"request_rejected_%ld",(long)error.code];return;}
    // The Get Current Location action requires WFMainThreadResource. A
    // semaphore blocking this command-line tool's main thread can prevent
    // WorkflowKit/ActionKit from dispatching progress and completion callbacks.
    // Keep the run loop alive while the one-shot workflow is in progress.
    NSDate *deadline=[NSDate dateWithTimeIntervalSinceNow:22.0];
    while (!atomic_load(&gWorkflowFinished) && [deadline timeIntervalSinceNow]>0) {
        @autoreleasepool {
            [[NSRunLoop currentRunLoop] runMode:NSDefaultRunLoopMode
                beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.08]];
        }
    }
    if (!atomic_load(&gWorkflowFinished)) {
        gStatus=atomic_load(&gWorkflowStarted)
             ? @"workflow_timeout_after_start" : @"workflow_timeout_no_start";
        SEL stop=sel_registerName("stop");
        if ([controller respondsToSelector:stop]) ((void(*)(id,SEL))objc_msgSend)(controller,stop);
    }
}
int main(int argc, char **argv) {
    @autoreleasepool {
        if (argc!=2) return 2;
        NSString *token=[NSString stringWithUTF8String:argv[1]];
        NSCharacterSet *allowed=[NSCharacterSet characterSetWithCharactersInString:@"0123456789ABCDEFabcdef-"];
        if (token.length<32 || token.length>40 ||
            [[token stringByTrimmingCharactersInSet:allowed] length]!=0) return 2;
        gToken=token;
        atomic_init(&gWorkflowFinished,false);
        atomic_init(&gWorkflowStarted,false);
        gStatus=nil;
        @try { RunLocationShortcut(); }
        @catch (__unused NSException *e) { gStatus=@"workflow_exception"; }
        Record(gStatus?:@"unknown",gMapsURL);
        return [gStatus isEqualToString:@"success"]?0:1;
    }
}

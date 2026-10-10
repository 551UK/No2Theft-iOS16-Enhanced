#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import <substrate.h>
#import <spawn.h>
#import <sys/wait.h>
#import <unistd.h>

extern char **environ;
@interface SKPSMTPMessage : NSObject
- (NSArray *)parts;
- (void)setParts:(NSArray *)parts;
- (void)send;
@end

static void (*gOriginalSend)(id, SEL);
static NSRegularExpression *gPattern;
static NSString *const kPartText = @"kSKPSMTPPartMessageKey";
static NSString *const kResultDir = @"/var/mobile/Library/Preferences";
static NSString *const kHelperPath = @"/var/jb/usr/bin/N2TShortcutLocation";

static NSString *PlainText(id value) {
    if ([value isKindOfClass:[NSString class]]) return value;
    if ([value isKindOfClass:[NSData class]])
        return [[NSString alloc] initWithData:value encoding:NSUTF8StringEncoding];
    return nil;
}
static BOOL HasMap(id message) {
    NSArray *parts = [message respondsToSelector:@selector(parts)] ? [message parts] : nil;
    if (![parts isKindOfClass:[NSArray class]]) return NO;
    for (id part in parts) {
        if (![part isKindOfClass:[NSDictionary class]]) continue;
        NSString *body=PlainText(part[kPartText]);
        if (body && [gPattern firstMatchInString:body options:0
                         range:NSMakeRange(0,body.length)]) return YES;
    }
    return NO;
}
static NSString *SafeStatus(NSString *value) {
    if (!value.length || value.length>100) return @"no_result";
    NSMutableString *out=[NSMutableString string];
    NSCharacterSet *allowed=[NSCharacterSet characterSetWithCharactersInString:
       @"abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_-"];
    for (NSUInteger i=0;i<value.length;i++) {
        unichar c=[value characterAtIndex:i];
        if ([allowed characterIsMember:c]) [out appendFormat:@"%C",c];
    }
    return out.length ? out : @"no_result";
}
static void ReplaceMap(id message, NSString *url, NSString *reason) {
    if (![message respondsToSelector:@selector(parts)] ||
        ![message respondsToSelector:@selector(setParts:)]) return;
    NSArray *parts=[message parts];
    if (![parts isKindOfClass:[NSArray class]]) return;
    NSString *replacement=url.length ? url : [NSString stringWithFormat:
        @"GPS location unavailable (Shortcuts: %@)",SafeStatus(reason)];
    NSMutableArray *out=[NSMutableArray arrayWithCapacity:parts.count];
    BOOL altered=NO;
    for (id part in parts) {
        if (![part isKindOfClass:[NSDictionary class]]) {[out addObject:part];continue;}
        id original=part[kPartText];
        NSString *body=PlainText(original);
        if (!body) {[out addObject:part];continue;}
        NSString *revised=[gPattern stringByReplacingMatchesInString:body options:0
            range:NSMakeRange(0,body.length) withTemplate:replacement];
        if ([revised isEqualToString:body]) {[out addObject:part];continue;}
        NSMutableDictionary *copy=[part mutableCopy];
        copy[kPartText]=[original isKindOfClass:[NSData class]]
            ? [revised dataUsingEncoding:NSUTF8StringEncoding] : revised;
        [out addObject:copy];
        altered=YES;
    }
    if (altered) [message setParts:out];
}
static NSString *AllowedMap(NSString *url) {
    if (![url isKindOfClass:[NSString class]] || url.length>1000) return nil;
    NSString *lower=url.lowercaseString;
    if ([lower hasPrefix:@"https://maps.apple.com/"] ||
        [lower hasPrefix:@"https://maps.google.com/"] ||
        [lower hasPrefix:@"https://www.google.com/maps"]) return url;
    return nil;
}
static void WriteStatus(NSString *status) {
    NSDictionary *value=@{@"date":[NSDate date],@"status":SafeStatus(status)};
    [value writeToFile:[kResultDir stringByAppendingPathComponent:
           @"uk.551.no2theft.shortcutloc.last.plist"] atomically:YES];
}
static NSDictionary *RunShortcutHelperOnce(void) {
    NSString *token=[NSUUID UUID].UUIDString;
    NSString *file=[kResultDir stringByAppendingPathComponent:
       [NSString stringWithFormat:@"uk.551.no2theft.shortcutloc.%@.plist",token]];
    if (![[NSFileManager defaultManager] isExecutableFileAtPath:kHelperPath])
        return @{@"status":@"helper_not_installed"};
    pid_t pid=0;
    char *argv[]={ (char*)kHelperPath.fileSystemRepresentation,
                   (char*)token.UTF8String, NULL };
    int result=posix_spawn(&pid,kHelperPath.fileSystemRepresentation,NULL,NULL,argv,environ);
    if (result!=0) return @{@"status":[NSString stringWithFormat:@"spawn_errno_%d",result]};
    NSDictionary *response=nil;
    NSDate *deadline=[NSDate dateWithTimeIntervalSinceNow:25];
    while ([deadline timeIntervalSinceNow]>0) {
        response=[NSDictionary dictionaryWithContentsOfFile:file];
        if ([response[@"requestID"] isEqualToString:token]) break;
        response=nil;
        [NSThread sleepForTimeInterval:0.25];
    }
    // The helper writes its response and then exits; reap asynchronously so
    // neither SpringBoard's main thread nor the SMTP send can be blocked.
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY,0), ^{
        if (pid>0) waitpid(pid,NULL,0);
    });
    [[NSFileManager defaultManager] removeItemAtPath:file error:NULL];
    if (!response) return @{@"status":@"helper_timeout"};
    return response;
}
static void N2TSendIntercept(id message,SEL selector) {
    if (!gOriginalSend) return;
    BOOL containsMap=NO;
    @try { containsMap=(gPattern && HasMap(message)); }
    @catch (__unused NSException *e) {}
    if (!containsMap) {gOriginalSend(message,selector);return;}
    // The SMTP message stays alive while a one-shot helper runs.
    SKPSMTPMessage *saved=message;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY,0), ^{
        NSDictionary *result=nil;
        @try { result=RunShortcutHelperOnce(); }
        @catch (__unused NSException *e) {result=@{@"status":@"helper_exception"};}
        NSString *status=SafeStatus(result[@"status"]);
        NSString *url=[status isEqualToString:@"success"] ? AllowedMap(result[@"mapURL"]) : nil;
        if (!url && [status isEqualToString:@"success"]) status=@"invalid_map_output";
        WriteStatus(status);
        dispatch_async(dispatch_get_main_queue(), ^{
            @try { ReplaceMap(saved,url,status); }
            @catch (__unused NSException *e) {}
            // Always attempt the original photo+Gmail email, even if GPS fails.
            gOriginalSend(saved,selector);
        });
    });
}
__attribute__((constructor)) static void N2TInstallShortcutsLocation(void) {
    @autoreleasepool {
        if (![[NSProcessInfo processInfo].processName isEqualToString:@"SpringBoard"]) return;
        gPattern=[NSRegularExpression regularExpressionWithPattern:
           @"https?://maps\\.google\\.com/maps\\?q=[^\\s<>\\\"']+"
           options:NSRegularExpressionCaseInsensitive error:NULL];
        Class cls=objc_getClass("SKPSMTPMessage");
        if (cls && class_getInstanceMethod(cls,@selector(send)))
            MSHookMessageEx(cls,@selector(send),(IMP)N2TSendIntercept,(IMP *)&gOriginalSend);
    }
}

#import <Foundation/Foundation.h>
#import <CoreLocation/CoreLocation.h>
#import <objc/runtime.h>
#import <substrate.h>
#import <math.h>

@interface INTULocationManager : NSObject
+ (instancetype)sharedInstance;
- (NSInteger)requestLocationWithDesiredAccuracy:(NSUInteger)accuracy timeout:(NSTimeInterval)timeout block:(void (^)(CLLocation *, NSUInteger, NSUInteger))block;
@end
@interface SKPSMTPMessage : NSObject
- (NSArray *)parts;
- (void)setParts:(NSArray *)parts;
- (void)send;
@end

static void (*priorSend)(id, SEL);
static NSRegularExpression *mapPattern;
static NSString *const key = @"kSKPSMTPPartMessageKey";

// Reject only unusable coordinates, never by age or horizontal accuracy.
static BOOL isValidCoordinate(CLLocation *loc) {
    if (!loc) return NO;
    CLLocationCoordinate2D c = loc.coordinate;
    return CLLocationCoordinate2DIsValid(c) &&
           isfinite(c.latitude) && isfinite(c.longitude) &&
           !(c.latitude == 0.0 && c.longitude == 0.0);
}
static NSString *textOf(id value) {
    if ([value isKindOfClass:[NSString class]]) return value;
    if ([value isKindOfClass:[NSData class]]) return [[NSString alloc] initWithData:value encoding:NSUTF8StringEncoding];
    return nil;
}
static BOOL containsMap(id message) {
    if (![message respondsToSelector:@selector(parts)]) return NO;
    NSArray *parts = [message parts];
    if (![parts isKindOfClass:[NSArray class]]) return NO;
    for (id part in parts) {
        if (![part isKindOfClass:[NSDictionary class]]) continue;
        NSString *body = textOf(part[key]);
        if (body && [mapPattern firstMatchInString:body options:0 range:NSMakeRange(0, body.length)]) return YES;
    }
    return NO;
}
static void updateMap(id message, CLLocation *location, NSString *reason) {
    if (![message respondsToSelector:@selector(parts)] || ![message respondsToSelector:@selector(setParts:)]) return;
    NSArray *parts = [message parts];
    if (![parts isKindOfClass:[NSArray class]]) return;
    NSString *url = isValidCoordinate(location)
        ? [NSString stringWithFormat:@"https://maps.google.com/maps?q=%.7f,%.7f", location.coordinate.latitude, location.coordinate.longitude]
        : [NSString stringWithFormat:@"GPS location unavailable (%@)", reason ?: @"unknown reason"];
    NSMutableArray *edited = [NSMutableArray arrayWithCapacity:parts.count];
    BOOL altered = NO;
    for (id part in parts) {
        if (![part isKindOfClass:[NSDictionary class]]) { [edited addObject:part]; continue; }
        id original = part[key];
        NSString *body = textOf(original);
        if (!body) { [edited addObject:part]; continue; }
        NSString *changed = [mapPattern stringByReplacingMatchesInString:body options:0 range:NSMakeRange(0, body.length) withTemplate:url];
        if ([changed isEqualToString:body]) { [edited addObject:part]; continue; }
        NSMutableDictionary *copy = [part mutableCopy];
        copy[key] = [original isKindOfClass:[NSData class]] ? [changed dataUsingEncoding:NSUTF8StringEncoding] : changed;
        [edited addObject:copy];
        altered = YES;
    }
    if (altered) [message setParts:edited];
}
static void gpsSend(id message, SEL selector) {
    if (!priorSend) return;
    BOOL shouldReplace = NO;
    @try { shouldReplace = mapPattern && containsMap(message); }
    @catch (NSException *e) {}
    if (!shouldReplace) { priorSend(message, selector); return; }
    SKPSMTPMessage *saved = message;
    dispatch_async(dispatch_get_main_queue(), ^{
        __block BOOL done = NO;
        void (^finish)(CLLocation *, NSString *) = ^(CLLocation *loc, NSString *reason) {
            dispatch_async(dispatch_get_main_queue(), ^{
                if (done) return;
                done = YES;
                @try { updateMap(saved, loc, reason); } @catch (NSException *e) {}
                priorSend(saved, selector);
            });
        };

        // Let INTULocationManager itself attempt location acquisition.
        // A different app's authorization status must not block the attempt.
        // The timeout is only to ensure the alarm email is eventually sent.
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 24 * NSEC_PER_SEC),
                       dispatch_get_main_queue(), ^{ finish(nil, @"24-second GPS timeout"); });
        @try {
            Class managerClass = objc_getClass("INTULocationManager");
            if (!managerClass || ![managerClass respondsToSelector:@selector(sharedInstance)]) {
                finish(nil, @"GPS manager unavailable"); return;
            }
            id manager = [managerClass sharedInstance];
            if (!manager || ![manager respondsToSelector:@selector(requestLocationWithDesiredAccuracy:timeout:block:)]) {
                finish(nil, @"GPS request method unavailable"); return;
            }
            [manager requestLocationWithDesiredAccuracy:5 timeout:22.0
                                                  block:^(CLLocation *loc, NSUInteger accuracy, NSUInteger status) {
                // Always send coordinates supplied by CoreLocation, regardless
                // of age, accuracy or provider status.
                if (isValidCoordinate(loc)) {
                    finish(loc, nil);
                } else {
                    finish(nil, [NSString stringWithFormat:@"no GPS coordinates returned (status %lu)",
                                          (unsigned long)status]);
                }
            }];
        } @catch (NSException *e) { finish(nil, @"GPS request exception"); }
    });
}
__attribute__((constructor)) static void installGPSLinkFix(void) {
    @autoreleasepool {
        mapPattern = [NSRegularExpression regularExpressionWithPattern:@"https?://maps\\.google\\.com/maps\\?q=[^\\s<>\\\"']+"
                         options:NSRegularExpressionCaseInsensitive error:NULL];
        Class cls = objc_getClass("SKPSMTPMessage");
        if (cls && class_getInstanceMethod(cls, @selector(send)))
            MSHookMessageEx(cls, @selector(send), (IMP)gpsSend, (IMP *)&priorSend);
    }
}

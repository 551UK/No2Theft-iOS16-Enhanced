#import <Foundation/Foundation.h>
#import <CoreLocation/CoreLocation.h>
#import <objc/runtime.h>
#import <substrate.h>
#import <math.h>

// This companion does not modify the known-good No2Theft Email Fix binary.
// The original tweak already bundles the INTULocationManager runtime class.
@interface INTULocationManager : NSObject
+ (instancetype)sharedInstance;
- (NSInteger)requestLocationWithDesiredAccuracy:(NSUInteger)accuracy
                                         timeout:(NSTimeInterval)timeout
                                           block:(void (^)(CLLocation *location, NSUInteger accuracy, NSUInteger status))block;
@end

typedef void (^N2TSuccess)(NSURLSessionDataTask *task, id response);
typedef void (^N2TFailure)(NSURLSessionDataTask *task, NSError *error);

typedef NSURLSessionDataTask *(*Get4IMP)(id self, SEL cmd,
    NSString *url, id parameters, N2TSuccess success, N2TFailure failure);
typedef NSURLSessionDataTask *(*Get5IMP)(id self, SEL cmd,
    NSString *url, id parameters, id progress, N2TSuccess success, N2TFailure failure);

static Get4IMP originalGET4;
static Get5IMP originalGET5;

static BOOL goodGPS(CLLocation *loc) {
    if (!loc) return NO;
    CLLocationCoordinate2D coordinate = loc.coordinate;
    if (!CLLocationCoordinate2DIsValid(coordinate)) return NO;
    if (!isfinite(coordinate.latitude) || !isfinite(coordinate.longitude)) return NO;
    if (coordinate.latitude == 0 && coordinate.longitude == 0) return NO;
    if (loc.horizontalAccuracy < 0 || loc.horizontalAccuracy > 30.0) return NO;
    NSTimeInterval age = [[NSDate date] timeIntervalSinceDate:loc.timestamp];
    if (age < -2.0 || age > 20.0) return NO;
    return YES;
}

// Preserve the schema No2Theft expects to assemble its existing email.
// No coordinates are written to NSLog or a file.
static void completeWithCoordinates(N2TSuccess completion, CLLocation *location) {
    NSString *coordinates = goodGPS(location)
        ? [NSString stringWithFormat:@"%.7f,%.7f", location.coordinate.latitude,
                                                      location.coordinate.longitude]
        : @"GPS unavailable,GPS unavailable";
    completion(nil, @{ @"loc": coordinates, @"city": @"", @"region": @"", @"country": @"" });
}

static void supplyGPS(N2TSuccess success) {
    if (!success) return;
    N2TSuccess completion = [success copy];

    // Location manager requests should start on main thread.
    dispatch_async(dispatch_get_main_queue(), ^{
        Class managerClass = objc_getClass("INTULocationManager");
        SEL selector = @selector(requestLocationWithDesiredAccuracy:timeout:block:);
        if (!managerClass || ![managerClass respondsToSelector:@selector(sharedInstance)]) {
            completeWithCoordinates(completion, nil);
            return;
        }
        id manager = [managerClass sharedInstance];
        if (!manager || ![manager respondsToSelector:selector]) {
            completeWithCoordinates(completion, nil);
            return;
        }

        // INTULocationAccuracyHouse = 4. Request a current/high-accuracy reading.
        [manager requestLocationWithDesiredAccuracy:4 timeout:12.0
                                             block:^(CLLocation *location, NSUInteger accuracy, NSUInteger status) {
            completeWithCoordinates(completion, location);
        }];
    });
}

static BOOL isIPInfoURL(NSString *url) {
    if (![url isKindOfClass:[NSString class]]) return NO;
    NSURLComponents *parts = [NSURLComponents componentsWithString:url];
    NSString *host = [parts.host lowercaseString];
    return [host isEqualToString:@"ipinfo.io"] ||
           [host isEqualToString:@"www.ipinfo.io"];
}

static NSURLSessionDataTask *gpsGET4(id self, SEL cmd,
    NSString *url, id parameters, N2TSuccess success, N2TFailure failure) {
    if (!isIPInfoURL(url))
        return originalGET4(self, cmd, url, parameters, success, failure);
    supplyGPS(success);
    return nil; // Never contact the IP-location service on this intercepted path.
}

static NSURLSessionDataTask *gpsGET5(id self, SEL cmd,
    NSString *url, id parameters, id progress,
    N2TSuccess success, N2TFailure failure) {
    if (!isIPInfoURL(url))
        return originalGET5(self, cmd, url, parameters, progress, success, failure);
    supplyGPS(success);
    return nil;
}

__attribute__((constructor)) static void installGPSHook(void) {
    // Naming the dylib ZZNo2TheftGPS normally loads it after No2Theft.
    Class af = objc_getClass("AFHTTPSessionManager");
    if (!af) return;

    SEL four = sel_registerName("GET:parameters:success:failure:");
    if (class_getInstanceMethod(af, four))
        MSHookMessageEx(af, four, (IMP)gpsGET4, (IMP *)&originalGET4);

    SEL five = sel_registerName("GET:parameters:progress:success:failure:");
    if (class_getInstanceMethod(af, five))
        MSHookMessageEx(af, five, (IMP)gpsGET5, (IMP *)&originalGET5);
}

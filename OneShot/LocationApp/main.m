#import <UIKit/UIKit.h>
#import <CoreLocation/CoreLocation.h>
#import <math.h>
#import <sys/stat.h>

static NSString * const kN2TLocationOutputRoot=@"/var/mobile/Library/Preferences";

@interface N2TOneShotLocation : NSObject <CLLocationManagerDelegate>
@property(nonatomic,strong) CLLocationManager *manager;
@property(nonatomic,strong) NSString *token;
@property(nonatomic,assign) BOOL done;
@property(nonatomic,copy) NSString *status;
@property(nonatomic,strong) CLLocation *location;
- (int)runWithToken:(NSString *)token;
@end

@implementation N2TOneShotLocation
- (void)finish:(NSString *)status location:(CLLocation *)location {
    if (self.done) return;
    self.done=YES;
    self.status=status;
    self.location=location;
    [self.manager stopUpdatingLocation];
}
- (void)locationManager:(CLLocationManager *)manager didUpdateLocations:(NSArray<CLLocation *> *)locations {
    for (CLLocation *loc in [locations reverseObjectEnumerator]) {
        CLLocationCoordinate2D c=loc.coordinate;
        if (CLLocationCoordinate2DIsValid(c) && isfinite(c.latitude) && isfinite(c.longitude)
          && (c.latitude!=0 || c.longitude!=0)) {
            [self finish:@"success" location:loc];
            return;
        }
    }
}
- (void)locationManager:(CLLocationManager *)manager didFailWithError:(NSError *)error {
    [self finish:[NSString stringWithFormat:@"clerror_%ld",(long)error.code] location:nil];
}
- (int)runWithToken:(NSString *)token {
    self.token=token;
    self.manager=[CLLocationManager new];
    self.manager.delegate=self;
    self.manager.desiredAccuracy=kCLLocationAccuracyBest;
    self.manager.distanceFilter=kCLDistanceFilterNone;
    CLAuthorizationStatus auth=self.manager.authorizationStatus;
    NSDictionary *start=@{@"status":@"starting",@"authorization":@(auth),
                           @"identifier":NSBundle.mainBundle.bundleIdentifier?:@"none"};
    NSString *path=[kN2TLocationOutputRoot stringByAppendingPathComponent:
       [NSString stringWithFormat:@"uk.551.no2theft.onceloc.%@.plist",token]];
    // Write explicit permission diagnostics even if requesting GPS fails.
    [start writeToFile:path atomically:YES];
    chmod(path.fileSystemRepresentation,0600);
    if (![CLLocationManager locationServicesEnabled]) [self finish:@"services_disabled" location:nil];
    else if (auth==kCLAuthorizationStatusNotDetermined) [self finish:@"permission_not_determined" location:nil];
    else if (auth==kCLAuthorizationStatusDenied) [self finish:@"permission_denied" location:nil];
    else if (auth==kCLAuthorizationStatusRestricted) [self finish:@"permission_restricted" location:nil];
    else {
        // Only invoke location updates after the alarm helper starts. No daemon
        // or permanently active location session is installed.
        @try { [self.manager startUpdatingLocation]; }
        @catch (__unused NSException *ex) { [self finish:@"location_exception" location:nil]; }
    }
    NSDate *limit=[NSDate dateWithTimeIntervalSinceNow:18.0];
    while (!self.done && [limit timeIntervalSinceNow]>0) {
        @autoreleasepool {
            [[NSRunLoop currentRunLoop] runMode:NSDefaultRunLoopMode
                 beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.08]];
        }
    }
    if (!self.done) [self finish:@"location_timeout" location:nil];
    NSMutableDictionary *result=[@{@"status":self.status?:@"unknown",
           @"authorization":@(auth),
           @"identifier":NSBundle.mainBundle.bundleIdentifier?:@"none",
           @"date":[NSDate date],@"requestID":token} mutableCopy];
    if (self.location) {
        CLLocationCoordinate2D c=self.location.coordinate;
        result[@"mapURL"]=[NSString stringWithFormat:@"https://maps.google.com/maps?q=%.7f,%.7f",
                             c.latitude,c.longitude];
        result[@"accuracyMeters"]=@(self.location.horizontalAccuracy);
    }
    [result writeToFile:path atomically:YES];
    chmod(path.fileSystemRepresentation,0600);
    return [self.status isEqualToString:@"success"]?0:1;
}
@end

@interface N2TLocationController : UIViewController <CLLocationManagerDelegate>
@property(nonatomic,strong) CLLocationManager *manager;
@property(nonatomic,strong) UITextView *information;
@end
@implementation N2TLocationController
- (UIButton *)button:(NSString *)text action:(SEL)action {
    UIButton *button=[UIButton buttonWithType:UIButtonTypeSystem];
    UIButtonConfiguration *c=[UIButtonConfiguration tintedButtonConfiguration];
    c.contentInsets=NSDirectionalEdgeInsetsMake(17,12,17,12);
    button.configuration=c;
    [button setTitle:text forState:UIControlStateNormal];
    [button addTarget:self action:action forControlEvents:UIControlEventTouchUpInside];
    [button.heightAnchor constraintEqualToConstant:54].active=YES;
    return button;
}
- (void)viewDidLoad {
    [super viewDidLoad];
    self.title=@"No2Theft Location";
    self.view.backgroundColor=UIColor.systemBackgroundColor;
    UILabel *heading=[UILabel new];
    heading.numberOfLines=0;
    heading.text=@"No2Theft On-Demand GPS Permission";
    heading.font=[UIFont boldSystemFontOfSize:23];
    UILabel *note=[UILabel new];
    note.numberOfLines=0;
    note.text=@"This app requests GPS permission once. No2Theft launches its executable only during a security alarm. It does not track you continuously.";
    note.font=[UIFont systemFontOfSize:15];
    self.information=[UITextView new];
    self.information.editable=NO;
    self.information.font=[UIFont monospacedSystemFontOfSize:14 weight:UIFontWeightRegular];
    self.information.backgroundColor=UIColor.secondarySystemBackgroundColor;
    self.information.layer.cornerRadius=10;
    [self.information.heightAnchor constraintEqualToConstant:230].active=YES;
    UIStackView *stack=[[UIStackView alloc] initWithArrangedSubviews:@[
       heading,note,
       [self button:@"1. Allow Location" action:@selector(requestWhenInUse)],
       [self button:@"2. Request Always Permission" action:@selector(requestAlways)],
       [self button:@"3. Check GPS Now" action:@selector(checkGPS)],
       [self button:@"4. Show Permission Status" action:@selector(showAuth)],
       self.information
    ]];
    stack.axis=UILayoutConstraintAxisVertical;
    stack.spacing=12;
    stack.translatesAutoresizingMaskIntoConstraints=NO;
    UIScrollView *scroll=[UIScrollView new];
    scroll.translatesAutoresizingMaskIntoConstraints=NO;
    [self.view addSubview:scroll];
    [scroll addSubview:stack];
    UILayoutGuide *safe=self.view.safeAreaLayoutGuide;
    [NSLayoutConstraint activateConstraints:@[
       [scroll.leadingAnchor constraintEqualToAnchor:safe.leadingAnchor],
       [scroll.trailingAnchor constraintEqualToAnchor:safe.trailingAnchor],
       [scroll.topAnchor constraintEqualToAnchor:safe.topAnchor],
       [scroll.bottomAnchor constraintEqualToAnchor:safe.bottomAnchor],
       [stack.leadingAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.leadingAnchor constant:20],
       [stack.trailingAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.trailingAnchor constant:-20],
       [stack.topAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.topAnchor constant:20],
       [stack.bottomAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.bottomAnchor constant:-20],
       [stack.widthAnchor constraintEqualToAnchor:scroll.frameLayoutGuide.widthAnchor constant:-40]
    ]];
    self.manager=[CLLocationManager new];
    self.manager.delegate=self;
    self.manager.desiredAccuracy=kCLLocationAccuracyBest;
    [self showAuth];
}
- (void)showAuth {
    self.information.text=[NSString stringWithFormat:
         @"CoreLocation permission: %ld\n\n0 = Not Determined\n3 = While Using\n4 = Always\n\nFor an on-demand request made while the phone is locked, Always permission may be required. This button does not start tracking.",
         (long)self.manager.authorizationStatus];
}
- (void)requestWhenInUse {
    [self.manager requestWhenInUseAuthorization];
    self.information.text=@"Waiting for iOS Location permission dialog. Choose Allow While Using App.";
}
- (void)requestAlways {
    [self.manager requestAlwaysAuthorization];
    self.information.text=@"Requested Always permission. iOS controls the prompt and may ask again later. Granting Always does not mean continuous GPS tracking.";
}
- (void)checkGPS {
    CLAuthorizationStatus s=self.manager.authorizationStatus;
    if (s!=kCLAuthorizationStatusAuthorizedAlways && s!=kCLAuthorizationStatusAuthorizedWhenInUse) {
        [self showAuth];return;
    }
    [self.manager startUpdatingLocation];
    self.information.text=@"Testing foreground GPS (no network request)...";
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW,15*NSEC_PER_SEC),dispatch_get_main_queue(),^{
        [self.manager stopUpdatingLocation];
        if ([self.information.text hasPrefix:@"Testing"]) self.information.text=@"Foreground location test timed out.";
    });
}
- (void)locationManagerDidChangeAuthorization:(CLLocationManager *)manager { [self showAuth]; }
- (void)locationManager:(CLLocationManager *)manager didFailWithError:(NSError *)error {
    [self.manager stopUpdatingLocation];
    self.information.text=[NSString stringWithFormat:@"Foreground GPS failed: %@ (%ld)",
                             error.domain,(long)error.code];
}
- (void)locationManager:(CLLocationManager *)manager didUpdateLocations:(NSArray<CLLocation *> *)locations {
    CLLocation *loc=locations.lastObject;
    [self.manager stopUpdatingLocation];
    self.information.text=[NSString stringWithFormat:
      @"Foreground GPS SUCCESS\nLocation: %.6f, %.6f\nAccuracy: %.0f m\nPermission: %ld",
      loc.coordinate.latitude,loc.coordinate.longitude,loc.horizontalAccuracy,
      (long)manager.authorizationStatus];
}
@end

@interface N2TLocationAppDelegate : UIResponder <UIApplicationDelegate>
@property(nonatomic,strong) UIWindow *window;
@end
@implementation N2TLocationAppDelegate
- (BOOL)application:(UIApplication *)app didFinishLaunchingWithOptions:(NSDictionary *)options {
    self.window=[[UIWindow alloc] initWithFrame:UIScreen.mainScreen.bounds];
    self.window.rootViewController=[[UINavigationController alloc]
         initWithRootViewController:[N2TLocationController new]];
    [self.window makeKeyAndVisible];
    return YES;
}
@end

int main(int argc,char **argv) {
    @autoreleasepool {
        if (argc==3 && strcmp(argv[1],"--once")==0) {
            NSString *token=[NSString stringWithUTF8String:argv[2]];
            NSCharacterSet *valid=[NSCharacterSet characterSetWithCharactersInString:
                                            @"0123456789ABCDEFabcdef-"];
            if (token.length<32 || token.length>40 ||
               [[token stringByTrimmingCharactersInSet:valid] length]>0) return 2;
            return [[N2TOneShotLocation new] runWithToken:token];
        }
        return UIApplicationMain(argc,argv,nil,NSStringFromClass([N2TLocationAppDelegate class]));
    }
}

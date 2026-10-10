#import <Foundation/Foundation.h>
#import <Preferences/PSListController.h>
#import <Preferences/PSSpecifier.h>

static NSString *const N2TPrefsDomain=@"com.elias.no2theft3";

@interface N2TSMSNumbersController : PSListController
@end

@implementation N2TSMSNumbersController

- (NSArray *)specifiers {
    if (!_specifiers) _specifiers=[self loadSpecifiersFromPlistName:@"SMSNumbers" target:self];
    return _specifiers;
}

- (id)readPreferenceValue:(PSSpecifier *)specifier {
    NSString *key=[specifier propertyForKey:@"key"];
    if(![key isEqualToString:@"firstNumber"] && ![key isEqualToString:@"secondNumber"])
        return @"";
    id value=CFBridgingRelease(CFPreferencesCopyAppValue((__bridge CFStringRef)key,
                                                      (__bridge CFStringRef)N2TPrefsDomain));
    return [value isKindOfClass:NSString.class] ? value : @"";
}

- (void)setPreferenceValue:(id)value specifier:(PSSpecifier *)specifier {
    NSString *key=[specifier propertyForKey:@"key"];
    if(![key isEqualToString:@"firstNumber"] && ![key isEqualToString:@"secondNumber"])
        return;
    if(![value isKindOfClass:NSString.class])return;
    // Do not write other settings, post alarm-state notifications, or
    // modify the original settings specifier list.
    CFPreferencesSetAppValue((__bridge CFStringRef)key,
                             (__bridge CFStringRef)value,
                             (__bridge CFStringRef)N2TPrefsDomain);
    CFPreferencesAppSynchronize((__bridge CFStringRef)N2TPrefsDomain);
}
@end

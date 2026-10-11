#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <Preferences/PSTableCell.h>

// Settings-only presentation. This class has NO hooks and touches NO preferences.
// It is used only by the dedicated PSGroupCell immediately below the main header.
@protocol PreferencesTableCustomView
- (instancetype)initWithSpecifier:(id)specifier;
- (CGFloat)preferredHeightForWidth:(CGFloat)width;
@end

@interface N2TGPSNoticeCell : PSTableCell <PreferencesTableCustomView>
@property (nonatomic, strong) UILabel *notice;
@end

@implementation N2TGPSNoticeCell

- (instancetype)initWithSpecifier:(id)specifier {
    self = [super initWithStyle:UITableViewCellStyleDefault
               reuseIdentifier:@"N2TGPSNoticeCell"
                      specifier:specifier];
    if (self) {
        self.backgroundColor = [UIColor clearColor];
        self.contentView.backgroundColor = [UIColor clearColor];
        _notice = [[UILabel alloc] initWithFrame:CGRectZero];
        _notice.numberOfLines = 0;
        _notice.textAlignment = NSTextAlignmentCenter;
        _notice.lineBreakMode = NSLineBreakByWordWrapping;
        _notice.textColor = [UIColor systemRedColor];
        _notice.font = [UIFont boldSystemFontOfSize:14.0];
        _notice.text = @"OPEN THE NO2THEFT LOCATION APP ON YOUR HOME SCREEN.\n"
                       @"ALLOW LOCATION ACCESS AND ENABLE PRECISE LOCATION "
                       @"FOR ACCURATE GPS ALERTS.";
        _notice.adjustsFontSizeToFitWidth = NO;
        _notice.isAccessibilityElement = YES;
        _notice.accessibilityLabel = _notice.text;
        [self.contentView addSubview:_notice];
        self.selectionStyle = UITableViewCellSelectionStyleNone;
    }
    return self;
}

- (void)layoutSubviews {
    [super layoutSubviews];
    CGRect bounds = self.contentView.bounds;
    self.notice.frame = CGRectInset(bounds, 18, 8);
}

- (CGFloat)preferredHeightForWidth:(CGFloat)width {
    return 120.0;
}
- (CGFloat)preferredHeightForWidth:(CGFloat)width inTableView:(id)tableView {
    return [self preferredHeightForWidth:width];
}
@end

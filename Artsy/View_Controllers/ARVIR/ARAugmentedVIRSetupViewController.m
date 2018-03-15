@import AVKit;
@import ARKit;

#import <Artsy-UIButtons/ARButtonSubclasses.h>
#import <Artsy+UILabels/Artsy+UILabels.h>
#import <Artsy+UIFonts/UIFont+ArtsyFonts.h>
#import <FLKAutoLayout/FLKAutoLayout.h>
#import <UIView+BooleanAnimations/UIView+BooleanAnimations.h>

#import "ARAppConstants.h"
#import "ARDefaults.h"
#import "UIDevice-Hardware.h"
#import "ARMenuAwareViewController.h"
#import "ARAugmentedRealityConfig.h"
#import "UIViewController+SimpleChildren.h"
#import "ARAugmentedVIRSetupViewController.h"
#import "ARAugmentedVIRViewController.h"

@interface ARAugmentedVIRSetupViewController () <ARMenuAwareViewController>
@property (nonatomic, copy) NSURL *movieURL;
@property (nonatomic, strong) NSUserDefaults *defaults;
@property (nonatomic, strong) ARAugmentedRealityConfig *config;

@property (nonatomic, weak) UILabel *subtitleLabel;
@property (nonatomic, weak) UIButton *button;

@property (nonatomic, assign) BOOL hasSentToSettings;
@end

NSString *const arTitle = @"Art in your home";

NSString *const needsAccessButtonTitle = @"Allow camera access";
NSString *const needsAccessSubtitle = @"To view works in your room, we'll need access to your camera.";

NSString *const hasDeniedAccessButtonTitle = @"Update Camera Access";
NSString *const hasDeniedAccessSubtitle = @"To view works in your room using augmented reality, we’ll need access to your camera. \n\nPlease update camera access permissions in the iOS settings.";

NSString *const hasAccessButtonTitle = @"Continue";
NSString *const hasAccessSubtitle = @"To view works in your room using augmented reality, find a wall and [something].";

@implementation ARAugmentedVIRSetupViewController

- (instancetype)initWithMovieURL:(NSURL *)movieURL config:(ARAugmentedRealityConfig *)config
{
    self = [super init];
    _movieURL = movieURL;
    _config = config;
    _defaults = [NSUserDefaults standardUserDefaults];
    return self;
}

- (void)viewDidLoad
{
    [super viewDidLoad];

    // Re-use the class check, this means it takes into account whether permissions have been changed after a user
    // has successfully set up an Artwork.
    [self.class canSkipARSetup:self.defaults callback:^(bool hasGivenAccess) {
        BOOL firstTime = ![self.defaults boolForKey:ARAugmentedRealityHasSeenSetup];
        BOOL notCompleted = ![self.defaults boolForKey:ARAugmentedRealityHasSuccessfullyRan];

        // Main potential states:
        //
        //  - First time with permission (given from consignments)
        //  - First time without permission
        //  - Xth time with permission because they couldn't place a work
        //  - Xth time without permission because they denied after the fact
        //
        NSString *buttonTitle = firstTime && !hasGivenAccess ? needsAccessButtonTitle : hasDeniedAccessButtonTitle ;
        NSString *subtitleText = firstTime && !hasGivenAccess ? needsAccessSubtitle: hasDeniedAccessSubtitle;
        buttonTitle = hasGivenAccess || notCompleted ? hasAccessButtonTitle : buttonTitle;
        subtitleText = hasGivenAccess || notCompleted ? hasAccessSubtitle : subtitleText;

        SEL nextButtonSelector = firstTime || hasGivenAccess || notCompleted ? @selector(next) : @selector(sendToSettings);

        // Have a potential background video, otherwise it's a black screen
        AVPlayerViewController *playVC = [[AVPlayerViewController alloc] init];
        playVC.player = [[AVPlayer alloc] initWithURL: self.movieURL];
        playVC.showsPlaybackControls = NO;

        // Add the AV player as a childVC, aligned edge to edge
        [playVC willMoveToParentViewController:self];
        [self addChildViewController:playVC];
        [self.view addSubview:playVC.view];
        [playVC.view alignToView:self.view];
        [playVC didMoveToParentViewController:self];

        UIView *overlay = [[UIView alloc] init];
        [self.view addSubview:overlay];
        [overlay alignToView:self.view];

        ARButton *allowAccessButton = [[ARWhiteFlatButton alloc] init];
        [allowAccessButton setTitle:buttonTitle forState:UIControlStateNormal];
        [allowAccessButton addTarget:self action:nextButtonSelector forControlEvents:UIControlEventTouchUpInside];
        [overlay addSubview:allowAccessButton];
        self.button = allowAccessButton;

        UILabel *subtitle = [[ARSerifLabel alloc] init];
        subtitle.font = [UIFont displaySansSerifFontWithSize:16];
        subtitle.backgroundColor = [UIColor clearColor];
        subtitle.textColor = [UIColor whiteColor];
        subtitle.text = subtitleText;
        subtitle.textAlignment = NSTextAlignmentCenter;
        [overlay addSubview:subtitle];
        self.subtitleLabel = subtitle;

        UILabel *title = [[ARSansSerifLabel alloc] init];
        title.font = [UIFont sansSerifFontWithSize:20];
        title.backgroundColor = [UIColor clearColor];
        title.textColor = [UIColor whiteColor];
        title.text = [arTitle uppercaseString];
        title.numberOfLines = 1;
        [overlay addSubview:title];

        UIButton *backButton = [self.class createBackButton];
        [backButton setTitle:@"Back to work" forState:UIControlStateNormal];
        [backButton addTarget:self action:@selector(back) forControlEvents:UIControlEventTouchUpInside];
        [overlay addSubview:backButton];

        // Align the button to the exact center of the view
        [allowAccessButton alignCenterWithView:overlay];

        // Push up subtitle from the button
        [subtitle constrainBottomSpaceToView:allowAccessButton predicate:@"-35"];
        [subtitle alignCenterXWithView:self.view predicate:@"0"];
        [subtitle alignLeading:@"20" trailing:@"-20" toView:self.view];

        // Push up title from the subtitle
        [title constrainBottomSpaceToView:subtitle predicate:@"-12"];
        [title alignCenterXWithView:self.view predicate:@"0"];

        // Align the back button to the bottom
        [backButton alignCenterXWithView:self.view predicate:@"0"];

        // ARKit is on on 11.0 so, this removes a bunch of warnings
        if (@available(iOS 11.0, *)) {
            [NSLayoutConstraint activateConstraints:@[
                [backButton.bottomAnchor constraintEqualToSystemSpacingBelowAnchor:overlay.safeAreaLayoutGuide.bottomAnchor multiplier:0]
            ]];
        } else {
            [backButton alignBottomEdgeWithView:self.view predicate:@"-20"];
        }
    }];
}

- (void)viewWillAppear:(BOOL)animated
{
    [super viewWillAppear:animated];
    [self.defaults setBool:YES forKey:ARAugmentedRealityHasSeenSetup];

    // Re-run the validation steps when they've come back from settings
    if (self.hasSentToSettings) {
        [self next];
    }
}

- (void)back
{
    [self.navigationController popViewControllerAnimated:YES];
}

- (void)sendToSettings
{
    self.hasSentToSettings = YES;
    [[UIApplication sharedApplication] openURL:[NSURL URLWithString:UIApplicationOpenSettingsURLString]];
}

- (void)next
{
    [self.class validateAVAccess:self.defaults callback:^(bool allowedAccess) {
        if (allowedAccess) {
            ARAugmentedVIRViewController *vc = [[ARAugmentedVIRViewController alloc] initWithConfig:self.config];
            [self.navigationController pushViewController:vc animated:YES];
        } else {
            [self requestDenied];
        }
    }];
}

- (void)requestDenied
{
    self.subtitleLabel.text = hasDeniedAccessSubtitle;
    [self.button setTitle:hasDeniedAccessButtonTitle forState:UIControlStateNormal];
    [self.button removeTarget:self action:@selector(next) forControlEvents:UIControlEventTouchUpInside];
    [self.button addTarget:self action:@selector(sendToSettings) forControlEvents:UIControlEventTouchUpInside];
}

+ (BOOL)canOpenARView
{
    if (@available(iOS 11.3, *)) {
        return [ARWorldTrackingConfiguration isSupported];
    } else {
        return NO;
    }
}

+ (void)canSkipARSetup:(NSUserDefaults *)defaults callback:(void (^)(bool allowedAccess))closure
{
    BOOL access = [defaults boolForKey:ARAugmentedRealityCameraAccessGiven];
    BOOL used = [defaults boolForKey:ARAugmentedRealityHasSuccessfullyRan];
    BOOL shouldBeFine = access && used;
    // We know it's a no, so return early
    if (!shouldBeFine) {
        return closure(NO);
    }

    // If you're in a sync environment (e.g. testing) return YES
    if (!ARPerformWorkAsynchronously) {
        return closure(YES);
    }

    // Otherwise, check if someone has revoked camera access after the initial acceptence
    // It won't prompt, as in order to be here you must have accepted it beforehand
    [AVCaptureDevice requestAccessForMediaType:AVMediaTypeVideo completionHandler:^(BOOL granted) {
        dispatch_async(dispatch_get_main_queue(), ^{
            closure(granted);
        });
    }];

}

+ (void)validateAVAccess:(NSUserDefaults *)defaults callback:(void (^)(bool allowedAccess))closure
{
    if ([defaults boolForKey:ARAugmentedRealityCameraAccessGiven]) {
        return closure(YES);
    }

    [AVCaptureDevice requestAccessForMediaType:AVMediaTypeVideo completionHandler:^(BOOL granted) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [defaults setBool:granted forKey:ARAugmentedRealityCameraAccessGiven];
            closure(granted);
        });
    }];
}

+ (UIButton *)createBackButton
{
    ARFlatButton *backButton = [[ARClearFlatButton alloc] init];
    [backButton setImage:[UIImage imageNamed:@"Chevron_White_Left"] forState:UIControlStateNormal];
    [backButton setImageEdgeInsets:UIEdgeInsetsMake(0, -25, 0, 10)];
    [backButton setBorderColor:[UIColor clearColor] forState:UIControlStateNormal];
    [backButton setBorderColor:[UIColor clearColor] forState:UIControlStateHighlighted];
    [backButton setBackgroundColor:[UIColor clearColor] forState:UIControlStateHighlighted];
    [backButton setTitleColor:[[UIColor whiteColor] colorWithAlphaComponent:0.5] forState:UIControlStateHighlighted];
    return backButton;
}

- (BOOL)hidesBackButton
{
    return YES;
}

- (BOOL)hidesToolbarMenu
{
    return YES;
}

- (BOOL)shouldAutorotate;
{
    return UI_USER_INTERFACE_IDIOM() == UIUserInterfaceIdiomPad;
}

- (UIInterfaceOrientationMask)supportedInterfaceOrientations;
{
    return self.shouldAutorotate ? UIInterfaceOrientationMaskAll : UIInterfaceOrientationMaskPortrait;
}

@end

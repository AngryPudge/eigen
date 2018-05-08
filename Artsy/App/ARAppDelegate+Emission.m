#import "ARAppDelegate+Emission.h"

#import "ARUserManager.h"
#import "Artist.h"
#import "Gene.h"
#import "ArtsyAPI+Following.h"
#import "ArtsyAPI+Notifications.h"
#import "ARDispatchManager.h"
#import "ARNetworkErrorManager.h"
#import "ARSwitchBoard+Eigen.h"
#import "ARTopMenuViewController.h"
#import "ARAppConstants.h"
#import "AROptions.h"
#import "ARMenuAwareViewController.h"
#import "ARAppNotificationsDelegate.h"
#import "ARDefaults.h"
#import "ARNavigationController.h"
#import "ARTopMenuViewController.h"
#import "ARRootViewController.h"
#import "ARAppStatus.h"
#import "ARRouter.h"

#import <Aerodramus/Aerodramus.h>
#import <Keys/ArtsyKeys.h>
#import <Emission/AREmission.h>
#import <Emission/ARTemporaryAPIModule.h>
#import <Emission/ARSwitchBoardModule.h>
#import <Emission/AREventsModule.h>
#import <Emission/ARTakeCameraPhotoModule.h>
#import <Emission/ARRefineOptionsModule.h>
#import <Emission/ARWorksForYouModule.h>
#import <Emission/ARArtistComponentViewController.h>
#import <Emission/ARHomeComponentViewController.h>
#import <Emission/ARWorksForYouComponentViewController.h>

#import <React/RCTUtils.h>
#import <objc/runtime.h>
#import <ARAnalytics/ARAnalytics.h>
#import "ARAdminNetworkModel.h"
#import "Artsy-Swift.h"

static void
FollowRequestSuccess(RCTResponseSenderBlock block, BOOL following)
{
    block(@[ [NSNull null], @(following) ]);
}

static void
FollowRequestFailure(RCTResponseSenderBlock block, BOOL following, NSError *error)
{
    ar_dispatch_main_queue(^{
        [ARNetworkErrorManager presentActiveError:error withMessage:@"Failed to follow artist."];
    });
    block(@[ RCTJSErrorFromNSError(error), @(following) ]);
}

@implementation ARAppDelegate (Emission)

- (void)setupEmission;
{
    if ([AROptions boolForOption:AROptionsStagingReactEnv]) {
        NSURL *packagerURL = [ARAdminNetworkModel fileURLForLatestCommitJavaScript];
        [self setupSharedEmissionWithPackagerURL:packagerURL];

    } else if ([AROptions boolForOption:AROptionsDevReactEnv]) {
        NSURL *packagerURL = [NSURL URLWithString:@"http://localhost:8081/Example/Emission/index.ios.bundle?platform=ios&dev=true"];
        [self setupSharedEmissionWithPackagerURL:packagerURL];

    } else {
        // The normal flow for users
        [self setupSharedEmissionWithPackagerURL:nil];
    }
}

- (void)setupSharedEmissionWithPackagerURL:(NSURL *)packagerURL;
{
    NSString *userID = [[[ARUserManager sharedManager] currentUser] userID];
    NSString *authenticationToken = [[ARUserManager sharedManager] userAuthenticationToken];
    NSParameterAssert(userID);
    NSParameterAssert(authenticationToken);

    ArtsyKeys *keys = [ArtsyKeys new];
    NSString *sentryDSN = nil;
    if (![ARAppStatus isDev]) {
        sentryDSN = [ARAppStatus isBeta] ? [keys sentryStagingDSN] : [keys sentryProductionDSN];
    }

    // Don't let the JS raise an error about Sentry's DSN being a stub on OSS builds
    if ([sentryDSN isEqualToString:@"-"]) {
        sentryDSN = nil;
    }

    NSString *gravity = [[ARRouter baseApiURL] absoluteString];
    NSString *metaphysics = [ARRouter baseMetaphysicsApiURLString];


    AREmissionConfiguration *config = [[AREmissionConfiguration alloc] initWithUserID:userID
                                                                      authenticationToken:authenticationToken
                                                                                sentryDSN:sentryDSN
                                                                         googleMapsAPIKey:[keys googleMapsAPIKey]
                                                                               gravityURL:gravity
                                                                           metaphysicsURL:metaphysics
                                                                                userAgent:ARRouter.userAgent];

    AREmission *emission = [[AREmission alloc] initWithConfiguration:config packagerURL:packagerURL];
    [AREmission setSharedInstance:emission];

#pragma mark - Native Module: Follow status

    emission.APIModule.artistFollowStatusProvider = ^(NSString *artistID, RCTResponseSenderBlock block) {
        [ArtsyAPI checkFavoriteStatusForArtist:[[Artist alloc] initWithArtistID:artistID]
                                       success:^(BOOL following) {
                                         FollowRequestSuccess(block, following);
                                       }
                                       failure:^(NSError *error) {
                                         FollowRequestFailure(block, NO, error);
                                       }];
    };
    emission.APIModule.artistFollowStatusAssigner = ^(NSString *artistID, BOOL following, RCTResponseSenderBlock block) {
        [ArtsyAPI setFavoriteStatus:following
                          forArtist:[[Artist alloc] initWithArtistID:artistID]
                            success:^(id response) {
                                FollowRequestSuccess(block, following);
                            }
                            failure:^(NSError *error) {
                                FollowRequestFailure(block, !following, error);
                            }];
    };

    emission.APIModule.geneFollowStatusProvider = ^(NSString *geneID, RCTResponseSenderBlock block) {
        [ArtsyAPI checkFavoriteStatusForGene:[[Gene alloc] initWithGeneID:geneID]
                                     success:^(BOOL following) {
                                         FollowRequestSuccess(block, following);
                                     }
                                     failure:^(NSError *error) {
                                         FollowRequestFailure(block, NO, error);
                                     }];
    };

    emission.APIModule.geneFollowStatusAssigner = ^(NSString *geneID, BOOL following, RCTResponseSenderBlock block) {
        [ArtsyAPI setFavoriteStatus:following
                            forGene:[[Gene alloc] initWithGeneID:geneID]
                            success:^(id response) {
                                FollowRequestSuccess(block, following);
                            }
                            failure:^(NSError *error) {
                                FollowRequestFailure(block, !following, error);
                            }];
    };

    emission.APIModule.notificationReadStatusAssigner = ^(RCTResponseSenderBlock block) {
        [ArtsyAPI markUserNotificationsReadWithSuccess:^(id response) {
            block(@[[NSNull null]]);
        } failure:^(NSError *error) {
            block(@[ RCTJSErrorFromNSError(error)]);
        }];
    };

#pragma mark - Native Module: Refine filter

    emission.refineModule.triggerRefine = ^(NSDictionary *_Nonnull initial, NSDictionary *_Nonnull current, UIViewController *_Nonnull controller, RCTPromiseResolveBlock resolve, RCTPromiseRejectBlock reject) {
        [RefineSwiftCoordinator showRefineSettingForGeneSettings:controller
                                                         initial:initial
                                                         current:current
                                                      completion:^(NSDictionary<NSString *,id> * _Nullable newRefineSettings) {
            resolve(newRefineSettings);
        }];
    };

#pragma mark - Native Module: SwitchBoard

    emission.switchBoardModule.presentNavigationViewController = ^(UIViewController *_Nonnull fromViewController,
                                                                   NSString *_Nonnull route) {
        UIViewController *viewController = [[ARSwitchBoard sharedInstance] loadPath:route];
        [[ARTopMenuViewController sharedController] pushViewController:viewController];
    };

    emission.switchBoardModule.presentModalViewController = ^(UIViewController *_Nonnull fromViewController,
                                                              NSString *_Nonnull route) {
        if ([route isEqualToString:@"/search"]) {
            [[ARTopMenuViewController sharedController].rootNavigationController toggleSearch];
        } else {
            UIViewController *viewController = [[ARSwitchBoard sharedInstance] loadPath:route];
            UIViewController *targetViewController = [ARTopMenuViewController sharedController];

            // We need to accomodate presenting a modal _on top_ of an existing modal view controller. Consignments
            // and BidFlow are presented modally, and we want to let them present modal view controllers on top of themselves.
            if (targetViewController.presentedViewController) {
                targetViewController = targetViewController.presentedViewController;
            }
            [targetViewController presentViewController:viewController
                                               animated:ARPerformWorkAsynchronously
                                             completion:nil];
        }
    };

    emission.switchBoardModule.presentArtworkSet = ^(UIViewController * _Nonnull fromViewController, NSArray<NSString *> * _Nonnull artworkIDs, NSNumber * _Nonnull index) {
        UIViewController *viewController = [[ARSwitchBoard sharedInstance] loadArtworkIDSet:artworkIDs inFair:nil atIndex:index.integerValue];
        [[ARTopMenuViewController sharedController] pushViewController:viewController];
    };

#pragma mark - Native Module: Events/Analytics

    emission.eventsModule.eventOccurred = ^(NSDictionary *_Nonnull info) {

        NSMutableDictionary *properties = [info mutableCopy];
        if (info[@"action_type"] ) {
            // Track event
            [properties removeObjectForKey:@"action_type"];
            [ARAnalytics event:info[@"action_type"] withProperties:[properties copy]];
        } else {
            // Screen event
            [properties removeObjectForKey:@"context_screen"];
            [ARAnalytics pageView:info[@"context_screen"]  withProperties:[properties copy]];
        }

        
        dispatch_async(dispatch_get_main_queue(), ^{
//            // TODO: Nav Notifications
//            if ([info[@"name"] isEqual:@"Follow artist"] && [fromViewController isKindOfClass:[ARArtistComponentViewController class]]) {
//                ARAppNotificationsDelegate *remoteNotificationsDelegate = [[JSDecoupledAppDelegate sharedAppDelegate] remoteNotificationsDelegate];
//                [remoteNotificationsDelegate registerForDeviceNotificationsWithContext:ARAppNotificationsRequestContextArtistFollow];
//            }
        });
    };

#pragma mark - Native Module: WorksForYou

    emission.worksForYouModule.setNotificationsCount = ^(NSInteger count) {
// TODO: Nav Notifications
//        [[ARTopMenuViewController sharedController] setNotificationCount:count forControllerAtIndex:ARTopTabControllerIndexNotifications];
    };

#pragma mark - Native Module: WorksForYou

}

@end

#pragma mark - ARRootViewController additions

@interface ARHomeComponentViewController (ARRootViewController) <ARRootViewController>
@end

@implementation ARHomeComponentViewController (ARRootViewController)

- (BOOL)isRootNavViewController
{
    return YES;
}

@end

@interface ARWorksForYouComponentViewController (ARRootViewController) <ARRootViewController>
@end

@implementation ARWorksForYouComponentViewController (ARRootViewController)

- (BOOL)isRootNavViewController
{
    return YES;
}

@end

#pragma mark - ARMenuAwareViewController additions


@interface ARArtistComponentViewController (ARMenuAwareViewController) <ARMenuAwareViewController>
@end


@implementation ARArtistComponentViewController (ARMenuAwareViewController)

static UIScrollView *
FindFirstScrollView(UIView *view)
{
    for (UIView *subview in view.subviews) {
        if ([subview isKindOfClass:UIScrollView.class]) {
            return (UIScrollView *)subview;
        }
    }
    for (UIView *subview in view.subviews) {
        UIScrollView *result = FindFirstScrollView(subview);
        if (result) return result;
    }
    return nil;
}

- (void)viewDidLayoutSubviews;
{
    [super viewDidLayoutSubviews];
    self.menuAwareScrollView = FindFirstScrollView(self.view);
}

static char menuAwareScrollViewKey;

- (void)setMenuAwareScrollView:(UIScrollView *)scrollView;
{
    if (scrollView != self.menuAwareScrollView) {
        [self willChangeValueForKey:@"menuAwareScrollView"];
        objc_setAssociatedObject(self, &menuAwareScrollViewKey, scrollView, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        [self didChangeValueForKey:@"menuAwareScrollView"];
    }
}

- (UIScrollView *)menuAwareScrollView;
{
    return objc_getAssociatedObject(self, &menuAwareScrollViewKey);
}

@end

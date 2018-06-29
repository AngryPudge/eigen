#import "ARZoomArtworkImageViewController.h"
#import "ARTopMenuViewController.h"
#import "UIDevice-Hardware.h"
#import "AROptions.h"

#import <ReactiveObjC/ReactiveObjC.h>


@interface ARZoomArtworkImageViewController () <ARZoomViewDelegate>

@property (nonatomic, assign) BOOL popped;
@property (readwrite, nonatomic, assign) BOOL hidesBackButton;

@end


@implementation ARZoomArtworkImageViewController

- (instancetype)initWithImage:(Image *)image
{
    self = [super init];
    if (!self) {
        return nil;
    }

    _image = image;

    return self;
}

#pragma mark - ARMenuAwareViewController

- (BOOL)hidesToolbarMenu
{
    return YES;
}

#pragma mark - UIViewController

- (BOOL)prefersStatusBarHidden
{
    return YES;
}

- (BOOL)hidesStatusBarBackground
{
    return YES;
}

- (void)viewDidLoad
{
    [super viewDidLoad];

    self.view.backgroundColor = [UIColor whiteColor];
    self.view.opaque = NO;
}

- (void)didPanOnZoomView
{
    NSLog(@"pan");
}

- (void)setZoomView:(ARZoomView *)zoomView
{
    _zoomView = zoomView;
    _zoomView.zoomDelegate = self;

    [self.view addSubview:zoomView];

    RACSignal *unconstrainSignal = [self rac_signalForSelector:@selector(unconstrainZoomView)];

    // This has immediate effect
    RACSignal *viewFrameSignal = [RACObserve(self.view, frame) takeUntil:unconstrainSignal];
    RAC(zoomView, frame) = viewFrameSignal;


    // throttle: is necessary to push this to the next runloop invocation.
    // Well, technically we need to delay it at least 2 invocations, at least on iOS 7.
    // Since it's not good to rely on iOS implementation details, this inperceptable delay will do.
    __weak typeof(zoomView) wZoomView = zoomView;

    [[[viewFrameSignal skip:1] throttle:0.01] subscribeNext:^(id x) {

        __strong typeof (wZoomView) zoomView = wZoomView;
        CGRect frame = [x CGRectValue];
        CGSize size = frame.size;
        
        [zoomView setMaxMinZoomScalesForSize:size];
        CGFloat zoomScale = [zoomView scaleForFullScreenZoomInSize:size];
        CGPoint targetContentOffset = [zoomView centerContentOffsetForZoomScale:zoomScale minimumSize:size];
        
        [zoomView performBlockWhileIgnoringContentOffsetChanges:^{
            [zoomView setZoomScale:zoomScale animated:YES];
        }];

        
        [zoomView setContentOffset:targetContentOffset animated:YES];
    }];
}

- (void)unconstrainZoomView
{
    // Empty – just used as a signal for RAC in setZoomView:
}

- (void)zoomViewFinished:(ARZoomView *)zoomView
{
    if (self.popped || self.navigationController.topViewController != self) {
        return;
    }

    [self.zoomView finish];
    self.popped = YES;
    [self.navigationController popViewControllerAnimated:YES];
}

- (void)zoomViewDidMove:(ARZoomView *)zoomView
{
    if ([AROptions boolForOption:AROptionsHideBackButtonOnScroll]) {
        [self showBackButton];
        [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(hideBackButton) object:nil];
        [self performSelector:@selector(hideBackButton) withObject:nil afterDelay:3];
    }
}

- (void)hideBackButton
{
   self.hidesBackButton = YES;
}

- (void)showBackButton
{
    self.hidesBackButton = NO;
}

- (void)viewWillAppear:(BOOL)animated
{
    [super viewDidAppear:animated];

    if (!self.suppressZoomViewCreation) {
        self.zoomView = [[ARZoomView alloc] initWithImage:self.image frame:self.view.bounds];
        self.zoomView.zoomScale = [self.zoomView scaleForFullScreenZoomInSize:self.view.bounds.size];
    }

    [super viewWillAppear:animated];
}

- (BOOL)shouldAutorotate
{
    // YES is buggy.
    return [UIDevice isPad];
}
@end

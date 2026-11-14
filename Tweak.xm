#import <UIKit/UIKit.h>
#import <CoreTelephony/CoreTelephony.h>
#import <dlfcn.h>

// ===== MediaRemote (private framework) =====
// MediaRemote is not in public SDK headers, so we load it manually at runtime.
typedef void (*MRMediaRemoteGetNowPlayingInfoFunction)(dispatch_queue_t queue, void (^handler)(NSDictionary *information));
typedef void (*MRMediaRemoteSendCommandFunction)(int command, id userInfo);

static MRMediaRemoteGetNowPlayingInfoFunction MRMediaRemoteGetNowPlayingInfo;
static MRMediaRemoteSendCommandFunction MRMediaRemoteSendCommand;

// Command constants from MediaRemote (stable across iOS 14-16)
static const int kMRPlay = 0;
static const int kMRPause = 1;
static const int kMRTogglePlayPause = 2;
static const int kMRNextTrack = 4;
static const int kMRPreviousTrack = 5;

static void LoadMediaRemote(void) {
    void *handle = dlopen("/System/Library/PrivateFrameworks/MediaRemote.framework/MediaRemote", RTLD_NOW);
    if (!handle) return;
    MRMediaRemoteGetNowPlayingInfo = (MRMediaRemoteGetNowPlayingInfoFunction)dlsym(handle, "MRMediaRemoteGetNowPlayingInfo");
    MRMediaRemoteSendCommand = (MRMediaRemoteSendCommandFunction)dlsym(handle, "MRMediaRemoteSendCommand");
}

// ===== Island modes =====
typedef NS_ENUM(NSInteger, IslandMode) {
    IslandModeIdle,
    IslandModeMusic,
    IslandModeCall,
    IslandModeTimer
};

// ===== The overlay window/view =====
@interface IslandWindow : UIWindow
@end

@interface IslandView : UIView
@property (nonatomic, assign) IslandMode mode;
@property (nonatomic, strong) UILabel *titleLabel;
@property (nonatomic, strong) UILabel *subtitleLabel;
@property (nonatomic, strong) UIButton *actionButton;
@property (nonatomic, strong) NSTimer *refreshTimer;
@property (nonatomic, strong) CTCallCenter *callCenter;
@property (nonatomic, assign) NSTimeInterval callStart;
- (void)setMode:(IslandMode)mode animated:(BOOL)animated;
- (void)refresh;
@end

static IslandWindow *gIslandWindow;
static IslandView *gIslandView;

@implementation IslandView

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        self.backgroundColor = [UIColor blackColor];
        self.layer.cornerRadius = frame.size.height / 2;
        self.clipsToBounds = YES;

        self.titleLabel = [[UILabel alloc] init];
        self.titleLabel.textColor = [UIColor whiteColor];
        self.titleLabel.font = [UIFont systemFontOfSize:13 weight:UIFontWeightSemibold];
        self.titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
        [self addSubview:self.titleLabel];

        self.subtitleLabel = [[UILabel alloc] init];
        self.subtitleLabel.textColor = [UIColor lightGrayColor];
        self.subtitleLabel.font = [UIFont systemFontOfSize:11];
        self.subtitleLabel.translatesAutoresizingMaskIntoConstraints = NO;
        [self addSubview:self.subtitleLabel];

        self.actionButton = [UIButton buttonWithType:UIButtonTypeSystem];
        [self.actionButton setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
        self.actionButton.translatesAutoresizingMaskIntoConstraints = NO;
        [self.actionButton addTarget:self action:@selector(actionTapped) forControlEvents:UIControlEventTouchUpInside];
        [self addSubview:self.actionButton];

        [NSLayoutConstraint activateConstraints:@[
            [self.titleLabel.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:14],
            [self.titleLabel.topAnchor constraintEqualToAnchor:self.topAnchor constant:6],

            [self.subtitleLabel.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:14],
            [self.subtitleLabel.topAnchor constraintEqualToAnchor:self.titleLabel.bottomAnchor constant:2],

            [self.actionButton.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-10],
            [self.actionButton.centerYAnchor constraintEqualToAnchor:self.centerYAnchor],
            [self.actionButton.widthAnchor constraintEqualToConstant:32],
            [self.actionButton.heightAnchor constraintEqualToConstant:32],
        ]];

        UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(islandTapped)];
        [self addGestureRecognizer:tap];

        self.callCenter = [[CTCallCenter alloc] init];
        self.mode = IslandModeIdle;

        self.refreshTimer = [NSTimer scheduledTimerWithTimeInterval:1.0 target:self selector:@selector(refresh) userInfo:nil repeats:YES];
        LoadMediaRemote();
        [self refresh];
    }
    return self;
}

// Decide what to show, in priority order: call > music > idle
- (void)refresh {
    __weak typeof(self) weakSelf = self;

    // 1. Check for an active call first (highest priority)
    BOOL hasActiveCall = NO;
    for (CTCall *call in self.callCenter.currentCalls) {
        if (call.callState == CTCallStateConnected || call.callState == CTCallStateDialing || call.callState == CTCallStateIncoming) {
            hasActiveCall = YES;
            break;
        }
    }

    if (hasActiveCall) {
        [self setMode:IslandModeCall animated:YES];
        return;
    }

    // 2. Check Now Playing info via MediaRemote
    if (MRMediaRemoteGetNowPlayingInfo) {
        MRMediaRemoteGetNowPlayingInfo(dispatch_get_main_queue(), ^(NSDictionary *info) {
            dispatch_async(dispatch_get_main_queue(), ^{
                NSString *title = info[@"kMRMediaRemoteNowPlayingInfoTitle"];
                NSString *artist = info[@"kMRMediaRemoteNowPlayingInfoArtist"];
                if (title.length > 0) {
                    weakSelf.titleLabel.text = title;
                    weakSelf.subtitleLabel.text = artist ?: @"";
                    [weakSelf setMode:IslandModeMusic animated:YES];
                } else {
                    [weakSelf setMode:IslandModeIdle animated:YES];
                }
            });
        });
    } else {
        [self setMode:IslandModeIdle animated:YES];
    }
}

- (void)setMode:(IslandMode)mode animated:(BOOL)animated {
    if (_mode == mode && mode != IslandModeCall) return; // allow call timer text to keep refreshing
    _mode = mode;

    CGSize targetSize;
    switch (mode) {
        case IslandModeIdle:
            targetSize = CGSizeMake(120, 34);
            self.titleLabel.text = [self currentTimeString];
            self.subtitleLabel.text = @"";
            [self.actionButton setImage:nil forState:UIControlStateNormal];
            break;
        case IslandModeMusic:
            targetSize = CGSizeMake(300, 60);
            [self.actionButton setTitle:@"⏯" forState:UIControlStateNormal];
            break;
        case IslandModeCall: {
            targetSize = CGSizeMake(260, 50);
            self.titleLabel.text = @"通話中";
            if (self.callStart == 0) self.callStart = [NSDate date].timeIntervalSince1970;
            NSInteger elapsed = (NSInteger)([NSDate date].timeIntervalSince1970 - self.callStart);
            self.subtitleLabel.text = [NSString stringWithFormat:@"%02ld:%02ld", (long)(elapsed / 60), (long)(elapsed % 60)];
            [self.actionButton setTitle:@"🔴" forState:UIControlStateNormal];
            break;
        }
        case IslandModeTimer:
            targetSize = CGSizeMake(180, 44);
            break;
    }

    if (mode != IslandModeCall) self.callStart = 0;

    [UIView animateWithDuration:(animated ? 0.45 : 0) delay:0 usingSpringWithDamping:0.75 initialSpringVelocity:0 options:0 animations:^{
        CGRect f = self.frame;
        CGFloat centerX = f.origin.x + f.size.width / 2;
        f.size = targetSize;
        f.origin.x = centerX - targetSize.width / 2;
        self.frame = f;
        self.layer.cornerRadius = targetSize.height / 2;
    } completion:nil];
}

- (NSString *)currentTimeString {
    static NSDateFormatter *fmt;
    if (!fmt) {
        fmt = [[NSDateFormatter alloc] init];
        fmt.dateFormat = @"HH:mm";
    }
    return [fmt stringFromDate:[NSDate date]];
}

- (void)islandTapped {
    // Expand/collapse manually; mostly useful in idle mode to peek battery etc.
    if (self.mode == IslandModeIdle) {
        self.subtitleLabel.text = [NSString stringWithFormat:@"バッテリー %d%%", (int)([UIDevice currentDevice].batteryLevel * 100)];
    } else {
        [self refresh];
    }
}

- (void)actionTapped {
    if (self.mode == IslandModeMusic && MRMediaRemoteSendCommand) {
        MRMediaRemoteSendCommand(kMRTogglePlayPause, nil);
    } else if (self.mode == IslandModeCall) {
        // Intentionally not wired to hang up automatically; hooking the real call-end
        // action requires CallKit/Telephony private hooks we are not enabling by default.
    }
}

@end

@implementation IslandWindow
- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
    // Only intercept touches inside the pill itself; let everything else pass through
    UIView *hit = [super hitTest:point withEvent:event];
    if (hit == self) return nil;
    return hit;
}
@end

// ===== Entry point: inject once SpringBoard finishes launching =====
%ctor {
    [[UIDevice currentDevice] setBatteryMonitoringEnabled:YES];

    dispatch_async(dispatch_get_main_queue(), ^{
        CGRect screen = [UIScreen mainScreen].bounds;
        CGFloat width = 120, height = 34;
        CGRect frame = CGRectMake((screen.size.width - width) / 2, 6, width, height);

        gIslandWindow = [[IslandWindow alloc] initWithFrame:frame];
        gIslandWindow.windowLevel = UIWindowLevelStatusBar + 100;
        gIslandWindow.backgroundColor = [UIColor clearColor];
        gIslandWindow.hidden = NO;

        gIslandView = [[IslandView alloc] initWithFrame:CGRectMake(0, 0, width, height)];
        gIslandView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        [gIslandWindow addSubview:gIslandView];
        gIslandWindow.rootViewController = [[UIViewController alloc] init];
        gIslandWindow.rootViewController.view = gIslandView;
    });
}

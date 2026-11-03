#import <AppKit/AppKit.h>
#import <Carbon/Carbon.h>
#import <pwd.h>
#import <unistd.h>

static NSString *const requestMode = @"SquirrelGetASCIIModeNotification";
static NSString *const modeResponse = @"SquirrelASCIIModeResponse";

@interface ModeIndicator : NSObject <NSApplicationDelegate>
@property(nonatomic, strong) NSStatusItem *item;
@property(nonatomic, strong) NSImage *chinese, *english;
@property(nonatomic, strong) NSTimer *timer;
@property(nonatomic) BOOL paused;
@end

@implementation ModeIndicator
- (NSImage *)icon:(NSString *)name {
    NSURL *url = [NSBundle.mainBundle URLForResource:name withExtension:@"svg"];
    NSImage *image = [[NSImage alloc] initWithContentsOfURL:url];
    if (!image || !image.isValid) return nil;
    image.size = NSMakeSize(22, 16);
    image.template = YES;
    return image;
}

- (void)applicationDidFinishLaunching:(NSNotification *)note {
    self.chinese = [self icon:@"Chinese"];
    self.english = [self icon:@"English"];
    if (!self.chinese || !self.english) { [NSApp terminate:nil]; return; }
    self.item = [NSStatusBar.systemStatusBar statusItemWithLength:NSVariableStatusItemLength];
    self.item.autosaveName = @"SquirrelMode";
    NSMenu *menu = [self configurationMenu];
    self.item.menu = menu;
    self.item.button.menu = menu; // Also use it as the button's native context menu.
    [self.item.button sendActionOn:NSEventMaskLeftMouseDown | NSEventMaskRightMouseDown];
    [self displayEnglish:YES]; // The account's schema starts new sessions in English.
    NSDistributedNotificationCenter *center = NSDistributedNotificationCenter.defaultCenter;
    [center addObserver:self selector:@selector(received:) name:modeResponse object:nil
        suspensionBehavior:NSNotificationSuspensionBehaviorDeliverImmediately];
    [center addObserver:self selector:@selector(refresh:) name:(__bridge NSString *)kTISNotifySelectedKeyboardInputSourceChanged
        object:nil suspensionBehavior:NSNotificationSuspensionBehaviorDeliverImmediately];
    NSNotificationCenter *workspace = NSWorkspace.sharedWorkspace.notificationCenter;
    [workspace addObserver:self selector:@selector(refresh:) name:NSWorkspaceDidActivateApplicationNotification object:nil];
    [workspace addObserver:self selector:@selector(pause:) name:NSWorkspaceWillSleepNotification object:nil];
    [workspace addObserver:self selector:@selector(pause:) name:NSWorkspaceSessionDidResignActiveNotification object:nil];
    [workspace addObserver:self selector:@selector(resume:) name:NSWorkspaceDidWakeNotification object:nil];
    [workspace addObserver:self selector:@selector(resume:) name:NSWorkspaceSessionDidBecomeActiveNotification object:nil];
    [self refresh:nil];
}

- (NSMenu *)configurationMenu {
    NSBundle *squirrel = [NSBundle bundleWithPath:@"/Library/Input Methods/Squirrel.app"];
    NSMenu *menu = [[NSMenu alloc] initWithTitle:@"Squirrel"];
    NSArray *titles = @[@"Deploy", @"Sync user data", @"Logs...", @"Settings...", @"Rime Wiki..."];
    SEL actions[] = {@selector(deploy:), @selector(sync:), @selector(openLogs:),
                     @selector(openSettings:), @selector(openWiki:)};
    for (NSUInteger i = 0; i < titles.count; i++) {
        NSString *title = [squirrel localizedStringForKey:titles[i] value:titles[i] table:nil] ?: titles[i];
        NSMenuItem *item = [menu addItemWithTitle:title action:actions[i] keyEquivalent:i == 0 ? @"`" : @""];
        item.target = self;
        if (i == 0) item.keyEquivalentModifierMask = NSEventModifierFlagControl | NSEventModifierFlagOption;
    }
    // Squirrel's built-in updater only accepts commands from inside its own app.
    NSString *language = squirrel.preferredLocalizations.firstObject;
    NSString *releaseTitle = [language isEqual:@"zh-Hans"] ? @"查看官方每夜构建…" :
        [language isEqual:@"zh-Hant"] ? @"查看官方每夜建置…" : @"View official nightly release…";
    [menu addItemWithTitle:releaseTitle action:@selector(openRelease:) keyEquivalent:@""].target = self;
    return menu;
}

- (void)deploy:(id)sender {
    [NSDistributedNotificationCenter.defaultCenter postNotificationName:@"SquirrelReloadNotification"
        object:nil userInfo:nil deliverImmediately:YES];
}

- (void)sync:(id)sender {
    [NSDistributedNotificationCenter.defaultCenter postNotificationName:@"SquirrelSyncNotification"
        object:nil userInfo:nil deliverImmediately:YES];
}

- (void)revealFile:(NSString *)path {
    if (!path) { NSBeep(); return; }
    [NSWorkspace.sharedWorkspace activateFileViewerSelectingURLs:@[[NSURL fileURLWithPath:path isDirectory:NO]]];
}

- (void)openSettings:(id)sender {
    struct passwd *account = getpwuid(getuid());
    NSString *home = account ? [NSString stringWithUTF8String:account->pw_dir] : nil;
    [self revealFile:[home stringByAppendingPathComponent:@"Library/Rime/squirrel.custom.yaml"]];
}

- (void)openLogs:(id)sender {
    // The login item supplies Squirrel's temp directory from outside our sandbox.
    NSString *folder = NSProcessInfo.processInfo.environment[@"SQUIRREL_LOG_FOLDER"];
    [self revealFile:[folder stringByAppendingPathComponent:@"rime.squirrel.INFO"]];
}

- (void)openWiki:(id)sender {
    [NSWorkspace.sharedWorkspace openURL:[NSURL URLWithString:@"https://github.com/rime/home/wiki"]];
}

- (void)openRelease:(id)sender {
    [NSWorkspace.sharedWorkspace openURL:[NSURL URLWithString:@"https://github.com/rime/squirrel/releases/tag/latest"]];
}

- (void)displayEnglish:(BOOL)english {
    NSStatusBarButton *button = self.item.button;
    NSImage *image = english ? self.english : self.chinese;
    if (button.image == image) return;
    button.image = image;
    NSString *label = english ? @"Squirrel · English" : @"Squirrel · Chinese";
    button.toolTip = label;
    [button setAccessibilityLabel:label];
}

- (void)received:(NSNotification *)note {
    if (!self.item.visible || self.paused) return;
    if ([note.object isEqual:@"ascii"]) [self displayEnglish:YES];
    if ([note.object isEqual:@"nascii"]) [self displayEnglish:NO];
}

// The official nightly answers mode queries; it does not broadcast every Shift.
- (void)askMode:(NSTimer *)timer {
    [NSDistributedNotificationCenter.defaultCenter postNotificationName:requestMode
        object:nil userInfo:nil deliverImmediately:YES];
}

- (void)refresh:(NSNotification *)note {
    TISInputSourceRef source = TISCopyCurrentKeyboardInputSource();
    NSString *identifier = source ? (__bridge NSString *)TISGetInputSourceProperty(source,kTISPropertyInputSourceID) : nil;
    BOOL active = !self.paused && [identifier hasPrefix:@"im.rime.inputmethod.Squirrel."];
    if (source) CFRelease(source);
    if (self.item.visible != active) self.item.visible = active;
    if (!active) {
        [self.timer invalidate];
        self.timer = nil;
        return;
    }
    if (!self.timer) {
        self.timer = [NSTimer timerWithTimeInterval:0.3 target:self selector:@selector(askMode:)
            userInfo:nil repeats:YES];
        self.timer.tolerance = 0.08;
        [NSRunLoop.mainRunLoop addTimer:self.timer forMode:NSRunLoopCommonModes];
    }
    [self askMode:nil];
}

- (void)pause:(NSNotification *)note { self.paused = YES; [self refresh:nil]; }
- (void)resume:(NSNotification *)note { self.paused = NO; [self refresh:nil]; }
- (void)applicationWillTerminate:(NSNotification *)note {
    [self.timer invalidate];
    [NSDistributedNotificationCenter.defaultCenter removeObserver:self];
    [NSWorkspace.sharedWorkspace.notificationCenter removeObserver:self];
    [NSStatusBar.systemStatusBar removeStatusItem:self.item];
}
@end

int main(void) {
    @autoreleasepool {
        NSApplication *app = NSApplication.sharedApplication;
        [app setActivationPolicy:NSApplicationActivationPolicyAccessory];
        __attribute__((objc_precise_lifetime)) ModeIndicator *delegate = [ModeIndicator new];
        app.delegate = delegate;
        [app run];
    }
    return 0;
}

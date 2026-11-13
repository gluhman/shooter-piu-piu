#import <AppKit/AppKit.h>
#import <Sparkle/Sparkle.h>

@interface ShooterUpdater : NSObject <NSApplicationDelegate, SPUUpdaterDelegate>
@property (nonatomic, strong) SPUUpdater *updater;
@end

@implementation ShooterUpdater

- (void)applicationDidFinishLaunching:(NSNotification *)notification
{
    NSURL *bundleURL = [[[[NSBundle.mainBundle.bundleURL URLByDeletingLastPathComponent]
        URLByDeletingLastPathComponent] URLByDeletingLastPathComponent] URLByStandardizingPath];
    NSBundle *game = [NSBundle bundleWithURL:bundleURL];
    if (![[game bundleIdentifier] isEqualToString:@"com.shootcontainer.game"]) {
        [NSApp terminate:nil];
        return;
    }

    SPUStandardUserDriver *driver = [[SPUStandardUserDriver alloc] initWithHostBundle:game delegate:nil];
    self.updater = [[SPUUpdater alloc] initWithHostBundle:game applicationBundle:game userDriver:driver delegate:self];
    NSError *error = nil;
    if (![self.updater startUpdater:&error]) {
        NSAlert *alert = [NSAlert alertWithError:error];
        [NSApp activateIgnoringOtherApps:YES];
        [alert runModal];
        [NSApp terminate:nil];
        return;
    }
    [self.updater checkForUpdates];
}

- (void)updater:(SPUUpdater *)updater didFinishUpdateCycleForUpdateCheck:(SPUUpdateCheck)check error:(NSError *)error
{
    [NSApp terminate:nil];
}

@end

int main(void)
{
    @autoreleasepool {
        NSApplication *application = NSApplication.sharedApplication;
        [application setActivationPolicy:NSApplicationActivationPolicyAccessory];
        ShooterUpdater *delegate = [ShooterUpdater new];
        application.delegate = delegate;
        [application run];
    }
    return 0;
}

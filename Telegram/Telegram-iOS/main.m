#import <UIKit/UIKit.h>

// 由 :LaraShim 提供；显式调用而不是靠 +load/constructor，
// 因为 :Main 是静态库，未被引用的目标文件会被 -dead_strip 丢掉。
extern void LaraBootstrapInstall(void);

int main(int argc, char *argv[]) {
    @autoreleasepool {
        LaraBootstrapInstall();
        return UIApplicationMain(argc, argv, @"Application", @"AppDelegate");
    }
}

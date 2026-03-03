#import "libiosrpc.h"
#import <dlfcn.h>

typedef int32_t (*dclogin_fn)(const char *);
typedef int32_t (*dclogout_fn)(void);
typedef int32_t (*startrpc_fn)(const char *, const char *, const char *, const char *);
typedef int32_t (*stoprpc_fn)(void);
typedef const char *(*dclast_error_fn)(void);

@interface DiscordRPCBridge ()
@property (nonatomic, assign) void *handle;
@property (nonatomic, assign) dclogin_fn dcloginPtr;
@property (nonatomic, assign) dclogout_fn dclogoutPtr;
@property (nonatomic, assign) startrpc_fn startrpcPtr;
@property (nonatomic, assign) stoprpc_fn stoprpcPtr;
@property (nonatomic, assign) dclast_error_fn dclastErrorPtr;
@property (nonatomic, copy, nullable) NSString *preferredLibraryPath;
@property (nonatomic, copy, nullable) NSString *lastLoadError;
@end

@implementation DiscordRPCBridge

+ (instancetype)shared {
    static DiscordRPCBridge *instance;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [DiscordRPCBridge new];
    });
    return instance;
}

- (void)setPreferredLibraryPath:(NSString *)path {
    self.preferredLibraryPath = path;
}

- (BOOL)loadLibrary {
    if (self.handle != NULL) {
        return YES;
    }

    NSMutableArray<NSString *> *candidatePaths = [NSMutableArray array];
    if (self.preferredLibraryPath.length > 0) {
        [candidatePaths addObject:self.preferredLibraryPath];
    }

    NSString *frameworksPath = [[NSBundle mainBundle] privateFrameworksPath];
    NSString *bundlePath = [frameworksPath stringByAppendingPathComponent:@"libiosrpc.dylib"];
    [candidatePaths addObject:bundlePath];

    NSString *execPath = [[NSBundle mainBundle] executablePath];
    NSString *dir = [execPath stringByDeletingLastPathComponent];
    NSString *fallbackPath = [dir stringByAppendingPathComponent:@"libiosrpc.dylib"];
    [candidatePaths addObject:fallbackPath];

    NSString *dlError = nil;
    for (NSString *path in candidatePaths) {
        self.handle = dlopen(path.UTF8String, RTLD_NOW | RTLD_LOCAL);
        if (self.handle != NULL) {
            break;
        }
        const char *err = dlerror();
        if (err != NULL) {
            dlError = [NSString stringWithUTF8String:err];
        }
    }

    if (self.handle == NULL) {
        self.lastLoadError = dlError;
        return NO;
    }

    self.dcloginPtr = (dclogin_fn)dlsym(self.handle, "dclogin");
    self.dclogoutPtr = (dclogout_fn)dlsym(self.handle, "dclogout");
    self.startrpcPtr = (startrpc_fn)dlsym(self.handle, "startrpc");
    self.stoprpcPtr = (stoprpc_fn)dlsym(self.handle, "stoprpc");
    self.dclastErrorPtr = (dclast_error_fn)dlsym(self.handle, "dclast_error");

    return self.dcloginPtr && self.dclogoutPtr && self.startrpcPtr && self.stoprpcPtr;
}

- (int32_t)loginWithToken:(NSString *)token {
    if (![self loadLibrary]) return -999;
    return self.dcloginPtr(token.UTF8String);
}

- (int32_t)logout {
    if (![self loadLibrary]) return -999;
    return self.dclogoutPtr();
}

- (int32_t)startRPCWithIcon:(NSString *)icon title:(NSString *)title description:(NSString *)description button:(NSString *)button {
    if (![self loadLibrary]) return -999;
    return self.startrpcPtr(icon.UTF8String, title.UTF8String, description.UTF8String, button.UTF8String);
}

- (int32_t)stopRPC {
    if (![self loadLibrary]) return -999;
    return self.stoprpcPtr();
}

- (NSString *)lastError {
    if (![self loadLibrary]) {
        if (self.lastLoadError.length > 0) {
            return [NSString stringWithFormat:@"Could not load libiosrpc.dylib: %@", self.lastLoadError];
        }
        return @"Could not load libiosrpc.dylib";
    }
    if (!self.dclastErrorPtr) {
        return @"dclast_error not exported";
    }

    const char *value = self.dclastErrorPtr();
    if (!value) {
        return @"unknown";
    }
    return [NSString stringWithUTF8String:value] ?: @"unknown";
}

@end

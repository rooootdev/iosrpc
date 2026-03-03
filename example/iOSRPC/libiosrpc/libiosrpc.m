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
@property (nonatomic, assign) dclast_error_fn dclasterrorptr;
@property (nonatomic, copy, nullable) NSString *preferredlibrarypath;
@property (nonatomic, copy, nullable) NSString *lastloaderror;
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

- (void)setpreferredlibrarypath:(NSString *)path {
    self.preferredlibrarypath = path;
}

- (BOOL)loadlibrary {
    if (self.handle != NULL) {
        return YES;
    }

    if (self.preferredlibrarypath.length > 0) {
        if (![[NSFileManager defaultManager] fileExistsAtPath:self.preferredlibrarypath]) {
            self.lastloaderror = [NSString stringWithFormat:@"preferred library not found at path: %@", self.preferredlibrarypath];
            return NO;
        }

        self.handle = dlopen(self.preferredlibrarypath.UTF8String, RTLD_NOW | RTLD_LOCAL);
        if (self.handle == NULL) {
            const char *err = dlerror();
            self.lastloaderror = err ? [NSString stringWithUTF8String:err] : @"dlopen failed for preferred library path";
            return NO;
        }
    }

    NSMutableArray<NSString *> *candidatepaths = [NSMutableArray array];

    NSString *frameworksPath = [[NSBundle mainBundle] privateFrameworksPath];
    NSString *bundlePath = [frameworksPath stringByAppendingPathComponent:@"libiosrpc.dylib"];
    [candidatepaths addObject:bundlePath];

    NSString *execPath = [[NSBundle mainBundle] executablePath];
    NSString *dir = [execPath stringByDeletingLastPathComponent];
    NSString *fallbackPath = [dir stringByAppendingPathComponent:@"libiosrpc.dylib"];
    [candidatepaths addObject:fallbackPath];

    NSString *dlerrormsg = nil;
    for (NSString *path in candidatepaths) {
        self.handle = dlopen(path.UTF8String, RTLD_NOW | RTLD_LOCAL);
        if (self.handle != NULL) {
            break;
        }
        const char *err = dlerror();
        if (err != NULL) {
            dlerrormsg = [NSString stringWithUTF8String:err];
        }
    }

    if (self.handle == NULL) {
        self.lastloaderror = dlerrormsg;
        return NO;
    }

    self.dcloginPtr = (dclogin_fn)dlsym(self.handle, "dclogin");
    self.dclogoutPtr = (dclogout_fn)dlsym(self.handle, "dclogout");
    self.startrpcPtr = (startrpc_fn)dlsym(self.handle, "startrpc");
    self.stoprpcPtr = (stoprpc_fn)dlsym(self.handle, "stoprpc");
    self.dclasterrorptr = (dclast_error_fn)dlsym(self.handle, "dclast_error");

    return self.dcloginPtr && self.dclogoutPtr && self.startrpcPtr && self.stoprpcPtr;
}

- (int32_t)loginwithtoken:(NSString *)token {
    if (![self loadlibrary]) return -999;
    return self.dcloginPtr(token.UTF8String);
}

- (int32_t)logout {
    if (![self loadlibrary]) return -999;
    return self.dclogoutPtr();
}

- (int32_t)startrpcwithicon:(NSString *)icon title:(NSString *)title description:(NSString *)description button:(NSString *)button {
    if (![self loadlibrary]) return -999;
    return self.startrpcPtr(icon.UTF8String, title.UTF8String, description.UTF8String, button.UTF8String);
}

- (int32_t)stoprpc {
    if (![self loadlibrary]) return -999;
    return self.stoprpcPtr();
}

- (NSString *)lasterror {
    if (![self loadlibrary]) {
        if (self.lastloaderror.length > 0) {
            return [NSString stringWithFormat:@"Could not load libiosrpc.dylib: %@", self.lastloaderror];
        }
        return @"Could not load libiosrpc.dylib";
    }
    if (!self.dclasterrorptr) {
        return @"dclast_error not exported";
    }

    const char *value = self.dclasterrorptr();
    if (!value) {
        return @"unknown";
    }
    return [NSString stringWithUTF8String:value] ?: @"unknown";
}

@end

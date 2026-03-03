#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface DiscordRPCBridge : NSObject
+ (instancetype)shared;
- (void)setpreferredlibrarypath:(NSString *)path;
- (BOOL)loadlibrary;
- (int32_t)loginwithtoken:(NSString *)token;
- (int32_t)logout;
- (int32_t)startrpcwithicon:(NSString *)icon title:(NSString *)title description:(NSString *)description button:(NSString *)button;
- (int32_t)stoprpc;
- (NSString *)lasterror;
@end

NS_ASSUME_NONNULL_END

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface DiscordRPCBridge : NSObject
+ (instancetype)shared;
- (BOOL)loadLibrary;
- (int32_t)loginWithToken:(NSString *)token;
- (int32_t)logout;
- (int32_t)startRPCWithIcon:(NSString *)icon title:(NSString *)title description:(NSString *)description button:(NSString *)button;
- (int32_t)stopRPC;
- (NSString *)lastError;
@end

NS_ASSUME_NONNULL_END

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// Private filter keys can change across OS versions. Contain KVC exceptions
/// so an unsupported experimental renderer can disable itself safely.
FOUNDATION_EXPORT BOOL GlassTabBarSetPrivateValue(NSObject *object, NSString *key, id value);

NS_ASSUME_NONNULL_END

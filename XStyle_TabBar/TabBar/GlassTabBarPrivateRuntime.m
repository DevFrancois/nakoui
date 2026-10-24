#import "GlassTabBarPrivateRuntime.h"

BOOL GlassTabBarSetPrivateValue(NSObject *object, NSString *key, id value) {
    @try {
        [object setValue:value forKey:key];
        return YES;
    } @catch (NSException *exception) {
        return NO;
    }
}

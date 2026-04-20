// ============================================================
// horizOn SDK - Apple Sign-In iOS Plugin (classic .gdip)
// ============================================================
// Wraps Apple's AuthenticationServices framework so Godot can
// drive `ASAuthorizationController` from GDScript via a Godot
// singleton named `HorizonAppleSignIn`.
//
// GDScript side waits on the `apple_sign_in_completed` signal:
//   (identity_token: String, first_name: String,
//    last_name: String, error: String)
// ============================================================

#ifndef HORIZON_APPLE_SIGN_IN_H
#define HORIZON_APPLE_SIGN_IN_H

#import <Foundation/Foundation.h>
#import <AuthenticationServices/AuthenticationServices.h>

#include "core/object/ref_counted.h"

class HorizonAppleSignIn : public RefCounted {
    GDCLASS(HorizonAppleSignIn, RefCounted);

    static HorizonAppleSignIn *instance;

protected:
    static void _bind_methods();

public:
    static HorizonAppleSignIn *get_singleton();

    // Kicks off the Sign in with Apple sheet.
    // `nonce` is the raw nonce; the plugin SHA-256 hashes it before
    // forwarding to ASAuthorizationAppleIDRequest, matching the format
    // the backend verifier expects.
    void start_sign_in(const String &nonce);

    // Internal - invoked by the Objective-C delegate when the sheet completes.
    void _emit_result(const String &identity_token, const String &first_name,
                      const String &last_name, const String &error);

    HorizonAppleSignIn();
    ~HorizonAppleSignIn();
};

extern "C" {
void horizon_apple_sign_in_init();
void horizon_apple_sign_in_deinit();
}

@interface HorizonAppleSignInDelegate : NSObject <ASAuthorizationControllerDelegate, ASAuthorizationControllerPresentationContextProviding>
- (void)startSignInWithNonce:(NSString *)nonce;
@end

#endif // HORIZON_APPLE_SIGN_IN_H

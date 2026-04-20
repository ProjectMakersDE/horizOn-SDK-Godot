// ============================================================
// horizOn SDK - Apple Sign-In iOS Plugin (classic .gdip)
// ============================================================
// Implementation of the AuthenticationServices wrapper. Built as a
// static library and linked into the Godot iOS export template via
// the .gdip manifest.
// ============================================================

#import "HorizonAppleSignIn.h"
#import <CommonCrypto/CommonDigest.h>
#import <UIKit/UIKit.h>

#include "core/config/engine.h"

HorizonAppleSignIn *HorizonAppleSignIn::instance = nullptr;

static HorizonAppleSignInDelegate *g_delegate = nil;

static NSString *sha256_hex(NSString *input) {
    const char *str = [input UTF8String];
    unsigned char hash[CC_SHA256_DIGEST_LENGTH];
    CC_SHA256(str, (CC_LONG)strlen(str), hash);
    NSMutableString *out = [NSMutableString stringWithCapacity:CC_SHA256_DIGEST_LENGTH * 2];
    for (int i = 0; i < CC_SHA256_DIGEST_LENGTH; i++) {
        [out appendFormat:@"%02x", hash[i]];
    }
    return out;
}

void HorizonAppleSignIn::_bind_methods() {
    ClassDB::bind_method(D_METHOD("start_sign_in", "nonce"), &HorizonAppleSignIn::start_sign_in);
    ADD_SIGNAL(MethodInfo("apple_sign_in_completed",
        PropertyInfo(Variant::STRING, "identity_token"),
        PropertyInfo(Variant::STRING, "first_name"),
        PropertyInfo(Variant::STRING, "last_name"),
        PropertyInfo(Variant::STRING, "error")));
}

HorizonAppleSignIn *HorizonAppleSignIn::get_singleton() {
    return instance;
}

HorizonAppleSignIn::HorizonAppleSignIn() {
    ERR_FAIL_COND(instance != nullptr);
    instance = this;
}

HorizonAppleSignIn::~HorizonAppleSignIn() {
    if (instance == this) {
        instance = nullptr;
    }
}

void HorizonAppleSignIn::start_sign_in(const String &nonce) {
    if (g_delegate == nil) {
        g_delegate = [[HorizonAppleSignInDelegate alloc] init];
    }
    NSString *raw_nonce = [NSString stringWithUTF8String:nonce.utf8().get_data()];
    [g_delegate startSignInWithNonce:raw_nonce];
}

void HorizonAppleSignIn::_emit_result(const String &identity_token, const String &first_name,
                                      const String &last_name, const String &error) {
    emit_signal("apple_sign_in_completed", identity_token, first_name, last_name, error);
}

void horizon_apple_sign_in_init() {
    HorizonAppleSignIn *plugin = memnew(HorizonAppleSignIn);
    Engine::get_singleton()->add_singleton(Engine::Singleton("HorizonAppleSignIn", plugin));
}

void horizon_apple_sign_in_deinit() {
    HorizonAppleSignIn *plugin = HorizonAppleSignIn::get_singleton();
    if (plugin != nullptr) {
        memdelete(plugin);
    }
    g_delegate = nil;
}

// ------------------------------------------------------------
// Objective-C delegate
// ------------------------------------------------------------

@implementation HorizonAppleSignInDelegate

- (void)startSignInWithNonce:(NSString *)nonce {
    ASAuthorizationAppleIDProvider *provider = [[ASAuthorizationAppleIDProvider alloc] init];
    ASAuthorizationAppleIDRequest *request = [provider createRequest];
    request.requestedScopes = @[ASAuthorizationScopeFullName, ASAuthorizationScopeEmail];
    request.nonce = sha256_hex(nonce);

    ASAuthorizationController *controller =
        [[ASAuthorizationController alloc] initWithAuthorizationRequests:@[request]];
    controller.delegate = self;
    controller.presentationContextProvider = self;
    [controller performRequests];
}

#pragma mark - ASAuthorizationControllerDelegate

- (void)authorizationController:(ASAuthorizationController *)controller
   didCompleteWithAuthorization:(ASAuthorization *)authorization {
    HorizonAppleSignIn *plugin = HorizonAppleSignIn::get_singleton();
    if (plugin == nullptr) {
        return;
    }

    if (![authorization.credential isKindOfClass:[ASAuthorizationAppleIDCredential class]]) {
        plugin->_emit_result(String(), String(), String(), String("INVALID_APPLE_TOKEN"));
        return;
    }

    ASAuthorizationAppleIDCredential *credential = (ASAuthorizationAppleIDCredential *)authorization.credential;
    NSString *token = [[NSString alloc] initWithData:credential.identityToken
                                            encoding:NSUTF8StringEncoding];
    NSString *first_name = credential.fullName.givenName ?: @"";
    NSString *last_name = credential.fullName.familyName ?: @"";

    plugin->_emit_result(
        String::utf8([(token ?: @"") UTF8String]),
        String::utf8([first_name UTF8String]),
        String::utf8([last_name UTF8String]),
        String());
}

- (void)authorizationController:(ASAuthorizationController *)controller
            didCompleteWithError:(NSError *)error {
    HorizonAppleSignIn *plugin = HorizonAppleSignIn::get_singleton();
    if (plugin == nullptr) {
        return;
    }

    NSString *code = @"INVALID_APPLE_TOKEN";
    if (error.code == ASAuthorizationErrorCanceled) {
        code = @"USER_CANCELED";
    } else if (error.code == ASAuthorizationErrorFailed || error.code == ASAuthorizationErrorInvalidResponse) {
        code = @"INVALID_APPLE_TOKEN";
    } else if (error.code == ASAuthorizationErrorNotHandled) {
        code = @"APPLE_NOT_CONFIGURED";
    } else if (error.code == ASAuthorizationErrorUnknown) {
        code = @"NETWORK_ERROR";
    }

    plugin->_emit_result(String(), String(), String(),
        String::utf8([code UTF8String]));
}

#pragma mark - ASAuthorizationControllerPresentationContextProviding

- (ASPresentationAnchor)presentationAnchorForAuthorizationController:
    (ASAuthorizationController *)controller {
    UIWindow *keyWindow = nil;
    for (UIScene *scene in [UIApplication sharedApplication].connectedScenes) {
        if ([scene isKindOfClass:[UIWindowScene class]] &&
            scene.activationState == UISceneActivationStateForegroundActive) {
            UIWindowScene *windowScene = (UIWindowScene *)scene;
            for (UIWindow *window in windowScene.windows) {
                if (window.isKeyWindow) {
                    keyWindow = window;
                    break;
                }
            }
            if (keyWindow) break;
        }
    }
    return keyWindow ?: [[UIApplication sharedApplication].windows firstObject];
}

@end

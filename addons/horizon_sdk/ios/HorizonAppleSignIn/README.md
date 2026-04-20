# HorizonAppleSignIn - Godot iOS Plugin

Classic Godot iOS plugin (`.gdip` format - **not** GDExtension) that wraps Apple's
`AuthenticationServices.framework` so the GDScript SDK can drive the native
**Sign in with Apple** sheet on iOS.

## Files

| File | Purpose |
|------|---------|
| `HorizonAppleSignIn.gdip` | Plugin manifest consumed by the Godot iOS export pipeline |
| `HorizonAppleSignIn.h` | C++ + Objective-C header, declares the engine singleton |
| `HorizonAppleSignIn.mm` | Objective-C++ implementation that wraps `ASAuthorizationController` |

## Build

The classic plugin format requires the static library to be **compiled from the
Godot iOS export template build** rather than shipped as a binary. Build steps:

```bash
# Inside the Godot source tree:
scons platform=ios target=template_release \
    custom_modules=/path/to/horizon_sdk/ios/HorizonAppleSignIn
```

The build emits `HorizonAppleSignIn.a`, which Godot's iOS exporter picks up
through the `[config] binary` field in `HorizonAppleSignIn.gdip`.

## Runtime Contract

When loaded, the plugin registers an engine singleton named `HorizonAppleSignIn`
exposing:

- `start_sign_in(nonce: String)` - presents the native Apple sheet.
- Signal `apple_sign_in_completed(identity_token, first_name, last_name, error)`
  - On success, `error` is empty.
  - On failure, `error` is one of:
    `INVALID_APPLE_TOKEN`, `APPLE_NOT_CONFIGURED`, `NETWORK_ERROR`,
    `USER_CANCELED`.

## Xcode Project Requirements

- Add the **Sign in with Apple** capability to your `.entitlements` file.
- Provisioning profile must include the Apple Sign-In capability.
- No additional Info.plist entries required - the framework handles the user
  prompt.

## GDScript Side

`addons/horizon_sdk/core/auth.gd` calls into this plugin from the
`sign_in_with_apple()` convenience method. The GDScript side detects the plugin
via `Engine.has_singleton("HorizonAppleSignIn")` and falls back to the
system-browser OAuth flow on every other platform.

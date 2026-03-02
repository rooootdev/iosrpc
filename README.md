# iOSRPC

This folder contains:

- `rust-dylib/`: Rust `cdylib` exposing `dclogin`, `dclogout`, `startrpc`, `stoprpc`.
- `example-xcode/`: Example iOS Xcode project (`DiscordRPCDemo.xcodeproj`) that:
  - Uses SwiftUI (`RPCDemoApp.swift` + `ContentView.swift`).
  - Opens Discord OAuth.
  - Receives token through HTTPS callback page -> app scheme redirect.
  - Passes token to `dclogin`.
  - Calls `startrpc`/`stoprpc`/`dclogout`.
- `web-callback-example/`: Simple PHP callback page for HTTPS -> app-scheme redirect.
- `backend-example/`: Optional stronger-security Node/Express backend for code exchange.

## 1) Build dylib

```bash
cd /Users/ruter/Desktop/understand/iOSRPC/rust-dylib
./build-ios.sh
```

Outputs:

- `target/aarch64-apple-ios/release/libiosrpc.dylib`
- `target/aarch64-apple-ios-sim/release/libiosrpc.dylib`
- `target/x86_64-apple-ios/release/libiosrpc.dylib`

## 2) Open example app

Open:

- `example-xcode/DiscordRPCDemo.xcodeproj`

The target includes a build script phase (`Copy Rust dylib`) that copies the correct `libiosrpc.dylib` variant from `../rust-dylib/target/...` into `App.app/Frameworks/`.

## 3) OAuth setup

In `example-xcode/DiscordRPCDemo/Info.plist`, set:

- `DiscordClientID` to your Discord application ID.
- `DiscordCallbackScheme` (default sample: `iosrpc`).
- `DiscordWebCallbackURL` to your hosted HTTPS callback page.

Host `web-callback-example/callback.php` at your HTTPS URL, then add that exact URL in Discord app Redirects:

- `https://site.example/iosrpc/callback.php`

The callback page forwards query/fragment to app scheme:
- `<DiscordCallbackScheme>://oauth?...#...`

Optional: use `backend-example/` if you want code flow + server token exchange.

## API notes

`rust-dylib/src/lib.rs` currently implements stateful login/RPC lifecycle and argument validation. It stores the presence payload in-process (for integration testing) and is the correct place to plug in your actual Discord transport.

Exported functions:

- `int32_t dclogin(const char *token)`
- `int32_t dclogout(void)`
- `int32_t startrpc(const char *icon, const char *title, const char *description, const char *button)`
- `int32_t stoprpc(void)`

Optional helpers:

- `const char *dclast_error(void)`
- `const char *dcrpc_snapshot_json(void)`

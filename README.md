# iOSRPC
Rust-powered iOS RPC bridge.

## Repository Layout
- `libiosrpc/`: Rust `cdylib` exposing `dclogin`, `dclogout`, `startrpc`, `stoprpc`.
- `example/`: iOS demo app project (`iOSRPC.xcodeproj`) using SwiftUI + Objective-C bridge.

## Build `libiosrpc.dylib`

```bash
cd libiosrpc
./build-ios.sh
```

Outputs:

- `libiosrpc/target/aarch64-apple-ios/release/libiosrpc.dylib`
- `libiosrpc/target/aarch64-apple-ios-sim/release/libiosrpc.dylib`
- `libiosrpc/target/x86_64-apple-ios/release/libiosrpc.dylib`

## Open the iOS Demo App

Open:

- `example/iOSRPC.xcodeproj`

The target has a build phase (`Copy Rust dylib`) that copies the correct `libiosrpc.dylib` variant from `../libiosrpc/target/...` into `App.app/Frameworks/`.

On first launch, the demo app also attempts to download the latest matching `libiosrpc` release asset from GitHub and prefer that runtime copy when loading the bridge.

## OAuth Setup

In `example/iOSRPC/Info.plist`, set:

- `DiscordClientID` to your Discord application ID.
- `DiscordCallbackScheme` (default: `iosrpc`).
- `DiscordWebCallbackURL` to your hosted HTTPS callback page.

## CI Release Artifacts

GitHub Actions workflow `.github/workflows/release-assets.yml` builds and uploads these assets to the latest GitHub release:

- `libiosrpc-aarch64-apple-ios.dylib`
- `libiosrpc-aarch64-apple-ios-sim.dylib`
- `libiosrpc-x86_64-apple-ios.dylib`
- `iOSRPC-example.ipa`

You can run it manually with `workflow_dispatch`, or it can run on release publish.

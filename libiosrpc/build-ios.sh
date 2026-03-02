#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
cd "$ROOT"

if ! command -v rustup >/dev/null 2>&1; then
  echo "error: rustup is required for this script." >&2
  exit 1
fi

TOOLCHAIN="stable"
RUSTC_BIN="$(rustup which --toolchain "$TOOLCHAIN" rustc)"
RUSTDOC_BIN="$(rustup which --toolchain "$TOOLCHAIN" rustdoc)"
CARGO_BIN="$(rustup which --toolchain "$TOOLCHAIN" cargo)"

# Build device + simulator dynamic libraries.
rustup target add --toolchain "$TOOLCHAIN" aarch64-apple-ios aarch64-apple-ios-sim x86_64-apple-ios >/dev/null
RUSTC="$RUSTC_BIN" RUSTDOC="$RUSTDOC_BIN" "$CARGO_BIN" build --release --target aarch64-apple-ios
RUSTC="$RUSTC_BIN" RUSTDOC="$RUSTDOC_BIN" "$CARGO_BIN" build --release --target aarch64-apple-ios-sim
RUSTC="$RUSTC_BIN" RUSTDOC="$RUSTDOC_BIN" "$CARGO_BIN" build --release --target x86_64-apple-ios

echo "Built dylibs:"
echo "  target/aarch64-apple-ios/release/libiosrpc.dylib"
echo "  target/aarch64-apple-ios-sim/release/libiosrpc.dylib"
echo "  target/x86_64-apple-ios/release/libiosrpc.dylib"

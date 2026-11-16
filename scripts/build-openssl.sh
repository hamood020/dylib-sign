#!/usr/bin/env bash
# Builds a static libcrypto for iOS arm64 into Vendor/openssl (headers + lib).
# Static linking keeps the app a single binary (no embedded framework to re-sign).
set -euo pipefail

OPENSSL_VERSION="${OPENSSL_VERSION:-3.3.2}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DEST="$ROOT/Vendor/openssl"

if [ -f "$DEST/lib/libcrypto.a" ]; then
  echo "OpenSSL already built in $DEST"
  exit 0
fi

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
cd "$WORK"
echo "Downloading OpenSSL $OPENSSL_VERSION"
curl -fsSL "https://github.com/openssl/openssl/releases/download/openssl-$OPENSSL_VERSION/openssl-$OPENSSL_VERSION.tar.gz" | tar -xz
cd "openssl-$OPENSSL_VERSION"

# no-module: build the legacy provider into libcrypto (zsign loads it for old .p12 files).
./Configure ios64-xcrun \
  no-shared no-module no-tests no-apps no-docs no-ui-console no-engine \
  -mios-version-min=15.0 \
  --prefix="$DEST" --libdir=lib

make -j"$(sysctl -n hw.ncpu)" build_libs >/dev/null
make install_dev >/dev/null

rm -f "$DEST/lib/libssl.a"
rm -rf "$DEST/lib/pkgconfig" "$DEST/lib/cmake"
echo "OpenSSL ready: $(ls "$DEST/lib")"

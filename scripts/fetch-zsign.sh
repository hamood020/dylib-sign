#!/usr/bin/env bash
# Downloads zsign (https://github.com/zhlynn/zsign) into Vendor/zsign and patches it for iOS.
set -euo pipefail

ZSIGN_COMMIT="${ZSIGN_COMMIT:-9299685bab7ef99827e06e5dfda93af747386590}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DEST="$ROOT/Vendor/zsign"

rm -rf "$DEST"
mkdir -p "$DEST"
echo "Downloading zsign @ $ZSIGN_COMMIT"
curl -fsSL "https://github.com/zhlynn/zsign/archive/$ZSIGN_COMMIT.tar.gz" | tar -xz -C "$DEST" --strip-components=1

cd "$DEST/src"

# popen() is not usable on iOS; that path only runs when /usr/bin/csreq exists (never on iOS).
perl -pi -e 's#FILE\* cmd = popen\(strCommand\.c_str\(\), "r"\);#FILE* cmd = NULL;#' signing.cpp
perl -pi -e 's#while \(NULL != fgets\(result, sizeof\(result\), cmd\)\)#while (cmd && NULL != fgets(result, sizeof(result), cmd))#' signing.cpp
perl -pi -e 's#^(\s*)pclose\(cmd\);#$1if (cmd) pclose(cmd);#' signing.cpp

if grep -n 'popen(' signing.cpp; then
  echo "error: popen patch did not apply (zsign changed?)" >&2
  exit 1
fi

echo "zsign ready in $DEST"

#!/bin/bash
# Cassette — local macOS build script.
# Builds the app and copies Foobar2026.app into ./build/ in the project directory.
#
# Usage:
#   ./build.sh                 # Debug build (default)
#   ./build.sh Release         # Release build
#   ./build.sh Debug --clean   # clean first
#   ./build.sh Debug --no-codesign   # force unsigned build
#
# Notes:
#   - Works even when xcode-select points at CommandLineTools, as long as an
#     Xcode.app exists in /Applications (any name, e.g. Xcode-26.3.0.app).
#   - If the project's DEVELOPMENT_TEAM isn't available on this machine, the
#     build automatically falls back to an unsigned build (fine for local runs).

set -euo pipefail

CONFIG="Debug"
CLEAN=0
NO_CODESIGN=0

for arg in "$@"; do
  case "$arg" in
    Debug|Release) CONFIG="$arg" ;;
    --clean) CLEAN=1 ;;
    --no-codesign) NO_CODESIGN=1 ;;
    *) echo "Unknown argument: $arg (expected Debug|Release, --clean, --no-codesign)"; exit 2 ;;
  esac
done

PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$PROJECT_DIR"

PROJECT="Cassette.xcodeproj"
SCHEME="Cassette"
OUT_DIR="$PROJECT_DIR/build"

# --- Locate a usable Xcode ---
find_xcode() {
  if command -v xcodebuild >/dev/null 2>&1 && xcodebuild -version >/dev/null 2>&1; then
    return 0  # xcode-select already points at a full Xcode
  fi
  local candidate
  for candidate in /Applications/Xcode*.app; do
    [ -d "$candidate" ] || continue
    if [ -x "$candidate/Contents/Developer/usr/bin/xcodebuild" ]; then
      export DEVELOPER_DIR="$candidate/Contents/Developer"
      echo "Using Xcode at $candidate (xcode-select was not pointing at a full Xcode)"
      return 0
    fi
  done
  echo "error: no usable Xcode found (xcode-select points at: $(xcode-select -p))" >&2
  exit 1
}
find_xcode

# --- Build ---
XCODEBUILD_ARGS=(
  -project "$PROJECT"
  -scheme "$SCHEME"
  -configuration "$CONFIG"
  -destination 'platform=macOS'
)
if [ "$CLEAN" -eq 1 ]; then
  echo "==> Cleaning…"
  xcodebuild "${XCODEBUILD_ARGS[@]}" clean >/dev/null
fi

echo "==> Building ($CONFIG)…"
set +e
if [ "$NO_CODESIGN" -eq 1 ]; then
  xcodebuild "${XCODEBUILD_ARGS[@]}" CODE_SIGNING_ALLOWED=NO build
  BUILD_STATUS=$?
else
  xcodebuild "${XCODEBUILD_ARGS[@]}" build
  BUILD_STATUS=$?
  # Missing provisioning profiles / unavailable team → retry unsigned.
  if [ $BUILD_STATUS -ne 0 ]; then
    echo "==> Build failed — retrying without code signing (fine for local runs)…"
    xcodebuild "${XCODEBUILD_ARGS[@]}" CODE_SIGNING_ALLOWED=NO build
    BUILD_STATUS=$?
  fi
fi
set -e
if [ $BUILD_STATUS -ne 0 ]; then
  echo "error: build failed" >&2
  exit $BUILD_STATUS
fi

# --- Locate the built product ---
BUILT_PRODUCTS_DIR="$(xcodebuild "${XCODEBUILD_ARGS[@]}" -showBuildSettings 2>/dev/null \
  | awk '/ BUILT_PRODUCTS_DIR = /{print $3; exit}')"
if [ -z "$BUILT_PRODUCTS_DIR" ] || [ ! -d "$BUILT_PRODUCTS_DIR/Foobar2026.app" ]; then
  echo "error: could not locate built Foobar2026.app" >&2
  exit 1
fi

# --- Copy into the project ---
mkdir -p "$OUT_DIR"
rm -rf "$OUT_DIR/Foobar2026.app"
ditto "$BUILT_PRODUCTS_DIR/Foobar2026.app" "$OUT_DIR/Foobar2026.app"

echo "==> Done: $OUT_DIR/Foobar2026.app"
echo "    Open with: open \"$OUT_DIR/Foobar2026.app\""

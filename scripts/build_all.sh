#!/usr/bin/env bash
# Build the release app for macOS: bundle the backend with PyInstaller, drop
# it into the Flutter assets, then build the Flutter app around it.
#
#   scripts/build_all.sh
#   PYTHON=/opt/homebrew/bin/python3.12 scripts/build_all.sh

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BACKEND="$ROOT/backend"
FRONTEND="$ROOT/frontend"
VENV="$BACKEND/.venv-build"
ASSET_DIR="$FRONTEND/assets/backend"

# A separate venv from the dev one (backend/.venv), so whatever happens to be
# installed there for development does not end up in the bundle.
echo "==> Python venv ($VENV)"
if [ ! -x "$VENV/bin/python" ]; then
  "${PYTHON:-python3}" -m venv "$VENV"
fi
"$VENV/bin/python" -m pip install --upgrade pip
"$VENV/bin/python" -m pip install -r "$BACKEND/requirements.txt" pyinstaller

echo "==> PyInstaller"
# One folder, zipped: a one-file build unpacks itself on every launch, which
# with antivirus scanning the fresh files took ~15 s each time.
"$VENV/bin/python" "$BACKEND/build_backend.py" --onedir --zip

echo "==> Copy backend into Flutter assets"
mkdir -p "$ASSET_DIR"
# Anything left from an earlier build would be shipped too.
find "$ASSET_DIR" -mindepth 1 ! -name .gitkeep -exec rm -rf {} +
cp "$BACKEND/dist/diagnostic_backend.zip" "$BACKEND/dist/diagnostic_backend.sha256" "$ASSET_DIR/"

echo "==> flutter build macos"
(cd "$FRONTEND" && flutter build macos --release)

echo
echo "Done: $FRONTEND/build/macos/Build/Products/Release"

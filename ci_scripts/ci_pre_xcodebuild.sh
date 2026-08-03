#!/bin/zsh

# Safeguard: Get the repository root path
ROOT_DIR="${CI_PRIMARY_REPOSITORY_PATH:-$CI_WORKSPACE}"

if [ -z "$ROOT_DIR" ]; then
    ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
fi

# Save directly to the repository root where Xcode is searching for it
echo "$GOOGLE_SERVICE_INFO_PLIST" | base64 -d > "$ROOT_DIR/GoogleService-Info.plist"

# Set permissions
chmod 644 "$ROOT_DIR/GoogleService-Info.plist"
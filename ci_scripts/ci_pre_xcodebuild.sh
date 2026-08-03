#!/bin/zsh

# Safeguard: Fallback to current directory parent if $CI_PRIMARY_REPOSITORY_PATH isn't set locally
ROOT_DIR="${CI_PRIMARY_REPOSITORY_PATH:-$CI_WORKSPACE}"

# If running locally without Xcode Cloud vars, default to parent directory of ci_scripts
if [ -z "$ROOT_DIR" ]; then
    ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
fi

# Decode the secret into the target path
echo "$GOOGLE_SERVICE_INFO_PLIST" | base64 -d > "$ROOT_DIR/Omok/GoogleService-Info.plist"

# Set permissions
chmod 644 "$ROOT_DIR/Omok/GoogleService-Info.plist"
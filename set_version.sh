#!/bin/bash

# Studio Guru Version Manager
# Usage: ./set_version.sh [version] [build]
# Example: ./set_version.sh 1.0-beta1 1

if [ $# -eq 0 ]; then
    echo "📱 Current version information:"
    echo ""
    /usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "Studio Guru/Info.plist" 2>/dev/null || echo "Marketing Version: Not found in Info.plist"
    /usr/libexec/PlistBuddy -c "Print :CFBundleVersion" "Studio Guru/Info.plist" 2>/dev/null || echo "Build Version: Not found in Info.plist"
    echo ""
    echo "Usage: $0 [version] [build]"
    echo "Example: $0 1.0-beta1 1"
    echo "Example: $0 1.0 5"
    exit 0
fi

VERSION=$1
BUILD=${2:-1}

echo "Setting version to: $VERSION (build $BUILD)"

# Update using xcrun agvtool (if available)
xcrun agvtool new-marketing-version "$VERSION"
xcrun agvtool new-version -all "$BUILD"

echo "✅ Version updated!"
echo "   Marketing Version: $VERSION"
echo "   Build Number: $BUILD"

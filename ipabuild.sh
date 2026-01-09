#!/bin/bash

set -e

cd "$(dirname "$0")"

WORKING_LOCATION="$(pwd)"
APPLICATION_NAME="Luna"

PLATFORM=${1:-ios}

case "$PLATFORM" in
    ios|iOS)
        PLATFORM="ios"
        SDK="iphoneos"
        XCODE_DESTINATION="generic/platform=iOS"
        PLATFORM_DIR="Release-iphoneos"
        OUTPUT_SUFFIX=""
        ;;
    tvos|tvOS)
        PLATFORM="tvos"
        SDK="appletvos"
        XCODE_DESTINATION="generic/platform=tvOS"
        PLATFORM_DIR="Release-appletvos"
        OUTPUT_SUFFIX="-tvOS"
        ;;
    *)
        echo "Error: Invalid platform '$PLATFORM'"
        echo "Usage: $0 [ios|tvos]"
        echo "  ios  - Build for iOS (default)"
        echo "  tvos - Build for tvOS"
        exit 1
        ;;
esac

if [ ! -d "build" ]; then
    mkdir build
fi

cd build

if [ -d "DerivedData$PLATFORM" ]; then
    rm -rf "DerivedData$PLATFORM"
fi

# Use workspace if it exists (after pod install), otherwise use project
if [ -f "$WORKING_LOCATION/$APPLICATION_NAME.xcworkspace/contents.xcworkspacedata" ]; then
    echo "Building with workspace (CocoaPods detected)"
    XCODE_PROJECT="-workspace $WORKING_LOCATION/$APPLICATION_NAME.xcworkspace"
else
    echo "Building with project"
    XCODE_PROJECT="-project $WORKING_LOCATION/$APPLICATION_NAME.xcodeproj"
fi

# Create archive (required for proper IPA structure)
ARCHIVE_PATH="$WORKING_LOCATION/build/$APPLICATION_NAME$OUTPUT_SUFFIX.xcarchive"

# Use xcconfig to ensure bundle identifier and build settings are loaded
XCCONFIG="$WORKING_LOCATION/Build.xcconfig"

xcodebuild archive \
    $XCODE_PROJECT \
    -scheme "$APPLICATION_NAME" \
    -configuration Release \
    -archivePath "$ARCHIVE_PATH" \
    -destination "$XCODE_DESTINATION" \
    -sdk "$SDK" \
    -xcconfig "$XCCONFIG" \
    CODE_SIGN_IDENTITY="" \
    CODE_SIGNING_REQUIRED=NO \
    CODE_SIGNING_ALLOWED=NO \
    ENABLE_USER_SCRIPT_SANDBOXING=NO

# Verify archive was created
if [ ! -d "$ARCHIVE_PATH" ]; then
    echo "Error: Archive failed to create at $ARCHIVE_PATH"
    exit 1
fi

# Extract app from archive (correct path: Products/Applications)
APP_PATH="$ARCHIVE_PATH/Products/Applications/$APPLICATION_NAME.app"

if [ ! -d "$APP_PATH" ]; then
    echo "Error: App not found at $APP_PATH"
    echo "Contents of archive:"
    find "$ARCHIVE_PATH" -type d -name "*.app" 2>/dev/null || echo "No app bundles found"
    exit 1
fi

# Create Payload directory and copy app
mkdir Payload
cp -r "$APP_PATH" "Payload/$APPLICATION_NAME.app"

# Remove code signature
rm -rf "Payload/$APPLICATION_NAME.app/_CodeSignature" 2>/dev/null || true
rm -f "Payload/$APPLICATION_NAME.app/embedded.mobileprovision" 2>/dev/null || true

# Create IPA (preserve symlinks with -y, recursive with -r)
zip -qry "$APPLICATION_NAME$OUTPUT_SUFFIX.ipa" Payload

# Cleanup
rm -rf Payload
rm -rf "$ARCHIVE_PATH"

if [ -f "Payload/$APPLICATION_NAME.app/$APPLICATION_NAME" ]; then
    strip "Payload/$APPLICATION_NAME.app/$APPLICATION_NAME" 2>/dev/null || true
fi

zip -qr "$APPLICATION_NAME$OUTPUT_SUFFIX.ipa" Payload

rm -rf "$TARGET_APP"
rm -rf Payload

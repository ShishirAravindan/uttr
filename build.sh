#!/bin/bash
set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Default values
CONFIGURATION="Release"
CLEAN=false
OPEN_APP=false
PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"

usage() {
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Build uttr from source"
    echo ""
    echo "Options:"
    echo "  -c, --configuration  Build configuration: Debug or Release (default: Release)"
    echo "  -C, --clean          Clean build folder before building"
    echo "  -o, --open           Open app after successful build"
    echo "  -h, --help           Show this help message"
    echo ""
    echo "Examples:"
    echo "  $0                   # Release build"
    echo "  $0 -c Debug          # Debug build"
    echo "  $0 --clean --open    # Clean Release build, then open app"
}

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -c|--configuration)
            CONFIGURATION="$2"
            shift 2
            ;;
        -C|--clean)
            CLEAN=true
            shift
            ;;
        -o|--open)
            OPEN_APP=true
            shift
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            echo -e "${RED}Unknown option: $1${NC}"
            usage
            exit 1
            ;;
    esac
done

# Validate configuration
if [[ "$CONFIGURATION" != "Debug" && "$CONFIGURATION" != "Release" ]]; then
    echo -e "${RED}Invalid configuration: $CONFIGURATION${NC}"
    echo "Must be 'Debug' or 'Release'"
    exit 1
fi

cd "$PROJECT_DIR"

echo -e "${GREEN}=== uttr Build ===${NC}"
echo -e "Configuration: ${YELLOW}$CONFIGURATION${NC}"
echo ""

# Clean if requested
if [ "$CLEAN" = true ]; then
    echo -e "${YELLOW}Cleaning build folder...${NC}"
    xcodebuild -project uttr.xcodeproj \
        -scheme uttr \
        -configuration "$CONFIGURATION" \
        -destination 'platform=macOS,arch=arm64' \
        clean
    echo ""
fi

# Debug signs the whole app for local use. Release keeps the distribution build's
# existing unsigned behavior; it must not inherit a developer's local identity.
SIGNING_SETTINGS=(CODE_SIGN_IDENTITY="-" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO)
if [ "$CONFIGURATION" = "Debug" ]; then
    SIGNING_SETTINGS=(CODE_SIGNING_ALLOWED=YES)
fi

# Build
echo -e "${YELLOW}Building...${NC}"
xcodebuild -project uttr.xcodeproj \
    -scheme uttr \
    -configuration "$CONFIGURATION" \
    -destination 'platform=macOS,arch=arm64' \
    "${SIGNING_SETTINGS[@]}" \
    build

# Find the built app
BUILD_SETTINGS=$(xcodebuild -project uttr.xcodeproj \
    -scheme uttr \
    -configuration "$CONFIGURATION" \
    -showBuildSettings 2>/dev/null)

BUILD_DIR=$(printf '%s\n' "$BUILD_SETTINGS" | sed -n 's/^[[:space:]]*BUILT_PRODUCTS_DIR = //p' | head -n 1)
APP_BUNDLE_NAME=$(printf '%s\n' "$BUILD_SETTINGS" | sed -n 's/^[[:space:]]*FULL_PRODUCT_NAME = //p' | head -n 1)
APP_PATH="$BUILD_DIR/$APP_BUNDLE_NAME"

echo ""
echo -e "${GREEN}=== Build Successful ===${NC}"
echo -e "Built app: ${YELLOW}$APP_PATH${NC}"

if [ "$CONFIGURATION" = "Release" ]; then
    FINAL_APP_PATH="/Applications/uttr.app"
    echo -e "${YELLOW}Installing to Applications folder...${NC}"
    if [ -d "$FINAL_APP_PATH" ]; then
        echo -e "${YELLOW}Removing existing installation...${NC}"
        rm -rf "$FINAL_APP_PATH"
    fi
    cp -R "$APP_PATH" "$FINAL_APP_PATH"
    echo -e "${GREEN}Installed: ${YELLOW}$FINAL_APP_PATH${NC}"

    if [ "$OPEN_APP" = true ]; then
        echo -e "${YELLOW}Opening app...${NC}"
        open "$FINAL_APP_PATH"
    fi
else
    # Debug builds run in-place — separate bundle ID avoids permission conflicts with /Applications/uttr.app
    echo -e "${YELLOW}Debug build — skipping Applications install (bundle ID: io.github.Rakk301.uttr.debug)${NC}"

    if [ "$OPEN_APP" = true ]; then
        echo -e "${YELLOW}Opening app from build directory...${NC}"
        open "$APP_PATH"
    fi
fi

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
    echo "Build the uttr without Xcode"
    echo ""
    echo "Options:"
    echo "  -c, --configuration  Build configuration: Debug or Release (default: Release)"
    echo "  -C, --clean          Clean build folder before building"
    echo "  -o, --open           Open the app after successful build"
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
        clean
    echo ""
fi

# Build
echo -e "${YELLOW}Building...${NC}"
xcodebuild -project uttr.xcodeproj \
    -scheme uttr \
    -configuration "$CONFIGURATION" \
    -destination 'platform=macOS' \
    CODE_SIGN_IDENTITY="-" \
    CODE_SIGNING_REQUIRED=NO \
    CODE_SIGNING_ALLOWED=NO \
    build

# Find the built app
BUILD_DIR=$(xcodebuild -project uttr.xcodeproj \
    -scheme uttr \
    -configuration "$CONFIGURATION" \
    -showBuildSettings 2>/dev/null | grep -m1 "BUILT_PRODUCTS_DIR" | awk '{print $3}')

APP_PATH="$BUILD_DIR/uttr.app"

echo ""
echo -e "${GREEN}=== Build Successful ===${NC}"
echo -e "App location: ${YELLOW}$APP_PATH${NC}"

# Open if requested
if [ "$OPEN_APP" = true ]; then
    if [ -d "$APP_PATH" ]; then
        echo -e "${YELLOW}Opening app...${NC}"
        open "$APP_PATH"
    else
        echo -e "${RED}App not found at expected location${NC}"
        exit 1
    fi
fi


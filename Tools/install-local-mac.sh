#!/bin/bash
# Build and install the owner's consistently signed local Mac app.
# This preserves the existing non-sandboxed development data locations. Distribution
# sandboxing remains enabled in the Xcode target and requires its own data migration.
set -euo pipefail
cd "$(dirname "$0")/.."

identity="${ANGROVE_SIGNING_IDENTITY:-Apple Development: rbaltodano337@gmail.com (T86LKF9KM2)}"
destination="${ANGROVE_MAC_INSTALL_PATH:-/Applications/Angrove.app}"
derived="$PWD/build/mac-local"
app="$derived/Build/Products/Release/Angrove-macOS.app"
staged="${destination%.app}.staging.app"
backupDirectory="$PWD/build/mac-installed-backups"
backup="$backupDirectory/Angrove-$(date +%Y%m%d-%H%M%S).zip"

# Refuse to rebuild/replace an app while it is running. Quit normally first so
# pending state can save; never force-terminate a workspace during installation.
if pgrep -f '/Angrove[^/]*\.app/Contents/MacOS/Angrove-macOS' >/dev/null; then
    echo 'Angrove is still running. Quit it, then rerun this installer.' >&2
    exit 1
fi

xcodebuild -project Angrove-iOS.xcodeproj -scheme Angrove-macOS \
    -configuration Release -destination 'platform=macOS,arch=arm64' \
    -derivedDataPath "$derived" -disableAutomaticPackageResolution \
    CODE_SIGNING_ALLOWED=NO build

# Sign embedded code inside-out, then the bundle. Do not use ad hoc signing for
# the app that reads personal stores: its designated requirement changes per build.
while IFS= read -r -d '' library; do
    codesign --force --sign "$identity" --options runtime "$library"
done < <(find "$app/Contents/Frameworks" -type f -name '*.dylib' -print0)
while IFS= read -r -d '' framework; do
    codesign --force --sign "$identity" --options runtime "$framework"
done < <(find "$app/Contents/Frameworks" -type d -name '*.framework' -print0)
codesign --force --sign "$identity" --options runtime "$app"
codesign --verify --deep --strict "$app"
codesign -dr - "$app"

# Check again in case someone opened a copy during the build.
if pgrep -f '/Angrove[^/]*\.app/Contents/MacOS/Angrove-macOS' >/dev/null; then
    echo 'Angrove is still running. Quit it, then rerun this installer.' >&2
    exit 1
fi

mkdir -p "$(dirname "$destination")"
if [[ -e "$staged" || -e "$backup" ]]; then
    echo "Preserving an earlier staged app or backup. Move it aside before reinstalling: $staged / $backup" >&2
    exit 1
fi
ditto "$app" "$staged"
codesign --verify --deep --strict "$staged"
if [[ -e "$destination" ]]; then
    # Keep recoverable rollback archives out of Applications and Spotlight's app list.
    mkdir -p "$backupDirectory"
    ditto -c -k --sequesterRsrc --keepParent "$destination" "$backup"
    # Move the intact old bundle out of the way until the verified replacement lands.
    previous="${staged%.app}.previous.app"
    if [[ -e "$previous" ]]; then
        echo "Preserving an earlier interrupted installation: $previous" >&2
        exit 1
    fi
    mv "$destination" "$previous"
    if ! mv "$staged" "$destination"; then
        mv "$previous" "$destination"
        exit 1
    fi
    # The old bundle is recoverable in the archive created above.
    rm -rf "$previous"
else
    mv "$staged" "$destination"
fi
open "$destination"
echo "Installed: $destination"

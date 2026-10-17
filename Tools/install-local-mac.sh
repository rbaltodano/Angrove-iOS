#!/bin/bash
# Build and install the owner's signed, sandboxed local Mac app.
# Xcode signs the app, Question of the Day widget and model downloader with their development
# profiles, so the installed app runs with the same sandbox, App Group and entitlements as the
# distribution build. The first sandboxed launch moves the pre-sandbox data into the app's
# container (macOS/Resources/container-migration.plist); a copy of the personal data is kept first.
set -euo pipefail
cd "$(dirname "$0")/.."

destination="${ANGROVE_MAC_INSTALL_PATH:-/Applications/Angrove.app}"
derived="$PWD/build/mac-local"
app="$derived/Build/Products/Release/Angrove-macOS.app"
staged="${destination%.app}.staging.app"
backupDirectory="$PWD/build/mac-installed-backups"
stamp="$(date +%Y%m%d-%H%M%S)"
backup="$backupDirectory/Angrove-$stamp.zip"
legacyData="$HOME/Library/Application Support/Angrove-macOS"
legacyPreferences="$HOME/Library/Preferences/com.ryanbaltodano.Angrove.macOS.plist"
container="$HOME/Library/Containers/com.ryanbaltodano.Angrove.macOS"

# Refuse to rebuild/replace an app while it is running. Quit normally first so
# pending state can save; never force-terminate a workspace during installation.
if pgrep -f '/Angrove[^/]*\.app/Contents/MacOS/Angrove-macOS' >/dev/null; then
    echo 'Angrove is still running. Quit it, then rerun this installer.' >&2
    exit 1
fi

# macOS moves pre-sandbox data into the container only when it creates the container. If one
# already exists, the data would stay behind and the app would start empty: stop instead.
if [[ -d "$legacyData" && -d "$container" ]]; then
    cat >&2 <<MESSAGE
Angrove's pre-sandbox data is still at:
  $legacyData
but a sandbox container already exists at:
  $container
macOS only moves data into a container it is creating, so this install would open without
your conversations. If that container holds nothing you need (it was made by an earlier test
build), move it to the Trash in Finder, then rerun this installer. Nothing has been changed.
MESSAGE
    exit 1
fi

xcodebuild -project Angrove-iOS.xcodeproj -scheme Angrove-macOS \
    -configuration Release -destination 'platform=macOS,arch=arm64' \
    -derivedDataPath "$derived" -disableAutomaticPackageResolution \
    -allowProvisioningUpdates build

codesign --verify --deep --strict "$app"
for bundle in "$app" "$app/Contents/PlugIns/AngroveMacWidgets.appex" \
    "$app/Contents/Extensions/AngroveMacModelDownloader.appex"; do
    entitlements="$(codesign -d --entitlements - --xml "$bundle" 2>/dev/null)"
    for key in com.apple.security.app-sandbox com.apple.security.application-groups; do
        if [[ "$entitlements" != *"$key"* ]]; then
            echo "Missing $key in $bundle; not installing." >&2
            exit 1
        fi
    done
done
codesign -dr - "$app"

# Check again in case someone opened a copy during the build.
if pgrep -f '/Angrove[^/]*\.app/Contents/MacOS/Angrove-macOS' >/dev/null; then
    echo 'Angrove is still running. Quit it, then rerun this installer.' >&2
    exit 1
fi

# Before the move into the container, keep a copy of the personal data (not the models or caches).
if [[ -d "$legacyData" ]]; then
    dataBackup="$PWD/build/mac-data-backups/$stamp"
    mkdir -p "$dataBackup"
    for item in "$legacyData"/*; do
        [[ "$(basename "$item")" == "Models" ]] && continue
        ditto "$item" "$dataBackup/Application Support/Angrove-macOS/$(basename "$item")"
    done
    [[ -f "$legacyPreferences" ]] && ditto "$legacyPreferences" "$dataBackup/Preferences/$(basename "$legacyPreferences")"
    echo "Personal data copied to $dataBackup before the first sandboxed launch."
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
if [[ "${ANGROVE_MAC_LAUNCH_AFTER_INSTALL:-1}" == "1" ]]; then
    open "$destination"
fi
echo "Installed: $destination"

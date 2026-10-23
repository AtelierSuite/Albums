#!/bin/zsh
# Captures raw Mac App Store screenshots into Raw/Mac/<language>/.
# Usage: ./capture-mac.sh [languages...]   (defaults to en ja)
#
# Runs the AppStoreScreenshots UI test against the Mac Catalyst build. A debug
# build shares the App Store app's containers, so any existing data is moved
# aside for the run and put back afterwards, even if the run fails. iCloud sync
# stays off while the app runs in screenshot mode. Needs an unlocked screen,
# and the test runner needs Accessibility access the first time.
# Run compose.swift afterwards to frame them.
set -e

SCRIPT_DIR=${0:A:h}
PROJECT_DIR=${SCRIPT_DIR:h:h}
BUNDLE_ID=com.tsubuzaki.IllustMate
GROUP_ID=group.com.tsubuzaki.IllustMate
DERIVED_DATA=/tmp/illustmate-mac-screenshots-dd
LANGUAGES=($@)
(( $# )) || LANGUAGES=(en ja)
CONTAINER=~/Library/Containers/$BUNDLE_ID
GROUP_CONTAINER=~/Library/Group\ Containers/$GROUP_ID
BACKUP=~/Library/Containers/$BUNDLE_ID.screenshots-backup
GROUP_BACKUP=~/Library/Group\ Containers/$GROUP_ID.screenshots-backup
WORK=$(mktemp -d /tmp/illustmate-mac-screenshots.XXXXXX)

# MARK: - Data

if [[ -e $BACKUP || -e $GROUP_BACKUP ]]; then
  echo "A backup from an earlier run is still in place; restore it before capturing:" >&2
  echo "  $BACKUP" >&2
  echo "  $GROUP_BACKUP" >&2
  exit 1
fi

clear_containers() {
  pkill -x "PicMate" 2>/dev/null || true
  rm -rf $CONTAINER $GROUP_CONTAINER
}

restore() {
  clear_containers
  [[ -e $BACKUP ]] && mv $BACKUP $CONTAINER
  [[ -e $GROUP_BACKUP ]] && mv $GROUP_BACKUP $GROUP_CONTAINER
  rm -rf $WORK
}

[[ -e $CONTAINER ]] && mv $CONTAINER $BACKUP
[[ -e $GROUP_CONTAINER ]] && mv $GROUP_CONTAINER $GROUP_BACKUP
trap restore EXIT

# MARK: - Build

xcodebuild build-for-testing -project "$PROJECT_DIR/PicMate.xcodeproj" -scheme PicMate \
  -destination "platform=macOS,variant=Mac Catalyst" -derivedDataPath $DERIVED_DATA -quiet
APP=$(ls -d $DERIVED_DATA/Build/Products/Debug-maccatalyst/*.app | grep -v Runner | head -1)
XCTESTRUN=$(ls $DERIVED_DATA/Build/Products/*.xctestrun | head -1)

# MARK: - Capture

# The sandbox container only exists once the app has run, so it is started
# once and quit before the samples are copied in.
seed() {
  clear_containers
  "$APP/Contents/MacOS/${APP:t:r}" -ScreenshotMode YES >/dev/null 2>&1 &
  local pid=$!
  sleep 6
  kill $pid 2>/dev/null || true
  wait $pid 2>/dev/null || true
  swift "$SCRIPT_DIR/samples.swift" $1 "$CONTAINER/Data/Documents/ScreenshotSeed" >/dev/null
}

for language in $LANGUAGES; do
  raw_dir="$SCRIPT_DIR/Raw/Mac/$language"
  rm -rf "$raw_dir"
  mkdir -p "$raw_dir"
  seed $language

  result="$WORK/$language.xcresult"
  TEST_RUNNER_SCREENSHOT_DIR=$raw_dir TEST_RUNNER_SCREENSHOT_LANGUAGE=$language \
    xcodebuild test-without-building -xctestrun $XCTESTRUN \
    -destination "platform=macOS,variant=Mac Catalyst" -resultBundlePath "$result" \
    -only-testing:PicMateUITests/AppStoreScreenshots/testScreens >"$WORK/$language.log" 2>&1 \
    || { grep -E "error: -\[" "$WORK/$language.log" >&2; exit 1 }

  # A sandboxed test runner can't write to raw_dir, so the captures are taken
  # from the attachments in the result bundle instead.
  if [[ -z $(ls "$raw_dir") ]]; then
    attachments="$WORK/$language-attachments"
    xcrun xcresulttool export attachments --path "$result" --output-path "$attachments"
    python3 -I - "$attachments" "$raw_dir" <<'PYTHON'
import json, os, shutil, sys
source, destination = sys.argv[1], sys.argv[2]
for test in json.load(open(os.path.join(source, "manifest.json"))):
    for attachment in test.get("attachments", []):
        name = attachment["suggestedHumanReadableName"].split("_")[0]
        shutil.copy(os.path.join(source, attachment["exportedFileName"]),
                    os.path.join(destination, f"{name}.png"))
PYTHON
  fi
  echo "captured Mac/$language"
done

#!/bin/bash

set -euo pipefail

if [[ $# -ne 2 ]]; then
  echo "Usage: $0 <x86_64 build directory> <arm64 build directory>" >&2
  exit 2
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SOURCE_DIR="$(cd "$SCRIPT_DIR/../../../.." && pwd)"
X86_BUILD="$1"
ARM_BUILD="$2"
X86_APP="$X86_BUILD/Binaries/Dolphin.app"
ARM_APP="$ARM_BUILD/Binaries/Dolphin.app"
STAGING_DIR="$(mktemp -d "${RUNNER_TEMP:-${TMPDIR:-/tmp}}/primehack-package.XXXXXX")"
MERGE_FILE="$STAGING_DIR/merged-macho"
X86_SLICE="$STAGING_DIR/x86_64-slice"
ARM_SLICE="$STAGING_DIR/arm64-slice"
APPNAME=""

cleanup() {
  rm -rf "$STAGING_DIR"
}
trap cleanup EXIT

if [[ ! -d "$X86_APP" || ! -d "$ARM_APP" ]]; then
  echo "Both architecture builds must contain Binaries/Dolphin.app" >&2
  exit 1
fi

is_macho() {
  file -b "$1" | grep -q 'Mach-O'
}

extract_slice() {
  local source_path="$1" arch="$2" destination_path="$3"
  local archs
  archs="$(lipo -archs "$source_path")"
  if [[ "$archs" == "$arch" ]]; then
    # lipo -thin rejects files that already contain only one architecture.
    cp -p "$source_path" "$destination_path"
  else
    lipo -thin "$arch" "$source_path" -output "$destination_path"
  fi
}

merge_macho_files() {
  local source_path relative_path arm_path destination_path

  while IFS= read -r -d '' source_path; do
    if ! is_macho "$source_path"; then
      continue
    fi

    relative_path="${source_path#"$X86_APP/"}"
    arm_path="$ARM_APP/$relative_path"
    destination_path="$STAGING_APP/$relative_path"

    if [[ ! -f "$arm_path" ]] || ! is_macho "$arm_path"; then
      echo "Missing ARM64 counterpart for Mach-O file: $relative_path" >&2
      exit 1
    fi

    # Dependencies may already be universal even though each application build
    # is single-architecture. Extract one slice from each input before merging.
    extract_slice "$source_path" x86_64 "$X86_SLICE"
    extract_slice "$arm_path" arm64 "$ARM_SLICE"
    lipo -create "$X86_SLICE" "$ARM_SLICE" -output "$MERGE_FILE"
    chmod "$(stat -f '%Lp' "$source_path")" "$MERGE_FILE"
    mv "$MERGE_FILE" "$destination_path"
  done < <(find "$X86_APP" -type f -print0)
}

check_arm_files_have_x86_counterparts() {
  local arm_path relative_path x86_path

  while IFS= read -r -d '' arm_path; do
    if ! is_macho "$arm_path"; then
      continue
    fi

    relative_path="${arm_path#"$ARM_APP/"}"
    x86_path="$X86_APP/$relative_path"
    if [[ ! -f "$x86_path" ]] || ! is_macho "$x86_path"; then
      echo "Missing x86_64 counterpart for Mach-O file: $relative_path" >&2
      exit 1
    fi
  done < <(find "$ARM_APP" -type f -print0)
}

check_universal_macho_files() {
  local path archs

  while IFS= read -r -d '' path; do
    if ! is_macho "$path"; then
      continue
    fi

    archs="$(lipo -archs "$path")"
    if [[ "$archs" != *x86_64* || "$archs" != *arm64* ]]; then
      echo "Mach-O file is not universal: $path ($archs)" >&2
      exit 1
    fi

    if otool -L "$path" | grep -E '/Users/|/opt/homebrew|/usr/local'; then
      echo "Mach-O file still references a build-machine library: $path" >&2
      exit 1
    fi
  done < <(find "$STAGING_APP" -type f -print0)
}

if TAG="$(git -C "$SOURCE_DIR" describe --tags --exact-match HEAD 2>/dev/null)"; then
  SUFFIX="$TAG"
elif [[ "${EVENT_NAME:-push}" == "pull_request" ]]; then
  PR_TITLE="$(printf '%s' "${PR_TITLE:-}" | LC_ALL=C tr -cd '[:alnum:] _-')"
  SUFFIX="pr[${PR_NUM:-0}]-sha[${PR_SHA:-unknown}]-title[$PR_TITLE"
  SUFFIX="$(printf '%.99s' "$SUFFIX")]"
else
  SUFFIX="sha[$(git -C "$SOURCE_DIR" rev-parse --short HEAD)]"
fi

SUFFIX="$(printf '%s' "$SUFFIX" | sed 's#[/:]#_#g; s/[[:space:]]/_/g')"

APPNAME="PrimeHack-$SUFFIX"
STAGING_APP="$STAGING_DIR/$APPNAME.app"
cp -R "$X86_APP" "$STAGING_APP"
check_arm_files_have_x86_counterparts
merge_macho_files

ENTITLEMENTS="$SOURCE_DIR/Source/Core/DolphinQt/DolphinEmu.entitlements"
UPDATER_APP="$STAGING_APP/Contents/Helpers/Dolphin Updater.app"
if [[ -d "$UPDATER_APP" ]]; then
  bash "$SOURCE_DIR/Tools/mac-codesign.sh" - "$UPDATER_APP"
fi
bash "$SOURCE_DIR/Tools/mac-codesign.sh" -e "$ENTITLEMENTS" - "$STAGING_APP"

MIN_VERSION="$(/usr/libexec/PlistBuddy -c 'Print :LSMinimumSystemVersion' "$STAGING_APP/Contents/Info.plist")"
if [[ "$MIN_VERSION" != 26.* ]]; then
  echo "Unexpected minimum macOS version in bundle: $MIN_VERSION" >&2
  exit 1
fi

check_universal_macho_files
codesign --verify --deep --strict --verbose=2 "$STAGING_APP"

ARCHIVE="$SOURCE_DIR/$APPNAME.tar.xz"
tar --options xz:compression-level=9 -cvJf "$ARCHIVE" -C "$STAGING_DIR" "$APPNAME.app"
echo "Created $ARCHIVE"

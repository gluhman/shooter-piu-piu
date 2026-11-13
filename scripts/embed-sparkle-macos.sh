#!/usr/bin/env bash
set -euo pipefail

app="$1"
dist="$2"
public_key="$3"
feed_url="$4"
[[ "$feed_url" == https://* ]] || { printf 'Для Sparkle нужен HTTPS appcast.\n' >&2; exit 1; }
[[ "$public_key" =~ ^[A-Za-z0-9+/]{43}=$ ]] || { printf 'Неверный публичный ключ Sparkle.\n' >&2; exit 1; }

contents="$app/Contents"
helper="$contents/Helpers/Shooter Updater.app"
plist="$contents/Info.plist"

mkdir -p "$contents/Frameworks" "$helper/Contents/MacOS"
ditto "$dist/Sparkle.framework" "$contents/Frameworks/Sparkle.framework"
install -m 644 "$dist/LICENSE" "$contents/Resources/Sparkle-LICENSE.txt"
xcrun clang -arch arm64 -arch x86_64 -mmacosx-version-min=12.0 -fobjc-arc \
    -F "$contents/Frameworks" -framework Sparkle -framework AppKit \
    -Wl,-rpath,@executable_path/../../../../Frameworks \
    "$(dirname "$0")/../platform/macos/shooter-updater.m" -o "$helper/Contents/MacOS/shooter-updater"

plutil -create xml1 "$helper/Contents/Info.plist"
plutil -insert CFBundleExecutable -string shooter-updater "$helper/Contents/Info.plist"
plutil -insert CFBundleIdentifier -string com.shootcontainer.game.updater "$helper/Contents/Info.plist"
plutil -insert CFBundleName -string 'Shooter Updater' "$helper/Contents/Info.plist"
plutil -insert CFBundlePackageType -string APPL "$helper/Contents/Info.plist"
plutil -insert LSMinimumSystemVersion -string 12.0 "$helper/Contents/Info.plist"
plutil -insert LSUIElement -bool YES "$helper/Contents/Info.plist"

plutil -insert SUFeedURL -string "$feed_url" "$plist"
plutil -insert SUPublicEDKey -string "$public_key" "$plist"
plutil -insert SUEnableAutomaticChecks -bool NO "$plist"
plutil -insert SUAllowsAutomaticUpdates -bool NO "$plist"
plutil -insert SUVerifyUpdateBeforeExtraction -bool YES "$plist"
plutil -insert SURequireSignedFeed -bool YES "$plist"
plutil -insert SUSignedFeedFailureExpirationInterval -integer 0 "$plist"

codesign --force --sign - "$helper"
codesign --force --sign - "$app"
codesign --verify --deep --strict "$app"

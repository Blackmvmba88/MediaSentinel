#!/bin/zsh
set -euo pipefail
cd "${0:A:h}"
command -v swiftc >/dev/null || { echo 'Instala Xcode Command Line Tools'; exit 1; }
APP="$PWD/build/Media Sentinel.app"
mkdir -p "$APP/Contents/MacOS"
mkdir -p "$APP/Contents/Resources"
xcrun swift Sources/make-icon.swift "$PWD/build/AppIcon.iconset"
iconutil -c icns "$PWD/build/AppIcon.iconset" -o "$APP/Contents/Resources/AppIcon.icns"
xcrun swiftc Sources/main.swift -O -o "$APP/Contents/MacOS/MediaSentinel" -framework Cocoa -framework SwiftUI -framework CoreAudio
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>local.blackmamba.MediaSentinel</string>
<key>CFBundleName</key><string>Media Sentinel</string>
<key>CFBundleExecutable</key><string>MediaSentinel</string>
<key>CFBundleIconFile</key><string>AppIcon</string>
<key>CFBundleVersion</key><string>3</string>
<key>CFBundleShortVersionString</key><string>1.2</string>
<key>LSMinimumSystemVersion</key><string>14.2</string>
<key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST
codesign --force --sign - "$APP"
codesign --verify --strict "$APP"
echo "$APP"

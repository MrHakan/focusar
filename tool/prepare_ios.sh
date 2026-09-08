#!/usr/bin/env bash
set -euo pipefail

if [[ ! -f ios/Runner.xcodeproj/project.pbxproj ]]; then
  flutter create --platforms=ios --org com.mrhakan --project-name focusar .
fi

/usr/libexec/PlistBuddy -c "Set :CFBundleDisplayName FocusAR" ios/Runner/Info.plist || true
/usr/libexec/PlistBuddy -c "Delete :NSCameraUsageDescription" ios/Runner/Info.plist 2>/dev/null || true
/usr/libexec/PlistBuddy -c "Add :NSCameraUsageDescription string FocusAR uses the camera to place a focus zone on a real surface." ios/Runner/Info.plist

if ! grep -q "platform :ios" ios/Podfile; then
  sed -i '' "1i\\
platform :ios, '13.0'\\
" ios/Podfile
else
  sed -i '' "s/^# *platform :ios.*/platform :ios, '13.0'/" ios/Podfile
fi

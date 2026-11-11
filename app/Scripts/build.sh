#!/bin/zsh
set -euo pipefail
APP_ROOT="${0:A:h:h}"
cd "$APP_ROOT"
command -v xcodegen >/dev/null || { print -u2 'Install XcodeGen: brew install xcodegen'; exit 1; }
LUNAV_DERIVED_DATA="${LUNAV_DERIVED_DATA:-$HOME/Library/Developer/Xcode/DerivedData/LunaV}"
xcodegen generate
xcodebuild -project LunaV.xcodeproj -scheme LunaV -configuration Release \
  -destination 'generic/platform=iOS' -derivedDataPath "$LUNAV_DERIVED_DATA" \
  CODE_SIGNING_ALLOWED=NO build

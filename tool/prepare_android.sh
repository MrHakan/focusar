#!/usr/bin/env bash
set -euo pipefail

if [[ ! -f android/gradlew || ! -f android/gradle/wrapper/gradle-wrapper.jar ]]; then
  flutter create --platforms=android --org com.mrhakan --project-name focusar .
fi

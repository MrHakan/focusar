# FocusAR

FocusAR is a Flutter focus timer for Android and iPhone. It can start instantly in motion-sensor mode or use ARCore/ARKit to anchor a phone-sized focus zone on a desk. The accelerometer, user accelerometer, and gyroscope make sure the device stays face-down until the timer ends.

## Flow

1. Choose 25, 45, 60, or 90 minutes.
2. Start directly with **Motion Sensor**, or optionally scan a surface and place the blue AR focus zone.
3. Put the phone face-down on a stable surface. The timer starts after the phone is still for 1.2 seconds.
4. Acceleration, lifting, or tilting pauses the timer and starts a repeating sound/haptic warning.
5. Returning it face-down for one second resumes the session. The warning stops when the timer finishes.

The AR camera session is disposed before the timer begins to reduce heat and battery usage. FocusAR does not change the operating system's Focus/Digital Wellbeing setting or silently block other apps. iOS does not allow third-party apps to switch the user's system Focus mode, and Android app blocking requires special device-owner or accessibility privileges. The app instead keeps its own guarded focus session active.

## Run

```sh
./tool/prepare_android.sh # Android, first checkout only
# macOS/iPhone: ./tool/prepare_ios.sh
flutter pub get
flutter run
```

AR requires a physical ARCore-supported Android device or an ARKit-capable iPhone. It will not work in a normal simulator. The motion-sensor mode does not require AR or camera access. The current AR renderer requires Android 9 (API 28) or newer; iOS requires version 13 or newer.

## Automated releases

Every push to `main`, or a manual run of **Build and publish mobile apps**, runs analysis and tests, builds both platforms, and replaces the assets on the existing [`release`](https://github.com/MrHakan/focusar/releases/tag/release) release:

- `FocusAR-Android.apk` — installable debug-signed release APK for testing.
- `FocusAR-Android-arm64-v8a.apk` — smaller APK for modern 64-bit Android devices.
- `FocusAR-iOS-unsigned.ipa` — unsigned iOS archive. Apple requires your Developer certificate and provisioning profile before it can be installed on a device or distributed through TestFlight/App Store.

For Play Store distribution, replace the debug signing configuration with an upload keystore kept in GitHub Actions secrets. Do not commit certificates or private keys.

## License

GPL-3.0, matching the repository license.

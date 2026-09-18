# FocusAR

FocusAR is a Flutter focus timer for Android and iPhone. You put the phone
face-down — optionally inside an AR zone anchored to your desk — and the
accelerometer, gyroscope, and linear accelerometer keep it there. Every focused
minute earns a credit, and every credit buys a minute of screen time back.

## Flow

1. Pick a **Deep block** (25/45/60/90 minutes, counts down) or **Earn screen
   time** (open-ended, counts up).
2. Start straight away on the motion sensors, or scan a surface and drop an AR
   focus zone. Drag to reposition it, pinch to resize it, twist to align it.
3. Put the phone face-down. The clock starts after it has been still for 1.2
   seconds.
4. Lifting, tilting, or knocking the phone pauses the clock and starts a
   repeating sound and haptic. Putting it back for a second resumes.
5. Credits accrue per focused second. An unbroken run earns faster: 1.25x after
   25 minutes, 1.5x after 50, 2x after 90. Picking the phone up drops you back
   to the base rate.
6. The balance lives on the focus card. Spend it on a screen-time coupon in
   15-minute to 2-hour blocks.

There is a **Pause** button for when you genuinely need the phone — it holds the
clock and the credits without the alarm, and asks you to put the phone back down
before counting resumes.

## What it does not do

FocusAR does not change the operating system's Focus or Digital Wellbeing
settings, and it does not block other apps. iOS does not let a third-party app
switch the system Focus mode, and Android app blocking needs device-owner or
accessibility privileges. So a coupon is a budget you hold yourself: the app
records what you earned the right to spend and lapses it after 24 hours. The
guarantee it *can* make is the one it makes — the phone stays face-down or the
session stops counting.

The AR camera session is shut down before the timer starts, so an hour-long
block does not cook the battery.

## Layout

```
lib/
  domain/    pure rules: the clock, the credit economy, the motion guard,
             the AR zone transform, the pinch maths
  data/      shared_preferences persistence and the sensor feed
  state/     SessionController (the session state machine) and WalletController
  ui/        screens and widgets
  theme/     palette and type
```

Everything in `domain/` and `state/` is free of platform channels, so the whole
session machine — arming, interruption, recovery, multipliers, pausing — is
covered by unit tests that drive a fake sensor feed and a hand-advanced clock.

## Run

```sh
./tool/prepare_android.sh # Android, first checkout only
# macOS/iPhone: ./tool/prepare_ios.sh
flutter pub get
flutter run
```

```sh
flutter analyze
flutter test
```

AR requires a physical ARCore-supported Android device or an ARKit-capable
iPhone; it will not work in a normal simulator. Motion-sensor mode needs no AR
and no camera access. The AR renderer requires Android 9 (API 28) or newer, and
iOS 13 or newer.

## Automated releases

Every push to `main`, or a manual run of **Build and publish mobile apps**, runs
analysis and tests, builds both platforms, and cuts a **new GitHub release**
carrying:

- `FocusAR-Android.apk` — installable debug-signed release APK for testing.
- `FocusAR-Android-arm64-v8a.apk` — smaller APK for modern 64-bit Android devices.
- `FocusAR-iOS-unsigned.ipa` — unsigned iOS archive. Apple requires your
  Developer certificate and provisioning profile before it can be installed on a
  device or distributed through TestFlight/App Store.

The tag is derived from `version:` in `pubspec.yaml`. A zero patch is dropped, so
`0.2.0+3` publishes as `v0.2`, while `0.2.1+5` publishes as `v0.2.1`. Bump the
version to name the next release.

Pushes that do not bump the version still get a release of their own: the tag
falls back to the build number (`v0.2-build.4`), and then to the workflow run
number (`v0.2-build.4.17`), so two builds never fight over one tag.

The older single `release` tag is left untouched, with whatever assets it already
held.

For Play Store distribution, replace the debug signing configuration with an
upload keystore kept in GitHub Actions secrets. Do not commit certificates or
private keys.

## License

GPL-3.0, matching the repository license.

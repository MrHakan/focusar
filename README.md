# FocusAR

FocusAR is a Flutter focus timer for Android and iPhone. You put the phone
face-down — optionally inside an AR zone anchored to your desk — and the
accelerometer, gyroscope, and linear accelerometer keep it there. Every focused
minute earns a credit, and every credit buys a minute of screen time back.

## Flow

1. Pick a **Deep block** (25/45/60/90 minutes, counts down) or **Earn screen
   time** (open-ended, counts up).
2. Start straight away on the motion sensors, or scan a surface and drop an AR
   focus zone — see [AR placement](#ar-placement).
3. Put the phone face-down. The clock starts after it has been still for 1.2
   seconds.
4. Lifting or tilting the phone pauses the clock and starts a repeating sound
   and haptic. Putting it back for a second resumes. Desk vibration is
   tolerated — see [Motion sensitivity](#motion-sensitivity).
5. Credits accrue per focused second. An unbroken run earns faster: 1.25x after
   25 minutes, 1.5x after 50, 2x after 90. Picking the phone up drops you back
   to the base rate.
6. The balance lives on the focus card. Spend it on a screen-time coupon in
   15-minute to 2-hour blocks.

There is a **Pause** button for when you genuinely need the phone — it holds the
clock and the credits without the alarm, and asks you to put the phone back down
before counting resumes.

## AR placement

The placement screen walks through **Scan → Place → Adjust**:

- **Scan.** A sweeping-phone hint until ARCore/ARKit reports a surface. After
  ten seconds without one it explains what helps (light, texture).
- **Place.** Taps go to the nearest tracked plane within 12 cm–2 m. Loose
  feature points are only accepted before any plane exists, and the zone then
  warns it may drift. Taps that miss say why (too close, too far, off the
  surface).
- **Adjust.** Drag to move, pinch or **− +** to resize, twist or the turn
  buttons (15°) to rotate, reset to the phone-sized default. Tapping elsewhere
  on the desk moves the zone there, keeping its size and heading.

The anchor is always level — only the tap's position is kept — so a leaning
hit pose cannot tilt the zone, and plane overlays are hidden once it is
placed.

**When tracking slips** (iOS), FocusAR polls ARKit for the camera and zone
poses twice a second. An off-screen zone gets an arrow ("Zone is to your
left"); poses that stop arriving or freeze for three seconds mark the zone
lost, bring the planes back, and ask for a tap to put it back with the same
size and heading. **Place again** does the same by hand on either platform.

Android caveats, from `ar_flutter_plugin_2` 0.0.3's native code: its pose
queries are unusable (the camera-pose call advances the AR session, and the
anchor lookup cannot find local anchors), so the automatic lost-zone check is
iOS-only; and it reads a node's rotation as radians where its renderer wants
degrees, so headings cannot be set from Dart. On Android the turn buttons are
hidden, the twist gesture (native) turns the zone, and resizing squares it up
again — so resize first. FocusAR also works around two of the plugin's
Android bugs: new models are sized from the first matrix value as metres
(a phone-sized zone used to arrive a metre long), and gesture-end matrices
come back transposed (echoing them snapped a dragged zone back onto its
anchor).

## Motion sensitivity

Desks shake. Typing, a mug set down, or another phone buzzing next to this one
jolts the phone without turning it over, so the guard tells the two apart: a
phone that turns or tilts is a pick-up after a fraction of a second, while one
that only shakes in place gets a longer grace, and any calm sample in between
forgives the shake. A hard snatch still alarms at once.

The sensor settings (the slider icon on the home screen) offer three levels —
**Strict** (the original behaviour), **Balanced** (the default), and
**Relaxed** — and a **desk calibration**: lay the phone face-down where you
work and carry on for eight seconds. FocusAR replays what it felt, 25% harder,
through every level using the same guard a session uses, and suggests the
strictest one that would not have raised a false alarm.

## Locking, backgrounding, and crashes

- **Leaving the app** — locking the screen, switching apps, or sending FocusAR
  to the background — counts as one pick-up if the clock was running. While
  the app is out of sight nothing counts and the sensors cannot resume the
  session, so Android and iPhone behave the same whether or not the OS keeps
  the app alive. Coming back shows how long you were away, and the phone has
  to go face-down again before the clock moves.
- **Transient overlays** — an incoming-call screen, a system sheet, the app
  switcher passing over — are not pick-ups on their own. The app is still on
  screen, so the motion sensors decide.
- **A frozen app** — one the OS suspended without telling it — is caught by
  the heartbeat: a beat more than five seconds late is treated as leaving,
  and the gap is not paid for.
- **A killed app** loses at most ten seconds. A running session saves a
  checkpoint every ten focused seconds and whenever it stops counting; the
  next launch banks it and says so. The balance and a marker of the last
  banked session are written together, so a recovered session is never paid
  twice.

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

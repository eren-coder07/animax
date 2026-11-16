# Building the Animax Netflix-UI APK

Two ways to get `app-release.apk` — pick whichever suits you.

---

## Option A — GitHub Actions (no local setup, recommended)

1. Create a repository on GitHub (e.g. `animax`).
2. Upload this entire folder's contents to it (web UI upload, or `git push`).
3. Open the **Actions** tab → select **"Build Animax APK (Netflix UI)"** → **Run workflow**.
   (It also runs automatically on every push.)
4. When the run finishes (about 5–8 minutes), click it → **Artifacts** → download
   **`animax-netflix-ui-apk`** → unzip → you get **`app-release.apk`**.
5. Copy it to your phone and install ("install unknown apps" permission needed).

The workflow file lives at `.github/workflows/build-apk.yml`. It builds with
Flutter 3.47.9 / Java 21 and produces a release APK covering arm64-v8a and
armeabi-v7a devices (the two real-world phone ABIs).

## Option B — Build locally (Linux/macOS/Windows with Android tooling)

```bash
flutter pub get
flutter build apk --release \
  --target-platform android-arm64,android-arm \
  --dart-define=cronetHttpNoPlay=true
```

APK lands in `build/app/outputs/flutter-apk/app-release.apk`.

Requirements: Flutter 3.47.9 (or any stable ≥ 3.47), Android SDK with
platform 36 + build-tools 36 + NDK (auto-installed by Gradle), JDK 17+.

---

## What changed for the Netflix UI

| Area | Change |
| --- | --- |
| `lib/core/app_theme.dart` | Full Netflix palette: pure-black `#000000` background, `#181818` surfaces, `#E50914` accent red, `#B3B3B3` secondary text |
| Accent rename | `AppColors.green → accent`, `greenDeep → accentDeep`, `greenGrad → accentGrad` across all 18 UI files |
| Buttons | New white "Play" variant (`PrimaryButton.white`) used on the details hero, Netflix-style red CTAs elsewhere |
| Bottom nav | White active tab + red indicator dot |
| Splash | Red wordmark on pure black |
| Posters | Tight 6px corners (Netflix-style) |
| Launcher icon | Generated black-square + red "A" adaptive icon (all densities) |
| `lib/core/video_backend.dart` | (from the Windows task) platform-abstracted player — untouched by the restyle |

`lib/core/video_backend.dart` keeps Android on ExoPlayer via `video_player`;
Windows builds use mpv. The APK build is unaffected by it.

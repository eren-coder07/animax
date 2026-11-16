# Building Animax as a Windows .exe

This folder is your original Flutter source, prepared for a Windows desktop
build. On a Windows PC the whole process is a **single double-click** on
`build_exe.bat`.

---

## 1. One-time setup (on the Windows PC)

| Requirement | Notes |
| --- | --- |
| **Flutter SDK** (stable) | https://docs.flutter.dev/get-started/install/windows |
| **Visual Studio 2022 Community** | During installer, tick the **"Desktop development with C++"** workload. That installs MSVC + Windows SDK, which Flutter needs to produce the exe. |
| **Git for Windows** | Needed by the Flutter tool. |

Then open a new terminal and check:

```
flutter doctor
```

Everything in the Flutter / Visual Studio rows must be green (Android Studio
rows can stay red — they are not needed for the exe).

## 2. Build the exe

Double-click **`build_exe.bat`** (or run it from a terminal). It does:

1. `flutter pub get`
2. `flutter build windows --release`
3. Collects the output into `Animax-1.6.1-windows-x64\` and zips it.

**The result:**

```
Animax-1.6.1-windows-x64\
├── animax.exe            ← the app
├── flutter_windows.dll   ← runtime
├── *.dll                 ← plugins (media_kit / mpv, shared_preferences, ...)
└── data\                 ← app bundle (fonts, icons, AOT code)
```

To give the app to someone else, share the **whole folder** (or the generated
zip), not just `animax.exe` — the exe needs the DLLs and the `data\` directory
next to it. No installation required; it is fully portable.

## 3. What was changed compared to your Android-only source

| Change | Why |
| --- | --- |
| Added the `windows\` platform folder (runner, CMake, resources) | Flutter needs it to produce an exe; `flutter create --platforms=windows` generated it. |
| Added `lib\core\video_backend.dart` + patched the two player screens | Google's official `video_player` package has **no Windows implementation**. The new platform-agnostic controller keeps ExoPlayer on Android (zero behavior change) and uses **media_kit (libmpv)** for playback on Windows — same UI, same custom controls overlay. |
| Added `media_kit`, `media_kit_video`, `media_kit_libs_windows_video` to `pubspec.yaml` | The mpv engine for Windows. Android APK builds ignore these (no size impact). |
| `build_exe.bat` | One-click build + packaging script. |

Your Android project is untouched — the same code still builds the APK exactly
as before. If your older Android Flutter version ever complains about the new
`pubspec.lock`, just run `flutter pub get` with that SDK and it will re-resolve.

## 4. Good to know

- The UI is designed portrait/mobile-first, so it shows phone-style layouts in
  the desktop window. Player fullscreen toggle works fine.
- The `setKeepScreenOn` / `openUrl` Android-native hooks are safely ignored on
  Windows (they are wrapped in try/catch).
- **Cloudflare-protected streams** (the +18 section) rely on Cronet's
  Chrome-like TLS fingerprint, which is Android-only. On Windows those streams
  may answer 403 to the mpv player even with the right headers. The main
  catalog is not affected; if a particular server refuses, the player falls
  back to the next server automatically.
- Code status before shipping this folder: `flutter analyze` → 0 issues,
  `flutter test` → 43/43 passed, full kernel compile OK.

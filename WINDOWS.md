# Animax on Windows

## Download / install

GitHub Actions builds Windows on every push to `main` and on every pull
request (`.github/workflows/build-windows.yml`). The `animax-windows`
artifact of a run contains:

| File | What it is |
| --- | --- |
| `AnimaxSetup-<version>-x64.exe` | Single-file installer (per-user, no admin needed). Adds Start-menu and optional desktop shortcuts. |
| `Animax-<version>-windows-x64-portable.zip` | Portable build — unzip anywhere and run `animax.exe` (keep the DLLs and `data\` next to it). |

Requirements: Windows 10/11 x64. Cinema/Cartoons use the Microsoft Edge
WebView2 runtime (built into Windows 11, installed with Edge on Windows 10).
The MSVC runtime DLLs are bundled.

## How Windows support works

| Piece | Windows implementation |
| --- | --- |
| Native players (anime, 18+, Akwam) | `video_player` routed to **media_kit / libmpv** via `video_player_media_kit` (enabled in `main.dart` on Windows only; Android keeps ExoPlayer). |
| Cinema / Cartoons embed players | `webview_flutter` backed by **WebView2** via `webview_win_floating`. |
| Downloads | Saved to `Downloads\Animax\{Videos,Comics}`; opened with the default app. HLS streams with separate audio cannot be merged on Windows (no MediaMuxer), so those save as a video file + an `(audio).m4a` file. |
| HTTP | `dart:io` (Cronet is Android-only). Cloudflare-fronted sources such as the 18+ catalog may refuse Windows requests. |
| Window | Opens as a 480×900 phone-shaped window (`windows/runner/main.cpp`); resizable. |

## Building locally

Needs Flutter 3.47.9, Visual Studio 2022 with "Desktop development with
C++", and a JDK (for the `jni` plugin):

```
flutter pub get
flutter build windows --release
"%ProgramFiles(x86)%\Inno Setup 6\ISCC.exe" windows\installer\animax.iss
```

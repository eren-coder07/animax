# Animax v1.9.0 — 55 Features

This release adds **55 new features** across the whole app: two brand-new
entertainment sections (Cartoons, Comics), a re-engineered Cinema player,
gesture-rich native players, a personal library layer and a themeable UI.

## Cinema — verification-failed fix + player overhaul (11)

| # | Feature | Where |
|---|---------|-------|
| 1 | **FIX: "Verification failed"** — 7 embed servers per title, failure pages auto-detected via JS probe and skipped silently | `core/cinema_providers.dart`, `screens/cinema_player_screen.dart` |
| 2 | In-player server switcher (bottom sheet with provider names + current pick) | cinema player |
| 3 | Smart retry: 14 s no-video watchdog + "N servers left in queue" status | cinema player |
| 4 | TMDB-id support (`moviedb_id` from Cinemeta) unlocks VidLink for series | `core/cinema_api.dart` |
| 5 | Auto-next-episode for cinema series (embed `postMessage` pump → 10 s countdown dialog) | cinema player |
| 6 | Episode picker drawer inside the cinema player | cinema player |
| 7 | Default cinema server preference (Settings → Player) | `core/app_prefs.dart` |
| 8 | Cinema watch-state tracking (movie / SxxExy watched flags) | `core/library_store.dart` |
| 9 | Cinema "save to My List" bookmark in details | `screens/cinema_details_screen.dart` |
| 10 | "Retry all" / "Pick server" recovery card when every server fails | cinema player |
| 11 | Allow-list extended to all 7 providers + CDNs (popunders still blocked) | `core/cinema_providers.dart` |

## Comics (MangaDex) — new section (12)

| # | Feature | Where |
|---|---------|-------|
| 12 | Comics tab — Popular / Latest updates / Fresh releases / Top rated rows | `screens/comic_tab.dart` |
| 13 | Manga search with debounce + poster grid results | comic tab |
| 14 | Genre chips → paginated catalog grid (infinite scroll) | `screens/comic_catalog_screen.dart` |
| 15 | Manga details — cover hero, status/year/chapters/authors meta, expandable description, genre tags | `screens/comic_details_screen.dart` |
| 16 | Chapter list with read markers, page counts, publish dates, per-chapter progress % | comic details |
| 17 | Vertical reader (swipe up/down, snap pages) | `screens/comic_reader_screen.dart` |
| 18 | Paged reader with right-to-left manga mode | comic reader |
| 19 | Reader settings sheet — layout, RTL, data-saver images, background color | comic reader |
| 20 | Data-saver page rendering (`data-saver` endpoint) | `core/manga_api.dart` |
| 21 | Reading progress: resume where you left off per chapter | `core/library_store.dart` |
| 22 | Auto mark-read at last page + next/prev chapter navigation with prefetch | comic reader |
| 23 | Manga language selector (EN/AR/ES/FR/PT-BR/RU/JA) | Settings → Comics |

## Cartoons (Cinemeta Animation) — new section (5)

| # | Feature | Where |
|---|---------|-------|
| 24 | Cartoons tab — trending / popular series / top movies / best-rated rows | `screens/cartoon_tab.dart` |
| 25 | Cartoon inline search (animation-filtered) | cartoon tab |
| 26 | Cartoon details + episodes reuse the cinema pipeline | `screens/cinema_details_screen.dart` |
| 27 | Cartoon playback through the same 7-server engine | cinema player |
| 28 | Genre-quality dedup: client-side Animation filter for unreliable search extras | `core/cartoon_api.dart` |

## Native player upgrades — anime + 18+ (12)

| # | Feature | Where |
|---|---------|-------|
| 29 | Double-tap seek ±10 s with side ripple | `widgets/player_gestures.dart` |
| 30 | Long-press 2× speed boost | player gestures |
| 31 | Swipe left side → screen brightness (native `setBrightness` channel) | `MainActivity.kt` + gestures |
| 32 | Swipe right side → player volume HUD | player gestures |
| 33 | Control lock (unlock button only) | player gestures |
| 34 | Picture-in-Picture (Android 8+ `enterPip`, manifest flag) | `MainActivity.kt` |
| 35 | Loop-episode toggle | player_screen |
| 36 | Sleep timer (15–90 min, auto-pause) | player_screen |
| 37 | Auto-skip intro (Settings → Player, configurable 30–120 s) | player_screen |
| 38 | Auto-play next gated behind a preference | player_screen |
| 39 | Exact resume position persisted per episode (anime) | player_screen |
| 40 | Watch history rows + progress bars for anime playback | player_screen |

## Personal library (7)

| # | Feature | Where |
|---|---------|-------|
| 41 | My List with 5 statuses (Plan / Watching / Completed / On Hold / Dropped) | `core/library_store.dart` |
| 42 | 10-point personal rating (dialog on details) | `screens/details_screen.dart` |
| 43 | Watch history page with relative timestamps | `screens/library_screen.dart` |
| 44 | Stats dashboard — episodes watched, chapters read, hours streamed, active days | library + profile |
| 45 | JSON export/import of the whole library via clipboard | Settings → Data |
| 46 | Continue Watching row on Home (red progress bars) | `screens/home_tab.dart` |
| 47 | Library screen with My List / History / Stats tabs | library screen |

## UI upgrade + polish (8)

| # | Feature | Where |
|---|---------|-------|
| 48 | Hero carousel on Home — auto-rotating top titles with backdrop art | home tab |
| 49 | Accent color picker — 5 palettes (Neo Green, Cinema Red, Ultra Violet, Deep Ocean, Sakura Pink) applied app-wide | `core/app_theme.dart` |
| 50 | AMOLED true-black theme | app_theme |
| 51 | "Surprise me" random-title shortcut | home tab |
| 52 | Shimmer skeleton loaders | `widgets/shimmer.dart` |
| 53 | Slide-fade page transitions | `widgets/transitions.dart` |
| 54 | "What's new" changelog dialog once per version | `screens/home_shell.dart` |
| 55 | Settings hub — appearance / player / comics / data / about + check-for-updates against GitHub releases | `screens/settings_screen.dart` |

## Live verification (2026-11-17)

- Cinemeta catalogs incl. `genre=Animation` — HTTP 200, plain JSON
- MangaDex — search / feed / at-home pages all 200 (throttled client)
- Embed providers verified: vidsrc.sh 200, vidfast 200, vidlink 200 (movies),
  vidsrc.cc/2embed/multiembed reachable from consumer networks (fallbacks)
- `flutter analyze` clean (Windows-conditional media_kit notes excluded —
  dead file not compiled into the APK), 73 tests green

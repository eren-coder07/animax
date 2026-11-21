# Animax (أنيماكس) v2.2.0 — Features

Arabic-first streaming app: right-to-left UI in Arabic (IBM Plex Sans
Arabic), Akwam as the home screen.

## Sections (Home category bar)
- **الرائج (Akwam)** — featured carousel (play / download / share), continue
  watching with progress bars, rows: recently added, movies, series, shows.
- **أفلام · مسلسلات · برامج** — full paginated Akwam catalogs (3-column grid).
- **أنمي** — trending, top hits, new episodes, this season; SUB / S-SUB / DUB
  servers with automatic fallback.
- **كرتون** — animated movies & series, inline search, multi-server player.
- **مانغا** — MangaDex: popular, latest, new, top rated, genre chips;
  vertical / paged / right-to-left reader; Arabic chapters first with
  English fallback.
- **+18** — age-gated section.

## Search
- Unified search across Akwam, anime and manga with poster rows.
- Recent searches (tap to repeat, clear) and popular suggestions.

## Details pages
- Player-style header, rating · year · type · genre line, info sheet.
- Pill actions: add to My List, quick share, download, view downloads.
- Sources: quality picker, play bar, tabs (episodes / for you / about).
- Episode rows with watched / "stopped at N min" marks, per-episode
  download and quick share; "download all episodes".

## Playback
- Native players (ExoPlayer on Android, mpv on Windows).
- Resume where you stopped (Akwam + anime); progress saved every 5 s,
  ≥92 % marks an episode watched.
- Gestures: double-tap ±10 s, swipe brightness / volume, long-press 2×,
  control lock; speed, quality switch, Picture-in-Picture, sleep timer,
  auto-skip intro, auto-play next.

## Downloads
- Movies and episodes save as MP4 (direct files with resume; HLS with
  AES-128 + separate audio remuxed on-device); manga chapters save as PDF.
- Download from details pages, players, comic chapters or "download all".
- Saved to `Download/Animax/{Videos,Comics}`; free-space readout, filters,
  pause / resume / retry / manage, survives app restarts.
- Downloaded videos play in-app (offline player); PDFs open in any reader.
- "Wi-Fi only" setting holds the queue on mobile data.

## Fast sharing
- Quick-share sheet: send the **video file** to WhatsApp / Telegram / any app
  (instantly when downloaded, otherwise it downloads and the share sheet
  opens automatically), share a **direct playable link** (browser / VLC),
  or share the title.
- Send button on every finished download and in the offline player.

## Library & profile
- My List with statuses, ratings, watch history with thumbnails, stats.
- Export / import library backup (JSON via clipboard).

## Look & feel
- Dark theme, cyan→green accent, accent picker, AMOLED black mode.
- Shimmer loading placeholders, fade-in images, phone-shaped window on
  Windows.

## Platforms
- Android: universal APK (32/64-bit ARM + x86_64).
- Windows: installer + portable zip (GitHub Actions).

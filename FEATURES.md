# Animax (أنيماكس) v2.4.0 — Features

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

## Accounts & community (Firebase)
- Email + password accounts — real providers only (Gmail, Outlook/Hotmail,
  Yahoo, iCloud, Proton, Zoho, GMX…), no verification mail.
- Every category (Akwam, anime, cartoons, manga, +18): view / read counts,
  likes, comments, likes on comments, delete your own comment; view-count
  badges on posters.
- User profiles: followers, following, clips; follow / unfollow.
- Splash connects to the backend and restores your account (offline mode
  when unreachable).

## Clips (مقاطع)
- ✂️ in the Akwam, anime and +18 players: pick a 3 / 5 / 10-second window
  and publish it.
- Clips tab: vertical feed, like (or double-tap), comments, repost (shows
  on your profile), views, share — sends a real MP4 cut on the phone.

## Bingo & Binge
- Watch Bingo: 3×3 goal card (watch, read, like, comment, clip, follow,
  marathon); rows / columns / diagonals count as BINGO; new rounds.
- Marathon mode: next episode after a 5 s cancellable countdown, intros
  skipped, streak counter.

## Watch together (v2.4)
- **Hot moments**: the seek bar glows where the community clipped the most;
  tap the strip or "jump to the top moment" (Akwam, anime, +18 players).
- **Timed comments**: comments pinned to a second of the episode fly across
  the video when playback reaches it; write one at the current second, list
  all of them and jump to any.
- **Spoiler shield**: clips from episodes past your progress are blurred
  until revealed; comments can be marked as spoilers.
- **Clip replies**: answer a clip with a new clip (or one of yours) — reply
  chains with "in reply to" links.
- **Manga panel clips**: crop a panel in the reader and post it to Clips;
  shared as a real PNG.
- **Weekly Bingo league**: the card resets every Monday; points (goal 1,
  bingo 3, full card 5) ranked against the people you follow and globally.

## Data & offline
- **Sound only**: audio rendition / lowest quality, keeps playing with the
  screen off (media notification).
- **Monthly mobile-data budget**: counts the app's cellular traffic; at 80 %
  switches to low-data mode, at 100 % asks before streaming and holds
  downloads for Wi-Fi.
- **Phone-to-phone without internet**: send any download to a nearby phone
  over Google Nearby Connections (Bluetooth + Wi-Fi Direct), confirmed with
  a 4-digit code; received files land in Downloads.

## Slow internet
- Automatic low-data mode on slow connections: small covers, lowest video
  quality first, data-saver manga pages, larger image cache.

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
- Android: 32-bit ARM APK (armeabi-v7a) sent to Telegram; universal build available.
- Windows: installer + portable zip (GitHub Actions).

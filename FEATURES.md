# Animax (أنيماكس) v2.8.0 — Features

Arabic-first streaming app: right-to-left UI in Arabic (IBM Plex Sans
Arabic), Akwam as the home screen.

## Sections (Home category bar)
- v2.7: «الأكثر مشاهدة على أنيماكس» — community ranking row (Akwam, anime,
  manga; shown once 3+ titles have views).
- **الرائج (Akwam)** — featured carousel (play / download / share), continue
  watching with progress bars, rows: recently added, movies, series, shows.
- **أفلام · مسلسلات · برامج** — full paginated Akwam catalogs (3-column grid).
- **أنمي** — trending, top hits, new episodes, this season; SUB / S-SUB / DUB
  servers with automatic fallback.
- **كرتون** — animated movies & series, inline search, multi-server player.
- **مانغا** — v2.6: hands-free reading (auto page turn, 0.5×–2×). MangaDex: popular, latest, new, top rated, genre chips;
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
- v2.7: ⋯ on clips — not interested / report / block / delete own; long-press
  comments to report or block; block / unblock / report from profiles;
  Settings → blocked users. Blocked people's clips, comments, timed comments
  and notices are hidden. «اكتشف صنّاع المقاطع» (top creators, one-tap follow).
- v2.6: «الرائج» feed (engagement with time decay).
- v2.5: optional captions (clips and manga panels); "Following" feed next to
  "Everyone"; activity inbox (likes, comments, replies, reposts, comment
  likes, new followers) with an unread badge; editable name + bio.
- ✂️ in the Akwam, anime and +18 players: pick a 3 / 5 / 10-second window
  and publish it.
- Clips tab: vertical feed, like (or double-tap), comments, repost (shows
  on your profile), views, share — sends a real MP4 cut on the phone.

## Bingo & Binge
- Watch Bingo: 3×3 goal card (watch, read, like, comment, clip, follow,
  marathon); rows / columns / diagonals count as BINGO; new rounds.
- Marathon mode: next episode after a 5 s cancellable countdown, intros
  skipped, streak counter.

## Animax technology (v2.8)
- **Intro detection without decoding**: compares two episodes' MP4 indexes
  only (~50 KB): the keyframe rhythm of an identical opening matches and
  diverges where the episode starts; 1-second frame-size sums confirm it
  (real intros score ~1.0 vs ~0.15–0.35 noise). Verified on Akwam
  «احتمال حب» eps 1–3, 41/42, 71 (credits end frame-checked at 77.96 s);
  no false intro on «ما زلت في 17» or on special episodes. «تخطي المقدمة»
  button + optional auto-skip; results cached per episode.
- **Adaptive quality for plain MP4**: Akwam's 360p/480p/720p files share
  86–100 % of keyframes; fast-start windows end on a keyframe shared by all
  qualities, so the next window can come from another quality with zero gap
  (measured: gap 0.000 s, first frame identical to the 720p original).
  Decisions from measured line speed (media + index transfers) and stalls.
- **Scene search**: a screenshot (downscaled to ~10 KB) → trace.moe frame
  index → anime, episode and second → found in our catalog → the player
  opens at that exact second. Low-confidence matches are dropped or marked.

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
- **Fast start for Akwam & clips**: a regular MP4 must download its whole
  index (~4 MB for a movie, ~45 s at 100 KB/s) before the first frame. The
  app now fetches only the index slices for the part being watched, writes a
  small standalone MP4 index and serves the window from a local server
  (media bytes stream straight from the CDN). Measured at 100 KB/s + 150 ms
  latency on a real Akwam movie: start 43 s → 3 s, resume at 30:00 44 s →
  6 s, a 10 s clip 48 s → 6 s; frames identical to the original; windows
  chain seamlessly.
- Real throughput measurement (the OS link speed is often wrong) picks the
  quality; repeated stalls step down to a lower quality automatically.
- Fix: Akwam's 480p/360p choices actually play those files (every watch page
  lists all qualities; the first — 720p — was always taken before).
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
- Akwam player: sleep timer (incl. end of episode) and picture-in-picture.
- Resume where you stopped (Akwam + anime); progress saved every 5 s,
  ≥92 % marks an episode watched.
- Gestures: double-tap ±10 s, swipe brightness / volume, long-press 2×,
  control lock; speed, quality switch, Picture-in-Picture, sleep timer,
  auto-skip intro, auto-play next.

## Downloads
- v2.7: smart downloads — past 80 % of an Akwam episode on Wi-Fi, the next
  episode is queued (same quality) for offline viewing (Settings switch).
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
- v2.6: cloud sync — My List, resume points, watched marks and history are
  kept in your account (`sync/{uid}`, private) and merged on every phone you
  sign in on (newest change per item wins; removals sync too).
- v2.6: new-episode alerts for Akwam series in My List (checked at launch and
  every 6 h) at the top of Notifications.
- Fix: watch progress and history were lost on every app restart (saved as a
  list, loaded as a map); each section now loads independently.
- My List with statuses, ratings, watch history with thumbnails, stats.
- Export / import library backup (JSON via clipboard).

## Look & feel
- Dark theme, cyan→green accent, accent picker, AMOLED black mode.
- Shimmer loading placeholders, fade-in images, phone-shaped window on
  Windows.

## Platforms
- Android: 32-bit ARM APK (armeabi-v7a) sent to Telegram; universal build available.
- Windows: installer + portable zip (GitHub Actions).

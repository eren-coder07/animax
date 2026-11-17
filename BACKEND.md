# Animax ↔ Aniwaves Backend — Integration Guide (v1.9.1)

The app is wired to the **real API captured in your HAR file**
(`upload/myapi`, traffic from `https://aniwaves.ru`) **plus the player and
schedule endpoints discovered from the site's own JS**. No configuration is
needed — the base URL is built in, and every endpoint below was
**verified live** at build time.

---

## 1. What the app does with your API

| App surface | Backend call | Status |
|---|---|---|
| Home — Top Hits + New Releases | `/genre/{action,adventure,comedy,fantasy,romance,sci-fi}` + `/ajax/v2/trending?mov_id={id}` | ✅ live-verified |
| Details — title, synopsis, poster, score, genres | `GET /watch/{slug}` (HTML scrape: `h1`, `.film-description`, `og:image`, `/genre/` links) | ✅ live-verified |
| Details — Episodes row | `GET /ajax/episode/list/{id}?vrf=` | ✅ live-verified |
| Details — More Like This | `GET /ajax/v2/recommendations?page=1&mov_id={id}` (empty on your side today — falls back to catalog) | ✅ wired |
| Player — SUB / S-SUB / DUB server chips | `GET /ajax/server/list?servers={id}&eps={ep}` | ✅ live-verified |
| **Player — in-app playback** | **`GET /ajax/sources?id={linkId}&asi=0&autoPlay=1` → `result.url` embed page opened in an in-app WebView** | ✅ live-verified |
| Player — view counter | `GET /ajax/anime/views/{id}` (fire-and-forget, like the site) | ✅ wired |
| Calendar tab | `GET /ajax/schedule/date?date=YYYY-MM-DD` — the site's own airing schedule, 3 days back → 7 ahead (falls back to episode `data-aired`) | ✅ live-verified |
| Notifications | episodes released in the last 3 days (from the schedule) | ✅ |
| Profile — session state | `GET /ajax/user/panel` (polled silently) | ✅ live-verified |

## 2. In-app playback — how it works

1. The player fetches `/ajax/server/list` for the episode; `data-link-id`
   tokens stay **opaque** (never decoded).
2. The chosen server's `link-id` is sent to `/ajax/sources?id=…` →
   `{"status":200,"result":{"url":"https://play.echovideo.ru/embed-20/…",
   "server":14,"skip_data":{...}}}`.
3. `result.url` — the **exact same embed page the website loads in its
   iframe** — is opened inside an in-app WebView (`webview_flutter`) with a
   browser User-Agent and `Referer: <base>`. Navigation outside the embed
   host is blocked; Prev/Next episode buttons re-resolve automatically.
4. If a server fails, the user taps another server chip or uses
   "Open in browser" (native `openUrl` channel) as a last resort.

## 3. Removed (not backed by this API)

Per product decision, the app no longer ships features the backend cannot
serve. Deleted in v1.3.0:

* **Sign-in / sign-up** — site auth is cookie+CSRF, not a JSON API.
* **My List / favorites tab** — favorites live behind the site session.
* **Downloads tab** — no download API.
* **Premium paywall + Add-card** — no payment API.
* **Edit profile / security / language picker** — no account API.
* **Fake comments on details** — the comment widget is a third-party embed.

The shell is now **Home / Calendar / Profile**.

## 4. The API contract as implemented

All AJAX endpoints return **JSON envelopes whose payloads are HTML
fragments**. The parsers live in `lib/core/api_html.dart` and are covered by
the tests in `test/`, which run against the **exact fragments captured
in your HAR** plus the live shapes above.

```
GET /ajax/v2/trending?mov_id={id}
  → {"status":200,"html":"<a class=\"item\" href=\"/watch/slug-81553\">…"}
    card fields: href → slug+id · img → poster · .name → title
                 .dot.score → rating · .dot → type, year
    ⚠ mov_id is REQUIRED — without it the endpoint returns an empty body
      (verified live). The app sources an id from a genre page on first run.

GET /ajax/episode/list/{id}?vrf=
  → {"status":200,"result":"<li data-num=\"1\" data-aired=\"2026-10-07T00:00:00+09:00\"
      data-duration=\"1420\" data-sub=\"1\" data-dub=\"1\"><span class=\"d-title\">…</span>"}

GET /ajax/server/list?servers={id}&eps={ep}
  → {"status":200,"result":"<div class=\"type\" data-type=\"sub|ssub|dub\">
      <li data-sv-id=\"14\" data-link-id=\"BASE64…\">DatSaV</li>…"}
    data-link-id is passed through OPAQUELY — the app never decodes it.

GET /ajax/sources?id={linkId}&asi=0&autoPlay=1
  → {"status":200,"result":{"url":"https://play.echovideo.ru/embed-20/…",
      "server":14,"skip_data":{"intro":[0,0],"outro":[0,0]},"sources":[],"tracks":[]}}
    result.url is opened in the in-app WebView (Referer = base URL).

GET /ajax/schedule/date?date=YYYY-MM-DD
  → {"result":"<a class=\"item\" href=\"/watch/slug-82794/ep-4\">
      <div class=\"time\" data-tip=\"82794\">12:26 PM</div>…
      <div class=\"title d-title\" data-jp=\"…\">English title</div></a>"}

GET /ajax/user/panel
  → {"status":200,"result":{"html":"…","user":{"id":0,"settings":[],"folders":[]}}}

GET /ajax/anime/views/{id}   → {"status":true}   (fire-and-forget)

GET /ajax/v2/recommendations?page=1&mov_id={id}
  → {"status":false,…} today; parsed as cards automatically when enabled.

GET /watch/{slug}            → full HTML page; details scraped from it.
GET /genre/{slug}, /search?keyword={q} → same item-card markup, parsed.
```

## 5. Request fidelity

Requests mirror the site's own frontend so AJAX endpoints answer normally:

- mobile Chrome `User-Agent` (same UA inside the playback WebView)
- `Accept: application/json, text/javascript, */*; q=0.01` + `X-Requested-With: XMLHttpRequest` on AJAX calls
- same-origin `Referer`; the WebView loads the embed with `Referer: <base>`

A live smoke test from the build machine confirmed **all endpoints answer
200 with full payloads** (no Cloudflare block for plain HTTP clients).

## 6. Configuration

There is **no in-app connection UI** — defaults are baked in so end users
never see connection diagnostics or debug screens:

```
Anime backend base URL      https://aniwaves.ru   (built in)
Akwam section base URL      https://akwam.ss      (built in)
```

Bake a different anime base at build time:

```bash
flutter build apk --release --dart-define=ANIMAX_API_BASE=https://your-mirror.tld
```

If the backend is unreachable (offline, blocked, DNS failure), the anime
sections show a neutral "Content unavailable" card with a retry button —
never a raw error dump. The Akwam section reports its own friendly errors.

## 7. Project map (integration parts)

```
lib/core/api_config.dart        base URL + endpoint paths (persisted, no UI)
lib/core/api_service.dart       HTTP layer: AJAX endpoints + watch/genre/search scraping
lib/core/api_html.dart          HTML-fragment → model parsers (cards, episodes,
                                servers, schedule rows, /ajax/sources envelope)
lib/core/api_mapper.dart        tolerant JSON→model mappers (kept for JSON backends)
lib/core/app_state.dart         repository: bootstrap, catalog, live schedule
                                calendar, notices, episode/recommendation caches
lib/core/akwam_api.dart         Akwam section scraper: catalogs, search, details,
                                episodes, quality tabs, direct-MP4 resolver
lib/screens/player_screen.dart  in-app WebView playback (server chips + prev/next)
lib/screens/akwam_*.dart        Akwam tab, details, search and native player
android/.../MainActivity.kt     openUrl / setKeepScreenOn / PiP channels
test/                           parser tests against captured traffic
```

## 8. Known limitations

- **Playback chrome** — the embed renders the website's own player UI. If
  you later expose a JSON endpoint returning direct `file.m3u8`/`file.mp4`
  URLs, the app can switch to a native player package for a fully custom UI.
- **Recommendations** — your backend currently returns `status:false`;
  the app auto-parses the HTML the day it is enabled.
- **Search** — scrapes `/search?keyword=`; if that route changes, only this
  one method needs updating.

## 9. Akwam section (`https://akwam.ss`)

The **Akwam** tab (v1.9.1) streams Arabic movies, series and shows from
akwam.ss. All requests are plain GETs through Cronet; the contract below
was **verified live on 2026-11-17**.

```
Catalogs   GET /recent?page=N  /movies?page=N  /series?page=N  /shows?page=N
           → poster cards (div.entry-box): a.entry-title (title + href),
             img[data-src] (poster), span.label.rating, span.label.quality,
             span.badge (year + Arabic genres). Pagination via ?page=N.

Search     GET /search?q={query}&page=N → same card markup.

Item page  GET /movie/{id}/{slug} | /series/{id}/{slug}
           → og:title / og:image / og:description + the "قصة …" story widget
             (longer synopsis) + for series the #series-episodes grid with
             /episode/{id}/{slug}/الحلقة-N links and p.entry-date air dates.

Movie /    quality tabs: ul.header-tabs li a → #tab-N labels
episode      div.tab-content.quality#tab-N → /watch/{fileId}/{itemId}/{slug}
page         watch links (+ sibling download links carrying file sizes).

Watch page GET /watch/{fileId}/…
           → HTML contains the direct https://…/*.mp4 stream URL
             (range requests supported — HTTP 206), played natively through
             video_player with Referer: https://akwam.ss/. No WebView.
```

Playback flow: catalog → details → (series: episode page → quality tabs)
→ `/watch/{fileId}` page → direct MP4 → ExoPlayer. Quality switching,
prev/next episode and auto-advance live in `akwam_player_screen.dart`.

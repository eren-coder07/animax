# Firebase setup for Animax

Animax talks to the Firebase project `cimacloud-22762` over Firebase's REST
APIs (Auth, Realtime Database). All Animax data lives under `/animax`.

## 1. Authentication
Console → Authentication → Sign-in method → **Email/Password: Enabled**
(already enabled — verified). Email verification is not used; the app only
accepts addresses at real providers (Gmail, Outlook/Hotmail, Yahoo, iCloud,
Proton, Zoho, GMX, …).

## 2. Realtime Database rules (important)
Your database is currently readable **and writable by anyone**, including
your `goldenace` data. Paste `database.rules.json` into
Console → Realtime Database → Rules → Publish.

What the rules do:
- Everything outside `/animax` and `/goldenace` is locked.
- `/goldenace` keeps today's open access so your other app keeps working —
  lock it down separately for that app.
- `/animax` is public to read (it is a social feed) but:
  - only the signed-in owner can write their profile, likes, follows,
    reposts, Bingo/Binge progress, comments and clips;
  - every counter (likes, comments, followers, reposts) can only move by
    exactly +1 / -1 per write; view counts can only go up by 1;
  - clips must be ≤ 10 seconds; text fields have length limits;
  - `items` is indexed by `views` (poster view badges).

## 3. Storage
Uploads to the default bucket return HTTP 402 on the Spark plan, so clips
are stored as references (source + start/end) and cut on-device when
shared. `storage.rules` is ready for when you move to Blaze.

## 4. Clean-up
A test account `animax.probe.<number>@gmail.com` (UID starting `rYjp4X`)
was left from the first connectivity check — delete it in
Console → Authentication → Users.

## v2.4 update — publish the rules again

v2.4 adds `moments`, `tcomments`, `clipReplies` and `league` (plus an index
on `league/{week}/score`). Paste the new `database.rules.json` into
Console → Realtime Database → Rules → **Publish** again. Until then the app
still works (it sorts on the device when an index is missing).

## v2.5 update — publish the rules again

The activity inbox (`inbox/{uid}`) must be readable only by its owner, so the
blanket `.read` on `/animax` became per-node public reads plus a private
`inbox` / `inboxSeen`. Paste the new `database.rules.json` and **Publish**.

## v2.6 update

Adds the private `sync/{uid}` node (account library sync). Publish the new
`database.rules.json` again.

## v2.7 update

Adds private `blocked/{uid}`, write-only `reports/{target}/{uid}` (read them
in the Firebase console → Realtime Database → animax/reports) and an index
on `users/followers`. Publish the new `database.rules.json`.

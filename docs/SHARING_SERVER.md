# Share server for screenshots and recordings

RyzenStatus can share screenshots and screen recordings as expiring links. Both
features upload to a **self-hosted HTTPS server** that implements the small `v1`
API below. There is deliberately **no default server and no third-party host**:
a shipped build must never upload a capture to a server we do not control, so
sharing stays disabled unless a developer configures their own endpoint.

## Activating sharing

Sharing is gated by three conditions, all of which must hold:

1. **Developer build.** The endpoint is only honored when the running bundle
   identifier is `com.ryzenstatus.utils.dev`. The official build
   (`com.ryzenstatus.utils`) never reads it. Produce the dev variant with:

   ```sh
   ./build.sh --dev
   ```

   The dev app installs and runs next to the official one with its own
   permissions, preferences and login item.

2. **Compiled with `DEBUG` defined.** The endpoint override is read only inside
   `#if DEBUG` (`ScreenshotShareService.endpoint` / `RecordingShareService.endpoint`).
   ⚠️ **Current gap:** `build.sh` compiles with `swiftc -O` and never passes
   `-DDEBUG` (build.sh line 192), so **no artifact produced by `build.sh`
   today satisfies this gate** — the override is compiled out in every build.
   An Xcode Debug configuration (which defines `DEBUG`) works. Until `--dev`
   also compiles with `-DDEBUG`, sharing cannot be activated from a `build.sh`
   build.

3. **Set the endpoint and enable the toggle.**

   ```sh
   defaults write com.ryzenstatus.utils.dev screenshotSharingDeveloperEndpoint "https://share.example.com"
   ```

   The endpoint is sanitized and must be:
   - `https` scheme (http is rejected),
   - a host, with **no** user, password, query or fragment,
   - an empty path (or exactly `/`). `https://share.example.com` is valid;
     `https://share.example.com/upload` is not.

   Then, in the app, turn the share toggle on in the screenshot / recorder
   settings. Note: the toggle defaults to on in the UI but the service checks
   `UserDefaults` directly, so if the key was never persisted, flip the switch
   off and on once. The share controls stay disabled until the endpoint is
   configured (`isSharingConfigured`).

## API contract (v1)

All endpoints are under the configured endpoint. Uploads use `URLSession`
with cookies disabled, no caching and short timeouts (screenshots: 75 s request
/ 90 s resource; recordings: 180 s / 300 s).

### Upload a screenshot

```
POST {endpoint}/v1/screenshots?expiresIn=3600|21600|86400
```

- `Content-Type: image/png` · `Accept: application/json` · `Cache-Control: no-store`
- Body: raw PNG, max 25 MiB, must start with the PNG magic bytes.
- Success: `201`, JSON body (≤ 64 KiB):

  ```json
  { "id": "…", "viewPath": "/s/{id}", "expiresAt": "2026-08-10T00:00:00Z", "deleteToken": "…" }
  ```

- `429`, `503`, `507` are treated as transient (the app reports “unavailable”);
  any other non-201 status is a rejection.

### Upload a recording

```
POST {endpoint}/v1/recordings?expiresIn=3600|21600
```

- `Content-Type: video/mp4` · `Accept: application/json` · `Cache-Control: no-store`
  · `Content-Length`
- Body: MP4 file, max 96 MiB (the app targets 90 MiB and re-encodes to fit:
  ≤ 30 fps, longest edge ≤ 1920 px, audio 128 kbps, adaptive video bitrate, and
  it may downscale; uploads over 96 MiB are retried at a lower bitrate).
- Success: `201`, same JSON shape as above.

### Revoke a link

```
DELETE {endpoint}/v1/screenshots/{id}
DELETE {endpoint}/v1/recordings/{id}
```

- `Authorization: Bearer {deleteToken}` · `Accept: application/json`
- Success: `204`; `404` is also accepted (already gone).

### Response payload rules (enforced by the client)

| Field | Rule |
|---|---|
| `id` | 32 chars, `[A-Za-z0-9_-]` |
| `deleteToken` | 43 chars, `[A-Za-z0-9_-]` |
| `viewPath` | must equal `/s/{id}` |
| `expiresAt` | ISO-8601 (with or without fractional seconds); in the future and ≤ 24 h + 5 min (screenshots) / 6 h + 5 min (recordings) after upload |

The `expiresIn` query value must match one of the enum cases above
(1 h / 6 h for recordings; 1 h / 6 h / 24 h for screenshots).

### Public view page

The link the app copies is `{endpoint}/s/{id}`. Your server serves a page for
that path, honoring the expiry.

## Client behavior worth mirroring

- Records persist locally (Application Support / `TemporaryScreenshotLinks` /
  `TemporaryRecordingLinks`, `records.json`, `0700`/`0600`). The app preflights
  local storage **before** uploading so a successful upload never disappears
  from the app if local persistence is unavailable; on that race it revokes the
  remote link when possible.
- The delete token is stored only locally and sent only on revoke.
- Expired links are purged locally and the UI only shows records for the
  currently configured host.

## Minimal server outline

A reference implementation (any language) needs: object/file storage keyed by
the generated id, a metadata store (id, expiry, delete token), and four routes:

1. `POST /v1/screenshots|recordings?expiresIn=` → store body, return
   `201` with `{id, viewPath, expiresAt, deleteToken}`.
2. `DELETE /v1/screenshots|recordings/{id}` with `Bearer` token → delete,
   `204` (or `404`).
3. `GET /s/{id}` → the public page, `410`/redirect after expiry.

Generate ids with `crypto/rand`-grade entropy (32 chars) and tokens with
43 chars so neither is guessable, and enforce the size limits above.

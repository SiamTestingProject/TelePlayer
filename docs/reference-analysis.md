# Telegram-Stremio Reference Analysis

Reference: https://github.com/weebzone/Telegram-Stremio

## Technically Relevant Findings

- Telegram communication: the reference server uses PyroFork/Pyrogram clients, configured with Telegram API ID/hash and bot tokens. It can run multiple bot clients for load distribution and an optional user session for global search.
- Authentication: server credentials live in environment/config values, with optional user session strings for userbot access. Newer README material also describes in-app Telegram login on the server settings page. This Flutter app instead asks for API ID/hash at runtime and stores them in platform secure storage.
- Media discovery: the reference scans configured Telegram channels and reads forwarded messages. TelePlayer now keeps only Telegram audio and audio-like document messages, using their embedded title, performer, duration, and album artwork metadata.
- Stream creation: the reference decodes a stream ID, resolves the Telegram chat/message, obtains file metadata, parses HTTP Range headers, and returns `206 Partial Content` with `Accept-Ranges: bytes`.
- Partial download behavior: the FastAPI streamer fetches chunks from Telegram through a `ByteStreamer` and prefetches adjacent chunks. This Flutter app applies the same essential pattern through a localhost HTTP server consumed by `just_audio`.
- Large files: the reference never requires loading an entire file into memory. It streams byte ranges and tracks active streams. This app serves smaller sequential TDLib ranges so native playback can start quickly without loading an entire file.
- Audio-only scope: video and split-video messages are deliberately ignored so the Library and playback queue contain songs only.
- Metadata: the reference enriches indexed media with TMDb/Cinemeta metadata. The Flutter implementation keeps local filename, MIME type, size, duration, and thumbnail hooks, while leaving external metadata enrichment out of scope for the first client app.
- Thumbnails: the reference retrieves Telegram thumbnails from media messages and caches them. This app exposes a thumbnail loading path through TDLib and maps missing thumbnails to a non-fatal friendly state.
- Sessions: the reference stores bot/user sessions on the server side. This app delegates local session persistence to TDLib's encrypted database and stores only user-provided app config in secure storage.
- Desktop runtime: Windows uses the same TDLib workflow, but TDJSON is resolved from a configured DLL path or from `tdjson.dll` beside the executable. Release packaging downloads and bundles the Windows TDLib runtime automatically, while a repository secret can still inject a custom DLL.
- Error handling: the reference logs Telegram failures and tracks client failures/rate limits. This app centralizes errors in `AppException` and maps network, auth, deleted message/media, private channel, invalid media, codec, playback, API, rate-limit, and missing-thumbnail failures to user-friendly UI copy.

## Deliberately Not Ported

- Stremio addon manifests, token subscriptions, admin panels, TMDb catalog management, announcements, analytics dashboards, MongoDB storage, and paid access flows.
- Server deployment helpers for Heroku, VPS, Hugging Face, and bot-based multi-user sharing.

## Essential Workflow Used Here

1. Authenticate a Telegram user session through TDLib.
2. Read configured channel histories.
3. Keep playable audio and audio-compatible document messages only.
4. Preserve Telegram album thumbnails and embedded mini artwork for the Library.
5. Register the selected item with a local HTTP streaming server.
6. Serve player range requests by asking TDLib for the matching byte range.
7. Surface failures through friendly app states instead of raw exceptions.

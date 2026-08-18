# IOS & IPADOS DIRECTORY RULES (`ios/GEMINI.md`)

## 1. ARCHITECTURAL PATTERNS
- **Design Pattern**: MVVM with Observable / Async-Await (Swift 6).
- **Decoupling**: Keep Player UI cleanly separated from `MediaPlayerProtocol` and low-level playback engine implementations (`AVPlayer`, `VLCKit`/`FFmpeg`).
- **File System Access**: Use `Security-Scoped Resource Bookmarks` when accessing files outside the app sandbox (e.g. external USB/iCloud Drive). Always release access using `stopAccessingSecurityScopedResource()`.

## 2. PLAYBACK & MEDIA RULES
- **Audio Session**: Configure `AVAudioSession` category to `.playback` and handle interruption notifications (`AVAudioSession.interruptionNotification`) and route change notifications (`AVAudioSession.routeChangeNotification`).
- **Now Playing & Remote Commands**: Maintain accurate metadata in `MPNowPlayingInfoCenter` and respond to `MPRemoteCommandCenter` events.
- **Picture-in-Picture (PiP)**: Integrate `AVPictureInPictureController` with graceful fallback when background video is unsupported.
- **Chromecast Streaming Bridge**: Run local HTTP server (`FlyingFox` or `Criollo`) on a background queue with HTTP Range support (`206 Partial Content`) for Google Cast.

## 3. SWIFT CODE CONVENTIONS
- Write clean, type-safe Swift with strict concurrency checks enabled.
- Avoid force unwrapping (`!`) in production paths; use `guard let` or `if let`.
- Add `// [Intent]` comments to explain non-obvious stream buffer, codec, or threading logic.

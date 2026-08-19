# PROJECT CONSTITUTION & CODING STANDARDS

## 1. PROJECT IDENTITY & TECH STACK
- **Project Goal**: High-performance personal media player app for iOS & iPadOS supporting local audio/video, AirPlay 2, Chromecast, in-app file/stream browsing, and test server integration.
- **Client Stack**: Swift 6, SwiftUI, AVKit / AVFoundation, GoogleCast iOS SDK, SQLite (GRDB.swift / SwiftData), WKWebView.
- **Target OS & Test Devices**: iOS 18.0+ / iPadOS 18.0+ (Universal). Verified on iPhone 11 (iOS 18.7.7) & iPad Air 5 (iPadOS 18.7.8, Apple M1).
- **Test Server Stack**: Linux (Ubuntu/Debian), Docker & Docker Compose, Nginx (HTTP Range streaming), WebDAV, Samba (SMB), Tailscale & Local LAN.

## 2. RULE HIERARCHY & CONSTRAINTS
1. **Hierarchy**: Global Constitution > Project Rules (`GEMINI.md`) > Directory Rules (`*/GEMINI.md`) > Instructions.
2. **Strict English**: All rule files and code comments must be written in English.
3. **Intent-Driven**: Add `// [Intent]` to non-obvious architecture, concurrency, or stream-handling logic.
4. **Token Economy**: Keep rule files focused and under 100 lines.
5. **Conflict Resolution**: If conflicts arise between rule files, evaluate based on project alignment, architectural consistency, and specificity—prioritizing the rule with the most concrete and well-justified rationale.

## 3. CORE ARCHITECTURAL PRINCIPLES
- **Decoupled Playback Engine**: UI components interact only via `MediaPlayerProtocol`, never directly with `AVPlayer` or external codec engines.
- **Background & Lifecycle Safety**: Audio sessions (`AVAudioSession`) must properly handle interruptions (calls, Siri), audio route changes (AirPods disconnect), and lock screen sync (`MPNowPlayingInfoCenter`).
- **Memory & Resource Discipline**: Always use `[weak self]` in closures, avoid retain cycles in player observers, and cancel async `Task` instances upon view dismissal.
- **Chromecast Streaming Bridge**: Chromecast cannot access sandbox files directly. Stream local files through an embedded, lightweight local HTTP server supporting HTTP Range 206 responses.

## 4. VERIFICATION & PRE-COMPLETION GATES
- Verify all changes before asserting completion. Run unit tests for metadata parsing, stream chunking, and database queries.
- Before committing, pass Swift 6 stability preflight checks against `docs/case-studies/KA_SWIFT_STABILITY.md` (concurrency isolation, enum exhaustiveness, and DTO symmetry).
- Before committing significant architecture changes, update relevant documents under `docs/`.

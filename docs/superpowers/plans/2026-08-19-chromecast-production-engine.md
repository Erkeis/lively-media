# Pure-Swift Production Chromecast Engine & Real-World iPad Test Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Implement a 100% production-ready, pure-Swift Chromecast engine supporting real local Wi-Fi mDNS discovery (`_googlecast._tcp`), Cast V2 socket control (TLS :8009), and an embedded HTTP Range 206 streaming bridge that runs natively on iPad Air 5 (Swift Playgrounds) and in the modular `ios/` package without breaking CI builds.

**Architecture:** 
1. `CastEngine` module: Pure-Swift `ChromecastService` utilizing Apple's `Network.framework` (`NWBrowser` for mDNS and `NWConnection` for TLS port 8009 Cast V2 JSON framing).
2. Embedded HTTP Range 206 Streaming Server: Serves local sandbox video/audio byte chunks (`Range: bytes=start-end`) on `:8080` to Chromecast receivers.
3. Standalone iPad App (`LivelyMedia.swiftpm/App.swift`): Contains full self-contained `NWListener` Range Server + `NWBrowser` Cast Engine with zero external binary dependencies.
4. Protocol-driven test isolation: Guarantees deterministic, fast execution in GitHub Actions CI (`macos-14` runner) without network timeouts.

**Tech Stack:** Swift 6, SwiftUI, Network.framework (`NWBrowser`, `NWConnection`, `NWListener`), AVFoundation, FlyingFox (in `ios/` package), XCTest.

---

### Task 1: Architecture & Case Study Documentation Update

**Files:**
- Modify: `docs/ARCHITECTURE.md`
- Modify: `docs/case-studies/MAJOR_CASES.md`
- Modify: `docs/NON_MAC_TEST_GUIDE.md`

- [ ] **Step 1: Update ARCHITECTURE.md with Pure-Swift Cast V2 & Range Server specification**
- [ ] **Step 2: Add Case M-07 to MAJOR_CASES.md detailing binary SDK constraints and pure-Swift solution**
- [ ] **Step 3: Update NON_MAC_TEST_GUIDE.md with real Chromecast live test checklist**
- [ ] **Step 4: Commit documentation changes**

```bash
git add docs/ARCHITECTURE.md docs/case-studies/MAJOR_CASES.md docs/NON_MAC_TEST_GUIDE.md
git commit -m "docs: document pure-Swift Cast V2 architecture and real-world testing checklist"
```

---

### Task 2: Pure-Swift Cast V2 Protocol Framing & Message Encoders

**Files:**
- Create: `ios/Sources/CastEngine/CastV2Protocol.swift`
- Modify: `ios/Sources/CastEngine/CastTarget.swift`
- Test: `ios/Tests/CastEngineTests/CastEngineTests.swift`

- [x] **Step 1: Write unit tests for Cast V2 payload serialization and packet framing**
- [x] **Step 2: Implement CastV2Protocol message structs (`CastMessage`, `MediaLoadCommand`, `MediaControlCommand`)**
- [x] **Step 3: Run tests to verify Cast V2 message serialization**
- [x] **Step 4: Commit**

```bash
git add ios/Sources/CastEngine/CastV2Protocol.swift ios/Sources/CastEngine/CastTarget.swift ios/Tests/CastEngineTests/CastEngineTests.swift
git commit -m "feat(CastEngine): add Cast V2 message framing and payload models"
```

---

### Task 3: Real mDNS Discovery & TLS Socket Client in CastEngine

**Files:**
- Modify: `ios/Sources/CastEngine/ChromecastService.swift`
- Modify: `ios/Sources/CastEngine/CastCoordinator.swift`
- Test: `ios/Tests/CastEngineTests/CastEngineTests.swift`

- [ ] **Step 1: Write unit tests for ChromecastService with mock and network discovery delegates**
- [ ] **Step 2: Implement NWBrowser mDNS scanner for `_googlecast._tcp` and NWConnection TLS :8009 client**
- [ ] **Step 3: Connect CastCoordinator with active session handling and error state propagation**
- [ ] **Step 4: Verify test suite execution**
- [ ] **Step 5: Commit**

```bash
git add ios/Sources/CastEngine/ChromecastService.swift ios/Sources/CastEngine/CastCoordinator.swift ios/Tests/CastEngineTests/CastEngineTests.swift
git commit -m "feat(CastEngine): implement real mDNS discovery and TLS socket client"
```

---

### Task 4: Embedded Pure-Swift HTTP 206 Streaming Server in LivelyMedia.swiftpm

**Files:**
- Modify: `LivelyMedia.swiftpm/App.swift`

- [ ] **Step 1: Implement embedded NWListener HTTP 206 Range Streaming Server in App.swift**
- [ ] **Step 2: Connect real-time NWBrowser discovery and Cast V2 control sheet in App.swift UI**
- [ ] **Step 3: Verify Swift Playgrounds syntax compatibility and standalone execution**
- [ ] **Step 4: Commit**

```bash
git add LivelyMedia.swiftpm/App.swift
git commit -m "feat(Playgrounds): embed native NWListener HTTP 206 range server and Cast V2 discovery in standalone app"
```

---

### Task 5: End-to-End Test Suite Verification & CI Preflight

**Files:**
- Test: `ios/Tests/CastEngineTests/CastEngineTests.swift`
- Test: `ios/Tests/TransferServerTests/TransferServerTests.swift`
- Test: `ios/Tests/PlayerUITests/PlayerUITests.swift`

- [ ] **Step 1: Run complete unit test suite across all 11 modules**
- [ ] **Step 2: Verify zero concurrency warnings under Swift 6 strict concurrency**
- [ ] **Step 3: Verify GitHub Actions CI workflow script consistency**
- [ ] **Step 4: Commit final verification adjustments**

```bash
git add .
git commit -m "test(CastEngine): complete end-to-end Chromecast test coverage and verification"
```

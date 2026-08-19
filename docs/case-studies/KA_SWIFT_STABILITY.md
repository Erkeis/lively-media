---
id: KA_SWIFT_STABILITY
title: Swift Stability & Strict Concurrency Preflight Signatures
version: 1.0.0
trigger_keywords:
  - swift6
  - concurrency
  - sendable
  - continuation
  - nwendpoint
  - enum_switch
  - actor_isolation
  - deinit_task
  - test_closures
tags:
  - swift
  - verification
  - concurrency
  - stability
  - preflight
---

# Knowledge Asset: Swift Stability & Strict Concurrency Signatures

<!-- [BLOCK_MAP]
- SIG_SWIFT6_CONCURRENCY: Concurrency & Continuation Closure Mutable Capture Rules
- SIG_EXHAUSTIVE_ENUMS: Non-Frozen System Enum Exhaustive Matching
- SIG_MODEL_SYMMETRY: Inter-Package DTO Symmetry & Computed Accessors
- SIG_MEMORY_ARC_DEINIT: Deinit Task Dispatch & ARC Weak Reference Safety
- SIG_LINKER_SYMBOLS: Modular Library vs Test Runner _main Linker Collisions
- SIG_PLATFORM_RUNNER: Cross-Platform Runner & Tools Version Portability
- SIG_TEST_CLOSURE_SAFETY: XCTest Asynchronous Closure State Synchronization
- AUDIT_CHECKLIST: Pre-Commit Gate Audit Checklist for Verification Agents
[END_BLOCK_MAP] -->

---

<!-- [START: SIG_SWIFT6_CONCURRENCY] -->
## 1. Concurrency & Continuation Closure Safety (SIG-01)

### Context & Symptom
In Swift 6 Complete Concurrency mode (`-strict-concurrency=complete`), capturing and mutating local variables across `@Sendable` or asynchronous closures is diagnosed as an unisolated data race:
`error: mutation of captured var in concurrently-executing code`.

### Rule & Pattern
- **Never** mutate a standard local `var` inside escaping handler closures or `withCheckedThrowingContinuation`.
- **Always** mark shared continuation flags as `nonisolated(unsafe)` and guard state transitions with `NSLock`, or isolate state within a dedicated `actor`.
- **Always** extract shared connection or socket handles (`self.connection`) under `lock.withLock` before calling asynchronous wire APIs.

```swift
// ❌ INCORRECT (Triggers Swift 6 Data Race error)
try await withCheckedThrowingContinuation { continuation in
    var hasResumed = false
    nwConn.stateUpdateHandler = { state in
        if state == .ready && !hasResumed {
            hasResumed = true
            continuation.resume()
        }
    }
}

// ✅ CORRECT (Swift 6 Compliant & Thread-Safe)
try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
    nonisolated(unsafe) var hasResumed = false
    let resumeLock = NSLock()

    nwConn.stateUpdateHandler = { state in
        switch state {
        case .ready:
            resumeLock.withLock {
                if !hasResumed {
                    hasResumed = true
                    continuation.resume()
                }
            }
        case .failed(let error):
            resumeLock.withLock {
                if !hasResumed {
                    hasResumed = true
                    continuation.resume(throwing: error)
                }
            }
        default:
            break
        }
    }
}
```
<!-- [END: SIG_SWIFT6_CONCURRENCY] -->

---

<!-- [START: SIG_EXHAUSTIVE_ENUMS] -->
## 2. Non-Frozen System Enum Exhaustive Matching (SIG-02)

### Context & Symptom
Enums from Apple system frameworks (`Network`, `AVFoundation`, `StoreKit`) are non-frozen. In Swift 6, omitting system cases or failing to provide an `@unknown default` clause causes compiler warnings or build failures.

### Rule & Pattern
- `NWEndpoint` must explicitly handle `.service`, `.hostPort`, `.unix`, `.url`, `.opaque`, and `@unknown default`.
- `NWConnection.State` must explicitly handle `.setup`, `.waiting`, `.preparing`, `.ready`, `.failed`, `.cancelled`, and `@unknown default`.
- `NWEndpoint.Host` must handle `.ipv4`, `.ipv6`, `.name`, and `@unknown default`.

```swift
// ✅ CORRECT (Exhaustive Pattern Matching for NWEndpoint)
switch result.endpoint {
case .service(let serviceName, _, _, _):
    name = serviceName
    deviceId = serviceName
case .hostPort(let host, let hostPort):
    name = "\(host)"
    deviceId = "\(host)"
    port = hostPort.rawValue
    switch host {
    case .ipv4(let ip): ipAddress = "\(ip)"
    case .ipv6(let ip): ipAddress = "\(ip)"
    case .name(let hostName, _): ipAddress = hostName
    @unknown default: break
    }
case .unix(let path):
    name = "Unix Socket"
    deviceId = path
case .url(let url):
    name = url.absoluteString
    deviceId = url.absoluteString
case .opaque:
    name = "Opaque Endpoint"
    deviceId = UUID().uuidString
@unknown default:
    break
}
```
<!-- [END: SIG_EXHAUSTIVE_ENUMS] -->

---

<!-- [START: SIG_MODEL_SYMMETRY] -->
## 3. Inter-Package DTO Symmetry & Computed Accessors (SIG-03)

### Context & Symptom
When maintaining standalone app bundles (`LivelyMedia.swiftpm`) alongside modular framework targets (`ios/Sources/`), nested model hierarchies must maintain symmetric convenience accessors.

### Rule & Pattern
- When a model struct wraps metadata (e.g. `CastMediaInfo` wrapping `CastMediaMetadata`), provide computed convenience accessors on an extension (`var title: String? { metadata?.title }`).
- Mirror all DTO modifications across both standalone and modular targets in the same commit.
<!-- [END: SIG_MODEL_SYMMETRY] -->

---

<!-- [START: SIG_MEMORY_ARC_DEINIT] -->
## 4. Deinit Task Dispatch & ARC Weak Reference Safety (SIG-04)

### Context & Symptom
Calling asynchronous tasks with `[weak self]` inside `deinit` triggers `objc_storeWeak` runtime crashes because weak reference tables reject pointers to objects currently in destruction.

### Rule & Pattern
- **Never** spawn `Task { [weak self] in ... }` inside `deinit`.
- Synchronously cancel handles (`task?.cancel()`, `connection?.cancel()`) and clear state directly in `deinit`.
<!-- [END: SIG_MEMORY_ARC_DEINIT] -->

---

<!-- [START: SIG_LINKER_SYMBOLS] -->
## 5. Modular Library vs Test Runner `_main` Collisions (SIG-05)

### Context & Symptom
Declaring `@main` inside an internal library module causes duplicate `_main` symbol collisions when linking Swift test runner executables (`XCTest`).

### Rule & Pattern
- Modular targets under `ios/Sources/` must remain pure libraries without `@main`.
- Only top-level app executables (e.g. `LivelyMedia.swiftpm/App.swift`) may declare `@main`.
<!-- [END: SIG_LINKER_SYMBOLS] -->

---

<!-- [START: SIG_PLATFORM_RUNNER] -->
## 6. Cross-Platform Runner & Tools Version Portability (SIG-06)

### Context & Symptom
Xcode 15.4 / Swift 5.10 runners reject `swift-tools-version: 6.0` manifests, and macOS test runners fail when resolving iOS-only SwiftUI modifiers (`.fullScreenCover`).

### Rule & Pattern
- Set `// swift-tools-version: 5.9` with platform minimums `.iOS("17.0")` for wide runner compatibility.
- Wrap platform-specific SwiftUI modifiers in `#if os(iOS) ... #else ... #endif` blocks.
<!-- [END: SIG_PLATFORM_RUNNER] -->

---

<!-- [START: SIG_TEST_CLOSURE_SAFETY] -->
## 7. XCTest Asynchronous Closure State Synchronization (SIG-07)

### Context & Symptom
In Swift 6, mutating non-isolated test variables inside `@Sendable` test callbacks violates complete concurrency checks.

### Rule & Pattern
- In test functions, mark callback-captured test variables as `nonisolated(unsafe)` and synchronize reads/writes using `NSLock.withLock`.
- Extract captured values to local constants before executing `XCTAssertEqual`.
<!-- [END: SIG_TEST_CLOSURE_SAFETY] -->

---

<!-- [START: AUDIT_CHECKLIST] -->
## 8. Pre-Commit Gate Audit Checklist for Verification Agents

Verification subagents (`code-reviewer`, `verifier`) must execute this checklist against staged `git diff` before approving a commit:

- [ ] **SIG-01**: Are all flags inside `withCheckedThrowingContinuation` marked `nonisolated(unsafe)` with `NSLock`?
- [ ] **SIG-02**: Do all `switch` statements over `NWEndpoint`, `NWConnection.State`, or system enums include `@unknown default`?
- [ ] **SIG-03**: Are model struct changes mirrored symmetrically between `ios/` and `LivelyMedia.swiftpm/`?
- [ ] **SIG-04**: Is `deinit` free of asynchronous `Task` dispatches and `[weak self]` captures?
- [ ] **SIG-05**: Are internal library targets free of `@main` attributes?
- [ ] **SIG-06**: Are platform-exclusive modifiers properly gated with `#if os(...)`?
- [ ] **SIG-07**: Are test closure captures protected with `nonisolated(unsafe)` and `NSLock`?
<!-- [END: AUDIT_CHECKLIST] -->

# Minor Engineering Case Studies

This document records tactical bug fixes, API evolution adjustments, platform compatibility guards, and UI refinements resolved during the LivelyMedia project.

---

## Case m-01: FlyingFox 0.16 -> 0.26+ Async API Evolution

### 1. Metadata
- **Subsystem**: `TransferServer` (`WebTransferServer.swift`)
- **Category**: Dependency API Evolution
- **Error Signature**:
  ```
  error: value of type 'HTTPUnhandledRequest' has no member 'body'
  error: value of type 'HTTPServer' has no member 'start'
  ```

### 2. Root Cause
Between FlyingFox 0.16 and 0.26+, the library underwent async API modernization:
1. `request.body` (Data property) was changed to an async throwing accessor `try await request.bodyData`.
2. `server.start()` was replaced with the structured concurrency entrypoint `try await server.run()`.

### 3. Resolution
```diff
 // Upload endpoint handler
-let body = request.body
+let body = try await request.bodyData

 // Server lifecycle
-try server.start()
+try await server.run()
```

---

## Case m-02: macOS Runner Platform Incompatibility for `fullScreenCover`

### 1. Metadata
- **Subsystem**: `PlayerUI` (`MainSplitNavigationView.swift`)
- **Category**: Cross-Platform SwiftUI Availability
- **Error Signature**:
  ```
  error: 'fullScreenCover(isPresented:onDismiss:content:)' is unavailable in macOS
  .fullScreenCover(isPresented: $coordinator.isFullscreenVideoPresented) { ... }
  ```

### 2. Root Cause
In `ios/Package.swift`, targets specify platforms `.iOS("17.0")` and `.macOS("14.0")` so unit tests can execute natively on macOS runner architectures. However, SwiftUI's `.fullScreenCover` modifier is restricted to iOS, tvOS, and watchOS.

### 3. Resolution
Encapsulate the fullscreen video presentation with compile-time platform checks:
```swift
#if os(iOS)
.fullScreenCover(isPresented: $coordinator.isFullscreenVideoPresented) {
    VideoPlayerOverlayView(coordinator: coordinator)
}
#else
.sheet(isPresented: $coordinator.isFullscreenVideoPresented) {
    VideoPlayerOverlayView(coordinator: coordinator)
}
#endif
```

---

## Case m-03: GRDB Duplicate Parameter Label Syntax Error

### 1. Metadata
- **Subsystem**: `CoreStorageTests` (`DatabaseTests.swift`)
- **Category**: Swift Grammar & Syntax Error
- **Error Signature**:
  ```
  error: extra argument label 'playlistId:' in call
  let itemsInPlaylist = try await playlistRepo.fetchMediaItems(in: playlistId: playlist.id)
  ```

### 2. Root Cause
In `PlaylistRepository.swift`, the method was declared as `func fetchMediaItems(in playlistId: String) async throws -> [MediaItem]`.
The test caller mistakenly provided both the external label `in:` and the internal parameter name `playlistId:` simultaneously without a comma separator.

### 3. Resolution
```diff
-let itemsInPlaylist = try await playlistRepo.fetchMediaItems(in: playlistId: playlist.id)
+let itemsInPlaylist = try await playlistRepo.fetchMediaItems(in: playlist.id)
```

---

## Case m-04: Swift Identifier Constraint Violation (`struct Wi-FiServerTab`)

### 1. Metadata
- **Subsystem**: `LivelyMedia.swiftpm`, `나의 앱.swiftpm`
- **Category**: Language Lexical Specification
- **Error Signature**:
  ```
  error: consecutive statements on a line must be separated by ';'
  struct Wi-FiServerTab: View { ... }
  ```

### 2. Root Cause
Swift identifier tokens cannot contain the hyphen character `-` as it is reserved for the subtraction/prefix operator. The compiler parsed `Wi-FiServerTab` as `Wi` minus `FiServerTab`.

### 3. Resolution
Renamed all occurrences across SwiftUI views and navigation tabs to alphanumeric CamelCase:
```diff
-struct Wi-FiServerTab: View {
+struct WiFiServerTab: View {
```

---

## Case m-05: Swift Tools Version Mismatch on GitHub Actions Runner

### 1. Metadata
- **Subsystem**: `CI/CD` (`ios/Package.swift`)
- **Category**: Toolchain Compatibility
- **Error Signature**:
  ```
  error: 'ios': package 'ios' is using Swift tools version 6.0.0 but the installed version is 5.10.0
  ```

### 2. Root Cause
`ios/Package.swift` was initially created with `// swift-tools-version: 6.0`. When running on macOS runners configured with Xcode 15.4 / Swift 5.10, the Swift Package Manager rejected the manifest prior to parsing package dependencies.

### 3. Resolution
Downgraded tools version header to `5.9` with platform minimum `.iOS("17.0")`:
```diff
-// swift-tools-version: 6.0
+// swift-tools-version: 5.9
```

---

## Case m-06: AirPlay 2 Native `AVRoutePickerView` Glassmorphism Integration

### 1. Metadata
- **Subsystem**: `PlayerUI`, `Playgrounds App`
- **Category**: UI/UX & System Component Integration

### 2. Context & Implementation
Standard SwiftUI buttons cannot directly invoke the iOS system AirPlay 2 routing sheet due to private system security policies.
Created a custom `UIViewRepresentable` bridging Apple's native `AVRoutePickerView` with dynamic Studio Amber tinting:

```swift
public struct AirPlayRoutePickerButton: UIViewRepresentable {
    public var tintColor: UIColor = UIColor(red: 0.96, green: 0.62, blue: 0.13, alpha: 1.0)

    public func makeUIView(context: Context) -> AVRoutePickerView {
        let routePicker = AVRoutePickerView()
        routePicker.tintColor = tintColor
        routePicker.activeTintColor = tintColor
        routePicker.prioritizesVideoDevices = true
        return routePicker
    }

    public func updateUIView(_ uiView: AVRoutePickerView, context: Context) {
        uiView.tintColor = tintColor
    }
}
```

---

## Case m-07: 10-Band Equalizer Preset Curve Synthesis & Haptic Scrubbers

### 1. Metadata
- **Subsystem**: `PlayerUI` (`EqualizerView.swift`)
- **Category**: Digital Signal Processing (DSP) UI & Haptics

### 2. Context & Implementation
Built a responsive 10-band graphic equalizer (32Hz to 16kHz) featuring:
- **6 Master Presets**: Studio Flat, Bass Boost, Vocal, Acoustic, Rock, Cinema.
- **Normalized dB Range**: `-12.0 dB` to `+12.0 dB` with real-time dB gain readouts.
- **Interactive Drag Gestures**: Vertical touch scrubbers with center notch snap (`0.0 dB`) and UI impact haptics.

---

## Case m-08: Non-Exhaustive Switch on Non-Frozen System Enums (`NWEndpoint`, `NWConnection.State`)

### 1. Metadata
- **Subsystem**: `CastEngine` (`ChromecastService.swift`), `Playgrounds App` (`App.swift`)
- **Category**: Compiler Exhaustiveness & System Framework Evolution (Swift 6)

### 2. Root Cause
In Swift 6 mode, pattern matching over non-frozen enums in Apple's `Network` framework (`NWEndpoint`, `NWConnection.State`, `NWEndpoint.Host`) produces compilation errors when system cases (`.unix`, `.url`, `.opaque`, `.waiting`) or future unannounced cases are not handled.

### 3. Resolution
Added exhaustive pattern matching with `@unknown default` fallback across all endpoint inspection sites in both `CastEngine` and `LivelyMedia.swiftpm`:

```swift
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

---

## Case m-09: Inter-Module Model DTO Property Symmetry & Computed Accessors

### 1. Metadata
- **Subsystem**: `CastEngine` (`CastV2Protocol.swift`), `Playgrounds App` (`App.swift`), `CastEngineTests`
- **Category**: API Ergonomics, DTO Parity & Test Assertions

### 2. Root Cause
`CastMediaInfo` encapsulates title and subtitle within nested `metadata: CastMediaMetadata?`. Direct property queries like `media?.title` failed compilation while `media?.metadata?.title` was required. Standalone Playgrounds and Core package models needed symmetrical ergonomics.

### 3. Resolution
Added computed convenience accessors on `CastMediaInfo` across all modular packages and updated test suites to validate both direct and nested paths:

```swift
public extension CastMediaInfo {
    var title: String? {
        metadata?.title
    }

    var subtitle: String? {
        metadata?.subtitle
    }
}
```

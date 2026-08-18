# Lively Media Player (iOS 18.0+ & iPadOS 18.0+)

> **Personal High-Performance Local Media Player for iPhone & iPadOS**  
> Supporting Universal Audio & Video Playback, AirPlay 2, Chromecast Local HTTP Bridge, In-App Web Media Sniffer, and Wi-Fi Web File Transfer.

---

## 🌟 Key Highlights & Features

1. **Obsidian Studio Design System**:
   - OLED-optimized deep obsidian dark theme (`#0B0C0E`) with studio amber gold accents (`#E5A93C`).
   - Adaptive **3-column `NavigationSplitView`** for iPad Air 5 (M1) and **Floating Glass Mini-Player** for iPhone 11.
   - 100-bar interactive amplitude waveform scrubber, 10-band graphic equalizer with presets, and synchronized karaoke lyrics sheet.
2. **Intelligent Dual Playback Engine**:
   - **AVPlayer (Primary Engine)**: 100% hardware acceleration, lowest battery consumption, native PiP, and zero-copy AirPlay 2.
   - **KSPlayer / Metal (Fallback Engine)**: Full support for `.mkv`, `.webm`, DTS/Opus audio, and stylized SSA/ASS anime/cinema subtitles.
3. **Chromecast Local HTTP Range Bridge**:
   - Overcomes iOS sandbox isolation by running an internal lightweight HTTP server (`FlyingFox`) serving `HTTP 206 Partial Content` directly to Chromecast / Android TV devices over local Wi-Fi.
4. **In-App Web Browser with Stream Sniffer**:
   - Integrated `WKWebView` browser with JavaScript media sniffer detecting HTML5 `<video>`, `.m3u8` (HLS), and MP4 streams with one-tap: **[Play in App]**, **[Cast to TV]**, and **[Background Download]**.
5. **Obsidian Wi-Fi Web Transfer**:
   - Built-in drag-and-drop browser uploader (`http://<device-ip>:8080`) with chunked parallel uploads and instant QR code connection.
6. **Linux Test Server Pipeline (LAN & Tailscale)**:
   - Ready-to-run Docker Compose stack providing Nginx Range streaming (:8081), WebDAV (:8082), and Mock RSS Podcast feeds (:8083).

---

## 🚀 Quick Start: Testing on Real Devices Without a Mac (Mac 없이 실기기 테스트)

상세 가이드는 [docs/NON_MAC_TEST_GUIDE.md](file:///C:/Users/kg908/Documents/antigravity/lively-turing/docs/NON_MAC_TEST_GUIDE.md)를 참고하세요.

### 방법 1 (가장 빠름): iPad Air 5 (iPadOS 18.7.8)에서 직접 빌드 & 실행
1. **iPad**의 App Store에서 **Swift Playgrounds**(무료)를 설치합니다.
2. 이 저장소의 `LivelyMedia.swiftpm` 폴더를 **iCloud Drive**에 업로드하거나 **USB-C 외장 드라이브**로 iPad의 파일 앱에 복사합니다.
3. iPad의 **Swift Playgrounds**에서 `LivelyMedia.swiftpm`을 엽니다.
4. 상단의 **▶ (실행)** 버튼을 누르면 iPad의 Apple M1 칩이 코드를 직접 컴파일하여 실기기에서 즉시 실행됩니다!

### 방법 2: iPhone 11 (iOS 18.7.7) 및 iPad에 사이드로딩 (Sideloadly / AltStore)
1. GitHub 저장소에 코드를 `git push`하면 GitHub Actions(무료 macOS 러너)가 자동으로 `.ipa`를 빌드합니다.
2. Windows PC에서 **Sideloadly**를 실행하고 iPhone 11을 케이블로 연결합니다.
3. 빌드된 `.ipa` 파일을 드래그 앤 드롭하여 본인의 무료 Apple ID로 실기기에 설치합니다.

---

## 📂 Project Architecture & Packages

```
lively-turing/
├── LivelyMedia.swiftpm/            # [iPad 단독 실행] Swift Playgrounds App 번들
│   ├── Package.swift
│   └── App.swift
├── ios/                            # [Swift 6 모듈형 코어 라이브러리]
│   ├── Package.swift               # 11개 핵심 타겟 & 11개 단위 테스트 정의
│   ├── Sources/
│   │   ├── CoreStorage/            # GRDB SQLite 데이터베이스 & 리포지토리
│   │   ├── MetadataEngine/         # AVAsset 비동기 메타데이터 파서 & 100-bar 파형 생성기
│   │   ├── TransferServer/         # Wi-Fi 웹 전송 서버 & HTTP 206 스트리밍
│   │   ├── FileManagerCore/        # iOS 파일 앱 연동 & 보안 스코프 북마크
│   │   ├── PlaybackEngine/         # AVPlayer + KSPlayer 이중 엔진 & 코디네이터
│   │   ├── PlayerUI/               # Obsidian Studio SwiftUI 플레이어 뷰 & 제스처
│   │   ├── CastEngine/             # AirPlay 2 & Google Cast 로컬 HTTP 브리지
│   │   ├── TestServerClient/       # WebDAV / HTTP Range / Mock 팟캐스트 클라이언트
│   │   ├── WebSnifferEngine/       # WKWebView 미디어 스트림 스니퍼
│   │   ├── DownloadManagerEngine/  # Background URLSession 다운로더
│   │   └── PodcastEngine/          # RSS 2.0 / iTunes XML 팟캐스트 파서
│   └── Tests/                      # 11개 모듈 단위 테스트 스위트
├── server/                         # [리눅스 테스트 서버 픽스처]
│   ├── docker-compose.test.yml     # Nginx Range :8081, WebDAV :8082, Mock RSS :8083
│   ├── nginx.conf                  # HTTP 206 지원 Nginx 설정
│   └── generate-fixtures.sh        # FFmpeg 테스트 미디어 자동 생성 스크립트
└── docs/                           # [SSOT 핵심 문서군]
    ├── ARCHITECTURE.md             # 시스템 아키텍처 & 이중 엔진 명세
    ├── DESIGN.md                   # Obsidian Studio UI/UX 명세
    ├── ROADMAP.md                  # 벤치마크, 전략, 4단계 마일스톤 & DoD
    ├── SERVER.md                   # 리눅스 테스트 서버 구축 가이드
    ├── NON_MAC_TEST_GUIDE.md       # Mac 없는 환경 실기기 테스트 완벽 가이드
    └── CHANGELOG.md                # Phase 1 ~ Phase 4 구현 변경 기록
```

---

## 🛠️ Linux Test Server Deployment (리눅스 테스트 서버 가동)

소유하고 계신 리눅스 서버(LAN 및 Tailscale)에서 테스트 미디어 서비스를 실행합니다:

```bash
# 리눅스 서버 접속 후
cd server
chmod +x generate-fixtures.sh
./generate-fixtures.sh
docker compose -f docker-compose.test.yml up -d
```
- **Nginx Range 스트리밍**: `http://<server-ip>:8081/media/sample_1080p_h264.mp4`
- **WebDAV 파일 공유**: `http://<server-ip>:8082/` (ID: `testuser` / PW: `testpassword`)
- **Mock 팟캐스트 피드**: `http://<server-ip>:8083/feed.xml`

---

## 📄 License & Standards
- Conforms to the project constitution at [GEMINI.md](file:///C:/Users/kg908/Documents/antigravity/lively-turing/GEMINI.md).
- Strict Swift 6 Concurrency & Sendable safety.

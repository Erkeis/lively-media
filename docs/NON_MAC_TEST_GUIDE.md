# Non-Mac Development & Real Device Testing Guide (No-Mac Test Suite)

이 문서는 **Mac 컴퓨터가 없는 환경**에서 **iPad Air 5 (iPadOS 18.7.8, Apple M1)** 및 **iPhone 11 (iOS 18.7.7)** 실기기에서 본 미디어 플레이어 앱을 직접 빌드하고, 테스트하고, 검증하는 완벽한 가이드입니다.

```mermaid
graph TD
    subgraph Windows_PC [Windows 개발 PC]
        Code[LivelyMedia.swiftpm / 소스 코드]
        GitPush[GitHub 저장소 Push]
    end

    subgraph iPad_Direct [방법 1: iPad Air 5 단독 빌드 및 실기기 구동 (추천)]
        iCloud[iCloud Drive / iPad 파일 앱]
        Playgrounds[Swift Playgrounds 앱 - 무료]
        RunIPad[iPad M1 실기기에서 즉시 컴파일 및 네이티브 실행]
    end

    subgraph iPhone_Sideload [방법 2: iPhone 11 및 iPad 설치 (AltStore / Sideloadly)]
        GHActions[GitHub Actions 무료 macOS 빌드 러너]
        IPABuild[LivelyMedia.ipa 빌드 아티팩트]
        AltServer[Windows AltServer / Sideloadly]
        RunIPhone[iPhone 11 & iPad Air 5 실기기 설치]
    end

    subgraph Linux_Server [방법 3: 리눅스 테스트 서버 연동]
        DockerStack[docker compose -f server/docker-compose.test.yml up -d]
        LocalStreams[Nginx Range :8081 / WebDAV :8082 / Mock RSS :8083]
    end

    Code -->|iCloud 동기화| iCloud
    iCloud --> Playgrounds
    Playgrounds --> RunIPad

    Code --> GitPush
    GitPush --> GHActions
    GHActions --> IPABuild
    IPABuild --> AltServer
    AltServer --> RunIPhone

    DockerStack --> LocalStreams
    RunIPad -.->|Wi-Fi / Tailscale 연결| LocalStreams
    RunIPhone -.->|Wi-Fi / Tailscale 연결| LocalStreams
```

---

## 방법 1 (가장 추천): iPad Air 5에서 Swift Playgrounds로 직접 컴파일 및 실행

Apple은 M1 이상의 iPadOS 기기에서 Mac 없이도 독립형 iOS/iPadOS 앱을 직접 컴파일하고 실행할 수 있는 **Swift Playgrounds 4**를 제공합니다.

### 1단계: iPad에 Swift Playgrounds 설치
- **iPad Air 5**의 App Store에서 **Swift Playgrounds**(무료) 앱을 다운로드합니다.

### 2단계: 프로젝트 폴더를 iPad로 전송
- Windows PC에서 `LivelyMedia.swiftpm` 폴더를 다음 방법 중 하나로 전달합니다:
  1. **iCloud Drive**: 웹 브라우저에서 [iCloud.com](https://www.icloud.com)에 로그인 후 `LivelyMedia.swiftpm` 폴더를 iCloud Drive에 업로드합니다.
  2. **USB-C 외장 드라이브/메모리**: Windows PC에서 USB에 `LivelyMedia.swiftpm`을 넣고, iPad Air 5의 USB-C 포트에 연결하여 **파일 앱**으로 복사합니다.

### 3단계: Swift Playgrounds에서 열기 및 빌드
1. iPad에서 **Swift Playgrounds** 앱을 실행합니다.
2. 좌측 상단 또는 메인 화면에서 **"더 많은 앱 보기" ➔ "문서 탐색"** 또는 파일 앱에서 `LivelyMedia.swiftpm`을 탭합니다.
3. 상단의 **▶ (재생/실행)** 버튼을 누르면 iPad의 Apple M1 칩이 즉시 코드를 컴파일하고 실기기 화면에서 앱이 구동됩니다!
4. **실기기 기능 검증**:
   - 오디오/비디오 로컬 재생
   - 백그라운드 오디오 및 화면 잠금 시 재생 유지
   - Wi-Fi 웹 전송 탭 테스트

---

## 방법 2: Windows에서 GitHub Actions CI로 `.ipa` 빌드 후 iPhone 11에 설치

iPhone 11은 Swift Playgrounds 앱 빌드 기능이 없으므로, **무료 GitHub Actions(macOS Runner)**를 통해 자동으로 `.ipa`를 빌드하고 Windows에서 실기기로 설치합니다.

### 1단계: GitHub Actions 빌드 워크플로우 설정
저장소 루트에 `.github/workflows/ios-build.yml`이 이미 구성되어 있습니다:
- 코드를 GitHub에 `git push`하면 GitHub의 macOS 서버가 무료로 앱을 빌드하고 `LivelyMedia.ipa`를 생성합니다.

### 2단계: Windows PC에서 Sideloadly 또는 AltStore로 설치
1. **Sideloadly 다운로드**: Windows PC에 [Sideloadly](https://sideloadly.io) (또는 AltServer)를 설치합니다.
2. **기기 연결**: iPhone 11 또는 iPad Air 5를 Lightning/USB 케이블로 Windows PC에 연결합니다.
3. GitHub Actions에서 다운로드받은 `LivelyMedia.ipa`를 Sideloadly에 드래그 앤 드롭하고 본인의 Apple ID로 사이드로딩(Sideload)합니다.
4. 기기의 **설정 ➔ 일반 ➔ VPN 및 기기 관리**에서 본인 계정을 '신뢰'로 설정하면 iPhone 11에서 즉시 앱이 실행됩니다!

---

## 방법 3: 리눅스 테스트 서버 가동 및 LAN / Tailscale 연동 테스트

소유하고 계신 리눅스 서버에서 테스트 미디어 픽스처(HLS, Range 스트리밍, WebDAV)를 실행하여 실기기 앱과 통신합니다.

### 1단계: 리눅스 서버에서 Docker 스택 실행
리눅스 서버에 SSH(또는 Tailscale SSH)로 접속하여 다음 명령을 실행합니다:

```bash
# 1. 프로젝트 server 디렉터리로 이동
cd /path/to/lively-turing/server

# 2. 테스트용 오디오/비디오/HLS 샘플 파일 자동 생성 (FFmpeg 필요)
chmod +x generate-fixtures.sh
./generate-fixtures.sh

# 3. Docker Compose 테스트 서비스 백그라운드 실행
docker compose -f docker-compose.test.yml up -d
```

### 2단계: 서비스 정상 작동 확인
```bash
# HTTP Range 206 부분 전송 테스트 (성공 시 HTTP/1.1 206 Partial Content 반환)
curl -I -H "Range: bytes=0-1024" http://localhost:8081/media/sample_1080p_h264.mp4

# WebDAV 서버 연결 확인
curl -X PROPFIND -u testuser:testpassword http://localhost:8082/
```

### 3단계: 실기기에서 접속 테스트
- **로컬 Wi-Fi 환경**: iPad Air 5 / iPhone 11이 리눅스 서버와 같은 공유기(Wi-Fi)에 연결되어 있을 때 `http://<리눅스-LAN-IP>:8081/media/sample_1080p_h264.mp4`를 앱의 브라우저 탭에 입력하여 즉시 스트리밍 재생을 검증합니다.
- **Tailscale 환경**: 외출 시 기기에서 Tailscale VPN을 켜고 `http://<리눅스-Tailscale-IP>:8081/media/...`로 원격 스트리밍을 테스트합니다.

---

## 4. 실사용 테스트 체크리스트 (iPad Air 5 & iPhone 11)

| 테스트 항목 | 테스트 시나리오 | 기대 결과 |
| :--- | :--- | :--- |
| **1. 로컬 재생** | iPad 파일 앱에서 샘플 MP3/FLAC/MP4 임포트 후 재생 | 끊김 없는 즉각 재생, 파형 스크러버 반응 |
| **2. 백그라운드 제어** | 음악 재생 중 iPad/iPhone 화면 잠금 | 소리가 멈추지 않고 잠금 화면 컨트롤러에서 조작 가능 |
| **3. AirPlay 2** | Apple TV 또는 Mac/스피커로 AirPlay 출력 전환 | A/V 싱크 유지되며 외부 기기에서 소리 출력 |
| **4. 크롬캐스트 엔진** | Wi-Fi 망의 스마트TV/Chromecast로 로컬 미디어 전송 | 순수 Swift Cast V2 소켓 연결 및 로컬 HTTP 206 서버를 통해 TV에서 버퍼링 없이 재생 및 양방향 동기화 |
| **5. 웹 전송 (Wi-Fi)** | PC 브라우저에서 `http://<iPad-IP>:8080` 접속 후 파일 업로드 | PC에서 드래그 앤 드롭한 파일이 iPad 앱 라이브러리에 즉시 표시 |
| **6. 웹 스니퍼** | 인앱 브라우저에서 웹 영상 페이지 접속 | 하단에 "미디어 감지됨" 알약 바 노출 및 다운로드 동작 |

---

### 4.1 Pure-Swift Chromecast Production Engine 상세 실기기 검증 절차

```mermaid
sequenceDiagram
    autonumber
    participant App as iPad/iPhone (LivelyMedia)
    participant Receiver as Chromecast / Google TV (Port 8009)
    participant Bridge as Local HTTP 206 Server (:8080)

    Note over App,Receiver: 1. mDNS Scanning & Discovery
    App->>Receiver: mDNS 브로드캐스트 검색 (_googlecast._tcp)
    Receiver-->>App: Bonjour TXT 레코드 응답 (기기명, IP)
    
    Note over App,Receiver: 2. Cast V2 TLS Socket & Heartbeat
    App->>Receiver: TLS 소켓 연결 (Port 8009, Self-Signed Cert 승인)
    App->>Receiver: [tp.connection] CONNECT & [receiver] LAUNCH (CC1AD845)
    loop Heartbeat (5초 주기)
        App->>Receiver: [tp.heartbeat] PING
        Receiver-->>App: [tp.heartbeat] PONG
    end

    Note over App,Bridge: 3. HTTP 206 Range Stream Delivery
    App->>Receiver: [media] LOAD (http://<iOS-LAN-IP>:8080/stream/sample.mp4)
    Receiver->>Bridge: GET /stream/sample.mp4 (Range: bytes=0-32767)
    Bridge-->>Receiver: HTTP/1.1 206 Partial Content
    Receiver->>Bridge: GET /stream/sample.mp4 (Range: bytes=32768-...)
    Bridge-->>Receiver: 연속 미디어 청크 스트리밍

    Note over App,Receiver: 4. Playback Synchronization
    Receiver-->>App: [media] MEDIA_STATUS (currentTime, playerState: "PLAYING")
    App->>Receiver: [media] PAUSE / SEEK / SET_VOLUME
    Receiver-->>App: 업데이트된 재생 위치 및 볼륨 동기화
```

#### Step 1: mDNS 디바이스 스캐닝 (Discovery Verification)
- **동작 확인**: 앱 내 상단/플레이어 바의 Cast 버튼을 탭하여 Cast 시트 호출.
- **검증 항목**:
  1. `Network.framework` `NWBrowser`가 `_googlecast._tcp` Bonjour 서비스를 감지하는지 확인.
  2. 동일 Wi-Fi LAN 내의 Chromecast / Google TV 기기 이름(`fn` 속성)과 모델 정보가 시트 목록에 1초 이내에 실시간으로 표시되는지 확인.

#### Step 2: Cast V2 소켓 연결 및 하트비트 (TLS Socket Handshake)
- **동작 확인**: 검색된 기기 목록에서 대상을 선택하여 연결.
- **검증 항목**:
  1. 대상 기기 IP의 포트 `8009`로 TLS TCP 소켓(`NWConnection`) 연결 성공.
  2. 자체 서명 X.509 인증서 신뢰 블록(`sec_protocol_options_set_verify_block`)이 정상 통과되는지 확인.
  3. `urn:x-cast:com.google.cast.receiver` 채널을 통해 기본 미디어 수신기(`CC1AD845`) 앱이 실행되어 TV 화면에 Cast 대기 화면이 표시되는지 확인.
  4. 5초 주기로 `PING` / `PONG` 하트비트가 오가며 백그라운드 연결이 안정적으로 유지되는지 확인.

#### Step 3: HTTP 206 Range 부분 전송 스트리밍 (Byte-Range Delivery)
- **동작 확인**: 로컬 샌드박스에 저장된 1080p MP4 또는 고음질 FLAC/MP3 파일 재생 중 Cast 전송 실행.
- **검증 항목**:
  1. 기기의 Wi-Fi 인터페이스 LAN IP(`getifaddrs`)가 정확히 해석되어 `http://<iOS-IP>:8080/stream/<filename>` 형태의 스트림 URL이 수신기로 전달되는지 확인.
  2. 크롬캐스트 수신기가 파일 헤더(moov atom 등)를 읽기 위해 보내는 `Range: bytes=0-32767` 요청에 대해 `FlyingFox` 임베디드 서버가 `HTTP/1.1 206 Partial Content` 및 `Content-Range` 헤더로 정확히 응답하는지 확인.
  3. TV 화면에서 버퍼링 및 끊김 없이 부드럽게 비디오/오디오가 하드웨어 디코딩 재생되는지 확인.

#### Step 4: 원격 재생 제어 및 양방향 타임라인 동기화 (Playback Sync)
- **동작 확인**: 앱 화면의 재생/일시정지 버튼, 탐색 스크러버(Seek), 볼륨 슬라이더 조작.
- **검증 항목**:
  1. `urn:x-cast:com.google.cast.media` 채널로 `PLAY`, `PAUSE`, `SEEK`, `SET_VOLUME` JSON 페이로드가 즉각 전송되는지 확인.
  2. TV 수신기로부터 주기적으로 수신되는 `MEDIA_STATUS` 메시지의 `currentTime`과 `playerState`가 iOS 앱의 SwiftUI 뷰(`@MainActor`)로 즉시 반영되어 진행 바가 원격 TV와 1:1 일치하는지 확인.
  3. Cast 시트에서 "연결 해제(Disconnect)" 탭 시 소켓이 안전하게 종료되고 앱이 로컬 재생 모드로 복귀하는지 확인.

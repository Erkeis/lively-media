# TEST SERVER & INFRASTRUCTURE RULES (`server/GEMINI.md`)

## 1. PURPOSE & SCOPE
- Defines the configuration, services, and networking for the Linux test server used during media player development.
- Target environment: Linux server accessible via local LAN and Tailscale mesh VPN.

## 2. SERVICE STANDARDS
- **Containerization**: Deploy all test services (Nginx HTTP streaming, WebDAV, Mock RSS/Podcast, Samba) via Docker Compose.
- **HTTP Range Support**: Nginx must have `slice` and `accept-ranges: bytes` enabled to test seeking and Chromecast buffering.
- **Port Allocation**: Use explicit, non-conflicting port mappings.
- **Security & Access**:
  - Restrict SSH access to authorized public keys and Tailscale network.
  - Test credentials for WebDAV/SMB must be clearly documented in `.env.example`.

## 3. NETWORKING CONSTRAINTS
- Note: AirPlay and Chromecast discovery (mDNS / SSDP) require layer 2 broadcast on the local Wi-Fi LAN.
- Remote testing over Tailscale is supported for direct HTTP/WebDAV/SMB streaming, but device discovery features require local LAN connectivity.

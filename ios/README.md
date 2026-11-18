# XiaoZhiAI iOS

Native SwiftUI client for the same XiaoZhi backend used by the Android app.

## Defaults

Two applications are generated:

| Scheme | Display name | OTA | WebSocket |
|---|---|---|---|
| `XiaoZhiAI` | 小安 | `http://sql.ms48.com:8002/xiaozhi/ota/` | `ws://sql.ms48.com:8001/xiaozhi/v1/` |
| `XiaoZhiAILAN` | 小安内网 | `http://192.168.0.20:8002/xiaozhi/ota/` | `ws://192.168.0.20:8001/xiaozhi/v1/` |

The applications have different bundle identifiers and can be installed at the
same time. The LAN build allows arbitrary HTTP loads for local debugging; the
domain build only allows insecure loads for `sql.ms48.com`.

The HTTP/WS endpoints are allowed through a domain-specific App Transport
Security exception. Production builds should switch these defaults to HTTPS/WSS
and remove the exception.

## Generate the Xcode project

On macOS:

```bash
brew install xcodegen
cd ios
chmod +x scripts/build-opus-ios.sh
./scripts/build-opus-ios.sh
xcodegen generate
open XiaoZhiAI.xcodeproj
```

Select `XiaoZhiAI` for the domain build or `XiaoZhiAILAN` for the LAN build.

The client implements configuration, device identity, OTA, WebSocket
handshake, text messaging, server event decoding, the shared protocol
fixtures, and a native AVFoundation/Opus audio pipeline. Generated Opus
binaries and headers are not committed.


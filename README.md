# MDC Sender

Native macOS tools for sending images to a Samsung EMDX color e-paper display over Samsung MDC TCP.

This project contains:

- A Go CLI named `mdc`.
- A SwiftUI macOS app named `MDC Sender.app`.
- A SwiftUI iOS app project named `MDC Sender iOS`.
- Shared config in `~/.mdc/config.json`, used by the CLI and macOS UI.
- Image fitting/cropping for the Samsung EM32DX `2560x1440` panel.

It is currently built and tested against a Samsung EM32DX / LH32EMDI display.

## Features

- Send JPG, JPEG, PNG, and BMP files to the display.
- Authenticate with Samsung's secured MDC TCP protocol.
- Wake the display with Wake-on-LAN when its MAC address is known.
- Remember display IP, PIN, display ID, MAC, local IP, transfer timeout, and image fit settings.
- Render images to an exact display canvas before sending:
  - `original`: send the source image as-is.
  - `contain`: preserve the whole image on a white canvas.
  - `cover`: fill the canvas and crop overflow.
  - `stretch`: force the image to the canvas aspect ratio.
- Adjust crop focus with `--crop-x` and `--crop-y`.
- Wait until the display downloads the image before returning.
- Inspect basic display info through MDC.
- Send from iPhone with the native SwiftUI iOS app.

## Quick Start

Build the CLI:

```sh
go build -o build/mdc ./cmd/mdc
```

Configure the display once:

```sh
build/mdc config set \
  --host 192.168.1.225 \
  --pin 123456 \
  --mac B0:F2:F6:60:F7:43 \
  --local-ip 192.168.1.66 \
  --fit cover \
  --canvas-width 2560 \
  --canvas-height 1440 \
  --crop-y 0.65
```

Test authentication:

```sh
build/mdc auth
```

Send an image:

```sh
build/mdc show-image --image ~/Pictures/poster.jpg
```

Wake the display:

```sh
build/mdc wakeup
```

Show diagnostic info:

```sh
build/mdc info
build/mdc battery
```

## macOS App

Build a double-clickable app bundle:

```sh
scripts/build_macos_app.sh
```

Open it:

```sh
open "build/MDC Sender.app"
```

The app bundles the Go CLI at `Contents/Resources/mdc`, reads the same `~/.mdc/config.json` file, and exposes the same display, transfer, and image fitting options.

## iOS App

Open the native iOS app project:

```sh
open ios/MDCSenderiOS/MDCSenderiOS.xcodeproj
```

The iOS app is designed around a large e-paper preview and Liquid Glass-style floating controls. It implements the MDC protocol in Swift because iOS cannot shell out to the Go CLI.

The app includes:

- Photo picking through `PhotosUI`.
- Native image preprocessing for `original`, `contain`, `cover`, and `stretch`.
- Temporary local HTTP server for `/content.json`, `/<uuid>.jpg`, and display progress callbacks.
- MDC TCP secured protocol client with STARTTLS/PIN auth.
- Wake-on-LAN support.
- Display settings stored on-device in `UserDefaults`.

See [ios/MDCSenderiOS/README.md](ios/MDCSenderiOS/README.md) for run instructions and design notes.

### iOS v1 Build And Signing

The iOS project is versioned as `1.0.0` build `1` with bundle identifier `net.maarten.mdcsender.ios`.

Build a signed archive:

```sh
xcodebuild \
  -project ios/MDCSenderiOS/MDCSenderiOS.xcodeproj \
  -scheme "MDC Sender iOS" \
  -configuration Release \
  -destination generic/platform=iOS \
  -archivePath build/releases/MDC-Sender-iOS-v1.xcarchive \
  archive
```

Export a development/debugging IPA:

```sh
xcodebuild \
  -exportArchive \
  -archivePath build/releases/MDC-Sender-iOS-v1.xcarchive \
  -exportPath build/releases/MDC-Sender-iOS-v1-debugging \
  -exportOptionsPlist ios/MDCSenderiOS/ExportOptions.development.plist
```

This IPA is signed for debugging/development distribution. It is useful for devices covered by the provisioning profile, but it is not a public App Store-style installer. For non-developer installs, use TestFlight/App Store distribution or create an ad-hoc export with a provisioning profile that includes the target device UDIDs.

## CLI Syntax

```sh
mdc show-image --host IP --pin PIN --image PATH [--mac MAC]
mdc set-content-url --host IP --pin PIN --url URL
mdc auth --host IP --pin PIN
mdc info --host IP --pin PIN
mdc battery --host IP --pin PIN
mdc wakeup --mac MAC
mdc config show
mdc config path
mdc config set [options]
```

Common options:

```text
--host IP          display IP address
--pin PIN          six-character secured MDC PIN
--port 1515        MDC TCP port
--display 0        display ID, 0..253
```

Image sending options:

```text
--image PATH       image to send
--mac MAC          optional Wake-on-LAN MAC address
--local-ip IP      local IP address reachable by the display
--http-port N      local HTTP server port, 0 means automatic
--timeout 120s     wait timeout for image download
--no-wait          return after the MDC command ACK
--fit original     original, contain, cover, or stretch
--canvas-width N   target display canvas width
--canvas-height N  target display canvas height
--crop-x N         horizontal focus from 0.0 to 1.0
--crop-y N         vertical focus from 0.0 to 1.0
```

For a portrait or non-16:9 photo on the EM32DX panel, `cover` usually gives the best full-screen result:

```sh
build/mdc show-image \
  --image ~/Pictures/photo.jpg \
  --fit cover \
  --canvas-width 2560 \
  --canvas-height 1440 \
  --crop-y 0.65
```

`--crop-y 0.5` keeps the vertical center. Higher values keep more of the bottom and crop more from the top. Lower values keep more of the top.

## Shared Config

The CLI and macOS app share:

```text
~/.mdc/config.json
```

The file is written with `0600` permissions because it contains the display PIN.

Example:

```json
{
  "host": "192.168.1.225",
  "port": 1515,
  "display_id": 0,
  "pin": "123456",
  "mac": "B0:F2:F6:60:F7:43",
  "local_ip": "192.168.1.66",
  "timeout_seconds": 120,
  "wait_for_download": true,
  "image_fit": "cover",
  "canvas_width": 2560,
  "canvas_height": 1440,
  "crop_x": 0.5,
  "crop_y": 0.65
}
```

Show the active config:

```sh
build/mdc config show
```

Print the config path:

```sh
build/mdc config path
```

Use a temporary config for testing:

```sh
MDC_CONFIG=/tmp/mdc-config.json build/mdc config show
```

## Protocol Notes

Samsung MDC uses compact binary frames over TCP. A regular MDC request is:

```text
AA CMD DISPLAY_ID LENGTH DATA... CHECKSUM
```

The checksum is the low byte of the sum of all bytes after `AA`, including `CMD`, `DISPLAY_ID`, `LENGTH`, and `DATA`.

A response is:

```text
AA FF DISPLAY_ID LENGTH ACK_OR_NAK ORIGINAL_CMD DATA... CHECKSUM
```

For the EMDX display tested here, MDC is exposed on TCP port `1515` with Samsung's secured protocol:

1. Connect to `DISPLAY_IP:1515`.
2. Read the plaintext banner `MDCSTART<<TLS>>`.
3. Upgrade the socket to TLS.
4. Send the display PIN.
5. Read `MDCAUTH<<PASS>>` or `MDCAUTH<<FAIL:0xNN>>`.
6. Send normal MDC frames inside the TLS connection.

The image flow does not stream image bytes through MDC. Instead:

1. The Mac or iPhone starts a temporary HTTP server.
2. The server exposes `/content.json` and an image URL. The CLI/macOS flow uses `/image`; the iOS v1 flow advertises `/<uuid>.jpg` because the tested display rejected JSON-slash-escaped URLs.
3. The sender sends MDC command `0xC7`.
4. The command payload is:

```text
53 80 URL_LENGTH URL_BYTES...
```

5. The display downloads `content.json`, then downloads the image URL referenced in that manifest.
6. The display may POST progress to `/content-transfer-progress`; the iOS server accepts this callback and logs the reported status.

This keeps the MDC channel small and matches the display's own content download behavior.

## Network Discovery

The display needs to be reachable from the Mac over the same LAN. Useful checks:

```sh
nc -G 2 -vz 192.168.1.225 1515
arp -n 192.168.1.225
```

Wake-on-LAN requires the display MAC address:

```sh
build/mdc wakeup --mac B0:F2:F6:60:F7:43
```

If the image command succeeds but the display never downloads the image, the advertised local IP is probably wrong. Set the Mac address that the display can reach:

```sh
build/mdc config set --local-ip 192.168.1.66
```

## Troubleshooting

`authentication failed: MDCAUTH<<FAIL:0xNN>>`

The TCP connection and TLS handshake worked, but the PIN was rejected. Check the PIN in the Samsung app or display settings. The tested display expects a six-character secured MDC PIN.

`connect: host is down` or `connection refused`

The display is asleep, offline, changing network state, or MDC is not listening. Try Wake-on-LAN and retry the port check.

`timed out waiting for display to download image`

The display accepted the MDC command but did not fetch the image from the Mac. Set `--local-ip` to the Mac interface on the same network as the display.

For iOS, check the in-app transfer log. If the display reports `URL using bad/illegal format or missing URL`, make sure the manifest advertises a plain unescaped URL such as `http://192.168.1.65:8080/<uuid>.jpg`.

`negative acknowledgement for command ...`

The display rejected that MDC command. Some standard MDC commands are unsupported on the EMDX model even when authentication succeeds.

## Display Notes

The tested display label identifies:

- Model: `EM32DX`
- Model code: `LH32EMDIBGBXEN`
- Type: `LH32EMDI`
- Native panel resolution: `2560x1440`
- Supported image files: JPG, JPEG, PNG, BMP

## Development

Run tests:

```sh
go test ./...
swift build --package-path . -c debug --product MDCUI
```

Build everything:

```sh
go build -o build/mdc ./cmd/mdc
scripts/build_macos_app.sh
xcodebuild -project ios/MDCSenderiOS/MDCSenderiOS.xcodeproj -scheme "MDC Sender iOS" -configuration Release -destination generic/platform=iOS -archivePath build/releases/MDC-Sender-iOS-v1.xcarchive archive
```

The Go code owns protocol handling, config, Wake-on-LAN, image preprocessing, the HTTP content server, and the CLI. The macOS SwiftUI app is a native wrapper that shells out to the bundled CLI. The iOS SwiftUI app implements MDC, image rendering, and the local HTTP server natively in Swift.

## License

MIT. See `LICENSE`.

# MDC Sender iOS

Native SwiftUI iOS app for sending photos to a Samsung EM32DX e-paper display.

Open the project:

```sh
open ios/MDCSenderiOS/MDCSenderiOS.xcodeproj
```

Select the `MDC Sender iOS` scheme, choose an iPhone, and run.

## v1 Status

Version `1.0.0` build `1` has been tested on a real iPhone against a Samsung EM32DX / LH32EMDI display over MDC TCP.

Known-good display settings from the test setup:

- Display IP: `192.168.1.225`
- MDC port: `1515`
- Display ID: `0`
- Secured MDC PIN: six characters
- HTTP port: `8080`
- Panel: `2560x1440`
- Fit: `cover`
- Vertical focus: around `0.65`

The iOS app stores these settings in `UserDefaults`, separate from the CLI/macOS `~/.mdc/config.json`.

## Design

The first screen is the product workflow:

1. Choose or replace a photo.
2. Preview it inside an e-paper frame.
3. Tune fit/crop if needed.
4. Send.

The selected photo becomes the content layer and the controls float above it. On iOS 26 and newer, custom controls use SwiftUI Liquid Glass through `glassEffect(_:in:)`. On earlier iOS versions, the app falls back to `ultraThinMaterial`.

This follows Apple's Liquid Glass guidance:

- Standard SwiftUI controls adopt the system look automatically.
- Custom Liquid Glass is applied to controls and navigation elements.
- The content layer remains the photo/preview instead of becoming a heavy glass card.

References:

- https://developer.apple.com/documentation/technologyoverviews/liquid-glass
- https://developer.apple.com/documentation/swiftui/applying-liquid-glass-to-custom-views
- https://developer.apple.com/design/human-interface-guidelines/materials

## Implementation

The iOS app implements the MDC flow natively in Swift:

- `MDCClient.swift`: raw TCP socket, Samsung STARTTLS banner, SecureTransport TLS upgrade, PIN auth, MDC frames.
- `LocalContentServer.swift`: temporary local HTTP server that serves `/content.json`, the generated `/<uuid>.jpg`, and `/content-transfer-progress`.
- `ImageRenderer.swift`: renders the selected photo to `2560x1440` using `original`, `contain`, `cover`, or `stretch`.
- `WakeOnLAN.swift`: optional Wake-on-LAN packet sender.
- `SenderView.swift`: Liquid Glass-style SwiftUI interface.

The app stores display settings in `UserDefaults`, not in the macOS CLI config. The user should enter:

- Display IP, for example `192.168.1.225`
- PIN, for example `136300`
- MAC for Wake-on-LAN, for example `B0:F2:F6:60:F7:43`
- Optional local IP override if iOS cannot infer the Wi-Fi address

## Image Fit

The crop button opens the fit controls:

- `Original`: send the selected JPEG as-is.
- `Contain`: keep the whole photo visible on a white `2560x1440` canvas.
- `Cover`: fill the display and crop overflow.
- `Stretch`: force the photo to `2560x1440`.

`Horizontal focus` and `Vertical focus` control which part of the image is kept when `cover` crops overflow. With `contain`, they position the photo inside any remaining white area. They are disabled for `original` and `stretch` because those modes do not have meaningful crop focus.

## Permissions

The app declares:

- `NSLocalNetworkUsageDescription`
- `NSPhotoLibraryUsageDescription`

iOS will ask for local network access when the app connects to the display or hosts the temporary content server.

## Build Verification

Code build check:

```sh
xcodebuild \
  -project ios/MDCSenderiOS/MDCSenderiOS.xcodeproj \
  -scheme "MDC Sender iOS" \
  -configuration Debug \
  -sdk iphoneos \
  -destination generic/platform=iOS \
  -derivedDataPath build/DerivedData-iOS \
  CODE_SIGNING_ALLOWED=NO \
  build
```

The simulator build may require local CoreSimulator services to be available. In restricted environments, a generic iOS device build is the more reliable compile check.

## Signing

The project uses automatic signing with:

- Team: `CYJQTUCH5F`
- Bundle identifier: `net.maarten.mdcsender.ios`
- Version: `1.0.0`
- Build: `1`

On this machine the v1 archive signed successfully with:

- Certificate: `Apple Development: Maarten Goet (GFK797D388)`
- Provisioning profile: `iOS Team Provisioning Profile: *`

Create a signed release archive:

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

The resulting IPA is useful for devices covered by the provisioning profile. A GitHub release can host it as a convenience artifact, but iOS will not install a development-signed IPA on arbitrary devices. For family-friendly distribution, use TestFlight/App Store distribution or export an ad-hoc IPA with all target device UDIDs included in the provisioning profile.

## v1 Artifact

The v1 local artifact built during release preparation is:

```text
build/releases/MDC-Sender-iOS-v1.ipa
```

SHA-256:

```text
b0d677a55078272e607d6b2f9467ed7dfdf9e06042d0fe35f12462ca2cb9b186
```

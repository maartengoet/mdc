# MDC Sender iOS v1

Native iPhone app for sending photos to a Samsung EM32DX / LH32EMDI e-paper display over Samsung MDC TCP.

## Highlights

- SwiftUI iOS app with Liquid Glass-style controls.
- Photo picker, large e-paper preview, and fit/crop controls.
- Native Samsung secured MDC client with STARTTLS and PIN authentication.
- Temporary local HTTP server for `content.json`, generated JPEG downloads, and transfer progress callbacks.
- Image rendering for the `2560x1440` EM32DX panel with `original`, `contain`, `cover`, and `stretch` modes.
- Tested live against display IP `192.168.1.225` on MDC port `1515`.

## Signing

The attached IPA is a development/debugging export signed with Apple Development credentials for team `CYJQTUCH5F`.

It is not a public App Store installer. It can be installed only on devices covered by the provisioning profile, or through Xcode using the same developer account. For wider distribution, use TestFlight/App Store or an ad-hoc export with the target device UDIDs in the provisioning profile.

## Artifact

- Version: `1.0.0`
- Build: `1`
- Bundle ID: `net.maarten.mdcsender.ios`
- SHA-256: `b0d677a55078272e607d6b2f9467ed7dfdf9e06042d0fe35f12462ca2cb9b186`

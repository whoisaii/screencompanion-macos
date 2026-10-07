# Architecture

The app uses native macOS frameworks and direct HTTPS requests. It has no third-party package dependencies.

| Component | Responsibility |
| --- | --- |
| `Source/Core.swift` | Settings, provider endpoints, Keychain storage, crop geometry, ScreenCaptureKit capture, API payloads and response parsing, global shortcuts |
| `Source/App.swift` | Application lifecycle, floating AppKit panel, SwiftUI views, settings, request orchestration, local capture preview |
| `Source/main.swift` | Application entry point and offline-test mode |
| `Source/Tests.swift` | Lightweight offline assertions for serialization, transport shapes, parsing, and image processing |
| `Source/Info.plist` | Bundle metadata and screen-capture usage description |
| `Source/build.sh` | Local native build, ad-hoc signing, and self-tests |

## Request lifecycle

The user starts a request from the panel, menu bar, or a global shortcut. Settings are copied for that request, and the selected provider's key is loaded from Keychain.

For screen requests, ScreenCaptureKit selects the display under the pointer and filters out the app's own process. Optional model-based region detection returns normalized coordinates. The crop validator rejects invalid coordinates and adds a small margin. A vision request transcribes the selected image; a final request receives both the transcription and image. A typed question takes priority over other visible questions.

Text-only requests skip capture and transcription. Requests use async URLSession calls, support cancellation, and report common provider errors in the panel. No automatic provider switching occurs.

## Platform adaptation

Windows-specific UI and capture APIs are replaced by AppKit/SwiftUI and ScreenCaptureKit. Keychain replaces Windows account-bound credential protection. Carbon hotkey registration provides configurable global shortcuts without a general-purpose keyboard-event logger. Window geometry is saved with AppKit's frame autosaving.

The app requests window-sharing restrictions as a best-effort measure; this is distinct from the explicit filter used for its own captures and is not treated as a guarantee against third-party recording.

## Deliberate limitations

This is a compact prototype, not a one-to-one restoration of the Windows source. Provider adapters share a request path but account/model compatibility still needs live validation. The UI, settings management, and request orchestration currently share a large source file. Offline assertions are useful checks, not substitutes for UI and end-to-end tests.

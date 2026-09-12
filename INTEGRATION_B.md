# INTEGRATION_B — App Workflow, Emergency Handling & Backend

Owner: Laptop B. This document covers everything needed to build, run, and
integrate the pieces this laptop is responsible for.

## Environment note

This half of the project was written in a Linux dev environment with no
Xcode/macOS toolchain available, so **the iOS app has not been compiled or
run** — only carefully hand-reviewed. The backend, by contrast, **was**
installed and smoke-tested locally (see "Backend — verified" below). Please
build the iOS target first thing and report any compiler errors; the code
follows standard SwiftUI/SwiftData/AVFAudio/CoreLocation APIs throughout, but
a first build is the real verification.

## Files created

```
project.yml                                   XcodeGen spec (see "Building the iOS app")
iOS/Info.plist                                Location/microphone usage strings, launch screen
iOS/LifeOptimizerApp.swift                    @main, SwiftData container, dependency wiring
iOS/Models/AppModels.swift                    DetectionResult, DetectionClassification, UserResponse,
                                               EmergencyEvent, SwiftData models (DetectionEvent, EmergencyContactRecord)
iOS/Detection/DetectionProvider.swift         protocol DetectionProvider, protocol DetectionFeedbackReceiver
iOS/Detection/DetectionConfig.swift           fusion weights + NORMAL/MEDIUM/HIGH thresholds (single source of truth)
iOS/Detection/MockDetectionProvider.swift     DemoMode enum + full mock engine driving the demo
iOS/App/AppState.swift                        the medium/high workflow state machine + 15s countdown
iOS/App/RootTabView.swift                     Home / History / Settings tab scaffold
iOS/Location/LocationManager.swift            protocol LocationProvider, CLLocationManager-backed impl
iOS/Emergency/AlarmManager.swift              protocol AlarmService, escalating tone via AVAudioEngine
iOS/Emergency/EmergencyService.swift          protocol EmergencyService, backend-backed impl
iOS/Emergency/EmergencyManager.swift          orchestrates location -> alarm -> POST -> persist -> UI state
iOS/Networking/APIClient.swift                URLSession client for the FastAPI backend
iOS/Speech/SpeechAnalyzer.swift               protocol + MockSpeechAnalyzer (stretch goal, unwired)
iOS/Features/Home/HomeView.swift              dashboard + demo-mode buttons
iOS/Features/Monitoring/MonitoringView.swift  facial/motion bars + status
iOS/Features/Alert/MediumConfidenceView.swift "are you okay" + 15s countdown
iOS/Features/Emergency/EmergencyView.swift    emergency screen + "I'm Safe"
iOS/Features/History/HistoryView.swift        SwiftData-backed incident list
iOS/Features/Settings/SettingsView.swift      emergency contact + backend URL + privacy copy

backend/requirements.txt
backend/main.py                               FastAPI app, all endpoints
backend/models.py                             Pydantic schemas
backend/services/emergency.py                 in-memory incident store + simulated notify/dispatch
```

## Shared contracts (what Laptop A's code must match)

```swift
enum DetectionClassification: String, Codable { case normal = "NORMAL", mediumConfidence = "MEDIUM", highConfidence = "HIGH" }

struct DetectionResult: Codable, Equatable {
    var facialScore: Double
    var depthScore: Double
    var motionScore: Double
    var temporalScore: Double
    var speechScore: Double?
    var finalScore: Double
    var classification: DetectionClassification
    var timestamp: Date
}

enum UserResponse: String, Codable { case confirmedOkay, needsHelp, timeout }

protocol DetectionProvider {
    var detectionStream: AsyncStream<DetectionResult> { get }
}

protocol DetectionFeedbackReceiver {
    func submit(response: UserResponse, for result: DetectionResult)
}
```

`DetectionFeedbackReceiver` is an addition beyond the literal spec snippet: it
lets the UI report a user's "I'm okay" / "I need help" / timeout back to
whichever engine is plugged in, without the UI touching baseline/anomaly
internals directly. Laptop A's real engine should conform to it and treat
`.confirmedOkay` as a benign-anomaly-store event, per the baseline-pollution
rule — **never** feed an anomalous observation into the core baseline just
because the user said they're okay.

All of these live in `iOS/Models/AppModels.swift` and
`iOS/Detection/DetectionProvider.swift`. Please don't change their shapes
without syncing here first — the whole app (state machine, screens, backend
payloads) is built against them.

## How the demo currently works (no real sensing yet)

`iOS/Detection/MockDetectionProvider.swift` implements both protocols above
and drives every demo scenario by itself:

- Ticks its current mode (`normal` / `medium` / `high`) into the stream
  every 2 seconds.
- `trigger(_ mode: DemoMode)` — called from Home's Demo Mode buttons —
  forces an immediate reading in that mode (Scenarios 1, 2, 5).
- `submit(response:for:)` — called by `AppState` — handles Scenario 3
  (confirmed okay resets to normal) and updates internal state for
  Scenario 4 (needs-help/timeout). **Note:** for needs-help/timeout it does
  NOT immediately re-emit a HIGH reading — `AppState` already escalates to
  the emergency workflow deterministically on that response (see below), so
  an immediate re-emission here would risk double-triggering the emergency
  workflow via a race between the two paths.

`iOS/App/AppState.swift` is the actual state machine: it consumes
`DetectionResult`s from whatever `DetectionProvider` it's given, runs the
15-second countdown on MEDIUM, and calls `EmergencyManager.handleHighConfidence`
on HIGH (whether reached directly or via escalation). It doesn't know or
care whether the provider is real or mocked.

## Switching to Laptop A's real engine

In `iOS/LifeOptimizerApp.swift`, this is the one line that matters:

```swift
let detectionProvider = MockDetectionProvider()
```

Replace it with Laptop A's real `DetectionProvider` conformer (and pass it as
`feedbackReceiver:` too if it also conforms to `DetectionFeedbackReceiver`).
Nothing else in the app — no view, no state machine code — needs to change.
If Laptop A's engine does NOT conform to `DetectionFeedbackReceiver`, pass
`feedbackReceiver: nil` to `AppState.init` and the "confirmed okay" signal
will simply not be reported back (the app-side workflow still functions).

Also remove the Demo Mode buttons from `HomeView` (or leave them — they only
affect `MockDetectionProvider` and become inert no-ops once it's no longer
the active provider, since `AppEnvironment.shared.mockDetectionProvider`
would then be `nil`).

## Building the iOS app (do this on a Mac)

This repo does not commit an `.xcodeproj` — it's generated from
`project.yml` via [XcodeGen](https://github.com/yonaskolb/XcodeGen) so the
project file itself never has to be hand-merged between teammates.

```bash
brew install xcodegen        # once, if not already installed
cd LifeOptimizer
xcodegen generate
open LifeOptimizer.xcodeproj
```

Then in Xcode: select a development team under Signing & Capabilities (the
generated project uses `CODE_SIGN_STYLE: Automatic`), pick an iPhone
simulator (iOS 17+), and Run.

Deployment target is iOS 17 (required by SwiftData).

## Running the backend

```bash
cd backend
python3 -m venv .venv && source .venv/bin/activate
pip install -r requirements.txt
uvicorn main:app --reload --host 0.0.0.0 --port 8000
```

Then set the app's backend URL in Settings:
- iOS Simulator: `http://127.0.0.1:8000` (default, already set)
- Physical iPhone: `http://<your-Mac's-LAN-IP>:8000` — the phone and the
  Mac running the backend must be on the same Wi-Fi network.

### Backend — verified

Installed and smoke-tested in this session (Linux, Python 3, in a venv):
`GET /health`, `POST /emergency` (with the exact example payload from the
spec), `GET /incident/{id}`, `GET /incident/{unknown-id}` (confirmed 404),
`POST /incident` (generic, auto-generated id), `GET /incidents`, and
`GET /dashboard` all returned the expected shapes.

### Endpoints

| Method | Path | Body | Response |
|---|---|---|---|
| GET | `/health` | – | `{"status": "ok"}` |
| POST | `/incident` | `IncidentPayload` (see below) | `{"status": "incident_recorded", "incidentId": "..."}` |
| POST | `/emergency` | `EmergencyPayload` | `{"status": "emergency_triggered", "contactNotified": true, "emergencyServices": "SIMULATED", "incidentId": "..."}` |
| POST | `/incident/{id}/cancel` | – | updated `IncidentRecord` (used by "I'm Safe", currently local-only on the app side — see Known limitations) |
| GET | `/incident/{id}` | – | `IncidentRecord` or 404 |
| GET | `/incidents` | – | `[IncidentRecord]`, newest first |
| GET | `/dashboard` | – | plain HTML table of incidents, for judges |

`EmergencyPayload` / `IncidentPayload` shapes (see `backend/models.py` for
the authoritative Pydantic definitions):

```json
{
  "incidentId": "ABC123",
  "timestamp": "2026-09-12T10:00:00Z",
  "confidence": 0.91,
  "classification": "HIGH",
  "location": {"latitude": 40.44, "longitude": -79.99},
  "signals": {"facial": 0.88, "depth": 0.71, "motion": 0.82, "temporal": 0.84, "speech": null},
  "contactName": "Jane Doe",
  "contactPhone": "555-1234"
}
```

No raw facial frames, depth maps, video, or the on-device personal baseline
are ever sent — only scores, a classification label, location, and
identifiers, per the project's privacy model.

## Known limitations

- **iOS app not built/run** in this environment (no Xcode available here).
  First build on a Mac is the real test; please report anything that
  doesn't compile.
- Backend storage is a process-local in-memory dict — restarting the
  backend clears all incidents. Fine for a demo; would need a real store
  otherwise.
- The "I'm Safe" button currently stops the local alarm and marks the
  SwiftData record but does not yet call `POST /incident/{id}/cancel` on
  the backend — trivial to wire up if the dashboard should reflect
  cancellations.
- `SpeechAnalyzer` / `MockSpeechAnalyzer` exist per the spec but are not
  wired into `MediumConfidenceView` — kept as a pure stretch-goal hook so it
  never blocks the MVP, per the project's own scope rules.
- Alarm audio is a synthesized tone (`AVAudioEngine`, no bundled asset) to
  avoid an audio-asset dependency; volume ramps 20/40/60/80/100% every 5s
  and stops immediately on "I'm Safe".
- No automated tests were added in this pass (Linux environment can't run
  Xcode's test runner for the iOS side); the backend was verified manually
  via curl rather than pytest, given the 3-hour scope. Worth adding
  `pytest` + `httpx` backend tests and iOS unit tests for `AppState`'s
  transitions if time allows.

## Please don't modify

- The shared contracts in `iOS/Models/AppModels.swift` and
  `iOS/Detection/DetectionProvider.swift` without updating this doc — the
  whole app is built against those exact shapes.
- `iOS/Detection/DetectionConfig.swift`'s weights/thresholds are the single
  source of truth for NORMAL/MEDIUM/HIGH — please don't duplicate magic
  numbers elsewhere; import and reuse this instead.

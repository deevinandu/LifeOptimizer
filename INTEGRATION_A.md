# INTEGRATION_A.md
# LifeOptimizer — Laptop A Integration Guide

> **For Laptop B:** This document describes everything you need to consume the intelligence engine.
> You should NEVER import `ARKit`, `CoreMotion`, `AVFoundation`, or any Laptop A internal module directly.
> All integration happens through the types in `FeatureVector.swift` and the `DetectionProvider` protocol.

---

## Files Created / Modified

### New Files

| File | Purpose |
|------|---------|
| `LifeOptimizer/Intelligence/Models/FeatureVector.swift` | **All shared contracts** — start here |
| `LifeOptimizer/Sensors/Face/FaceFeatureProvider.swift` | Protocol for face sensor |
| `LifeOptimizer/Sensors/Face/ARKitFaceTracker.swift` | Real ARKit implementation |
| `LifeOptimizer/Sensors/Face/FaceFeatureExtractor.swift` | Asymmetry computation |
| `LifeOptimizer/Sensors/Face/TrueDepthProvider.swift` | TrueDepth protocol + mock |
| `LifeOptimizer/Sensors/Face/MockFaceFeatureProvider.swift` | Demo face sensor |
| `LifeOptimizer/Sensors/Motion/MotionFeatureProvider.swift` | Protocol for motion sensor |
| `LifeOptimizer/Sensors/Motion/CoreMotionProvider.swift` | Real CoreMotion implementation |
| `LifeOptimizer/Sensors/Motion/MotionFeatureExtractor.swift` | Magnitude/jerk computation |
| `LifeOptimizer/Sensors/Motion/MockMotionFeatureProvider.swift` | Demo motion sensor |
| `LifeOptimizer/Intelligence/Baseline/BaselineEngine.swift` | EMA personal baseline with anomaly gate |
| `LifeOptimizer/Intelligence/Baseline/BaselineStore.swift` | SwiftData persistence bridge |
| `LifeOptimizer/Intelligence/Baseline/BenignAnomalyStore.swift` | User-confirmed benign memory |
| `LifeOptimizer/Intelligence/Anomaly/FacialAnomalyDetector.swift` | Weighted z-score facial anomaly |
| `LifeOptimizer/Intelligence/Anomaly/MotionAnomalyDetector.swift` | Weighted z-score motion anomaly |
| `LifeOptimizer/Intelligence/Anomaly/TemporalAnalyzer.swift` | Rolling window persistence |
| `LifeOptimizer/Intelligence/Fusion/ConfidenceEngine.swift` | Multimodal weighted fusion |
| `LifeOptimizer/Intelligence/Fusion/DetectionStateMachine.swift` | Full pipeline orchestration |
| `LifeOptimizer/Persistence/Models.swift` | SwiftData models |
| `LifeOptimizer/Demo/DemoDataProvider.swift` | Deterministic demo scenarios |
| `LifeOptimizer/Demo/MockDetectionProvider.swift` | Drop-in mock for Laptop B |
| `LifeOptimizer/App/LifeOptimizerApp.swift` | App entry point |
| `LifeOptimizer/App/ContentView.swift` | Debug view (Laptop A only) |
| `LifeOptimizerTests/IntelligenceTests.swift` | Unit tests (9 groups) |

---

## Public Protocols (Laptop B Integration Surface)

### `DetectionProvider` — **PRIMARY**
```swift
public protocol DetectionProvider: AnyObject {
    var detectionStream: AsyncStream<DetectionResult> { get }
    var eventStream:     AsyncStream<DetectionEvent>  { get }
    var currentState:    SMState                      { get }
    func startMonitoring()
    func stopMonitoring()
    func submitUserResponse(_ response: UserResponse)
}
```

### `FaceFeatureProvider`
```swift
public protocol FaceFeatureProvider: AnyObject {
    func start()
    func stop()
    var featureStream: AsyncStream<FacialFeatureVector> { get }
    var isRunning: Bool { get }
}
```

### `MotionFeatureProvider`
```swift
public protocol MotionFeatureProvider: AnyObject, Sendable {
    func start()
    func stop()
    var featureStream: AsyncStream<MotionFeatureVector> { get }
    var isRunning: Bool { get }
}
```

### `TrueDepthProvider`
```swift
public protocol TrueDepthProvider: AnyObject {
    func start()
    func stop()
    var depthStream: AsyncStream<DepthFeatureVector> { get }
    var isSupported: Bool { get }
    var isRunning: Bool { get }
}
```

---

## Key Models (Laptop B Should Use)

### `DetectionResult` — The primary output

```swift
public struct DetectionResult: Sendable, Codable {
    public let facialScore:    Double           // 0–1
    public let depthScore:     Double           // 0–1 (0 if TrueDepth unavailable)
    public let motionScore:    Double           // 0–1
    public let temporalScore:  Double           // 0–1
    public let speechScore:    Double?          // nil until speech is implemented
    public let finalScore:     Double           // 0–1 weighted combination
    public let classification: DetectionClassification  // .normal / .medium / .high
    public let timestamp:      Date
}
```

### `DetectionClassification`

```swift
public enum DetectionClassification: String, Codable {
    case normal = "NORMAL"
    case medium = "MEDIUM"
    case high   = "HIGH"
}
```

### `DetectionEvent` — State machine events

```swift
public enum DetectionEvent: Sendable {
    case classificationChanged(DetectionResult)
    case escalatedToMedium(DetectionResult)
    case escalatedToHigh(DetectionResult)
    case resolvedToNormal(DetectionResult)
    case userConfirmedBenign(DetectionResult)
}
```

### `UserResponse` — Laptop B sends this back

```swift
public enum UserResponse: Sendable {
    case okay        // "I'm fine" → benign anomaly stored, returns to NORMAL
    case needsHelp   // "I need help" → escalates to HIGH immediately
    case timeout     // 15-second timer expired → escalates to HIGH
}
```

### `SMState` — Current state machine state

```swift
public enum SMState: Equatable, Sendable {
    case idle
    case normal
    case mediumConfidence
    case highConfidence
}
```

---

## How to Start Monitoring (Real Mode)

```swift
import LifeOptimizer  // or whatever your module target name is

@MainActor
func setupMonitoring() {
    let faceProvider   = ARKitFaceTracker()
    let motionProvider = CoreMotionProvider()

    let sm = DetectionStateMachine(
        faceProvider:   faceProvider,
        motionProvider: motionProvider
    )

    sm.startMonitoring()

    // Subscribe to results
    Task {
        for await result in sm.detectionStream {
            print("Score: \(result.finalScore) — \(result.classification.rawValue)")
        }
    }

    // Subscribe to state-change events
    Task {
        for await event in sm.eventStream {
            switch event {
            case .escalatedToMedium(let result):
                // Show medium alert UI, start 15-second timer
                showMediumAlert(result: result)
            case .escalatedToHigh(let result):
                // Trigger emergency workflow
                triggerEmergency(result: result)
            default:
                break
            }
        }
    }
}
```

---

## How to Receive DetectionResult

Every `fusionInterval` (default 0.5s), `detectionStream` emits a `DetectionResult`.
```swift
for await result in sm.detectionStream {
    // Update your monitoring UI
    updateMonitoringUI(result)
}
```

---

## How to Submit User Response

When the user taps "I'm Okay" or "I Need Help" in the medium-alert UI:

```swift
// User says okay
sm.submitUserResponse(.okay)

// User says needs help
sm.submitUserResponse(.needsHelp)

// 15-second timer fires with no response
sm.submitUserResponse(.timeout)
```

---

## How to Enable Demo Mode

### Option A — Full pipeline demo (recommended for hackathon)

```swift
// In DemoDataProvider.swift
let sm = DemoDataProvider.stateMachine(for: .high)
sm.startMonitoring()
// Subscribe to streams exactly as above
```

### Option B — Mock provider for Laptop B UI testing (no ARKit needed)

```swift
let mock = MockDetectionProvider(scenario: .medium)
mock.startMonitoring()

// Manually trigger scenarios
mock.inject(scenario: .high)

// Works exactly like the real DetectionProvider
for await event in mock.eventStream { ... }
```

### Available Demo Scenarios

| Scenario | facialScore | motionScore | temporalScore | classification |
|----------|-------------|-------------|---------------|----------------|
| `.normal` | 0.10 | 0.08 | 0.05 | NORMAL |
| `.facialAnomaly` | 0.65 | 0.10 | 0.45 | MEDIUM |
| `.medium` | 0.65 | 0.10 | 0.55 | MEDIUM |
| `.high` | 0.85 | 0.80 | 0.90 | HIGH |

---

## SwiftData Models (Shared Storage)

The following models are persisted. Laptop B can read them via ModelContext:

| Model | Purpose |
|-------|---------|
| `PersistedBaselineFeature` | Per-feature mean/variance stats |
| `PersistedBenignAnomaly` | User-confirmed harmless events |
| `PersistedDetectionEvent` | Detection history (for incident log) |
| `UserProfile` | User name + emergency contact |

The `PersistedDetectionEvent` has a `toDetectionResult()` helper for displaying history.

---

## Build Instructions

1. Open `LifeOptimizer.xcodeproj` in Xcode on macOS
2. Select target: `LifeOptimizer`
3. Deployment target: **iOS 17.0+** (required for SwiftData)
4. Required capabilities (add in Xcode signing & capabilities):
   - `NSCameraUsageDescription` — for ARKit face tracking
   - `NSMotionUsageDescription` — for Core Motion
5. Build: `Cmd+B`
6. Run tests: `Cmd+U`
7. For simulator testing: use `MockFaceFeatureProvider` / `MockMotionFeatureProvider`
   (ARKit face tracking requires a physical device with TrueDepth camera)

### Required `Info.plist` keys

```xml
<key>NSCameraUsageDescription</key>
<string>LifeOptimizer uses the front camera to track facial features for anomaly detection.</string>

<key>NSMotionUsageDescription</key>
<string>LifeOptimizer uses motion sensors to detect unusual device movement.</string>
```

---

## Classification Thresholds (Configurable)

```swift
// In DetectionThresholds enum — change these to tune sensitivity
public static let normalUpperBound: Double = 0.35   // below → NORMAL
public static let mediumUpperBound: Double = 0.70   // above → HIGH
```

> ⚠️ These are **demonstration thresholds only** — NOT clinical values.

---

## Things Laptop B Should NOT Modify

- Anything in `Sensors/` (ARKit and CoreMotion implementations)
- `Intelligence/Baseline/BaselineEngine.swift` (personal baseline logic)
- `Intelligence/Anomaly/` (anomaly detectors)
- `Intelligence/Fusion/ConfidenceEngine.swift` (weights)
- `FeatureVector.swift` (shared contracts — discuss changes together)

---

## Known Limitations

1. **ARKit requires physical device** — the TrueDepth front camera is not emulated in Simulator
2. **Baseline needs warm-up** — ~30 normal observations (~30 seconds) before anomaly gating is active
3. **TrueDepth is mocked** — `MockTrueDepthProvider` is used; real AVFoundation depth capture is P2
4. **Speech is not implemented** — weight = 0.0, `SpeechScore` is always nil; Laptop B may implement `SpeechAnalyzer` and pass the score in
5. **No cloud sync** — baseline is local only (by design, for privacy)
6. **Fusion interval = 0.5s** — detection result emitted every 500ms; configurable via `sm.fusionInterval`
7. **15-second timer** — NOT implemented here; Laptop B owns this UX timer. When it fires: `sm.submitUserResponse(.timeout)`

---

## What Is Real vs. Mocked

| Component | Real | Mocked |
|-----------|------|--------|
| ARKit face tracking | ✅ ARKitFaceTracker | MockFaceFeatureProvider |
| Facial feature extraction | ✅ FaceFeatureExtractor | — |
| Asymmetry computation | ✅ FaceFeatureExtractor | — |
| Core Motion | ✅ CoreMotionProvider | MockMotionFeatureProvider |
| Jerk/magnitude | ✅ MotionFeatureExtractor | — |
| Personal baseline (EMA) | ✅ BaselineEngine | Pre-warmed in DemoDataProvider |
| Anomaly detection (z-score) | ✅ FacialAnomalyDetector, MotionAnomalyDetector | — |
| Temporal persistence | ✅ TemporalAnalyzer | — |
| Multimodal fusion | ✅ ConfidenceEngine | — |
| TrueDepth | ❌ Stub | ✅ MockTrueDepthProvider |
| Speech | ❌ Not implemented | — |
| SwiftData persistence | ✅ Models.swift | — |
| Benign anomaly memory | ✅ BenignAnomalyStore | — |

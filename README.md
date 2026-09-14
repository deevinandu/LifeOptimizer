# StrOK

**An experimental personalized multimodal early-warning system for stroke-like anomalies.**

> *"Can a smartphone detect potentially stroke-like anomalies more reliably by comparing a person's current facial behavior against their own baseline and corroborating it with device-motion signals?"*

---

## ⚠️ Disclaimer

This is a **proof-of-concept hackathon project**. It is **NOT** a medical device, clinical tool, or validated diagnostic system. All detection thresholds are demonstration values only. Do not use for medical decision-making.

---

## Architecture Overview

```
iPhone
├── ARKit (front TrueDepth camera)
│   └── Facial blend shapes + head pose → FacialFeatureVector
├── TrueDepth depth (optional/mocked)
│   └── Left/right depth asymmetry → DepthFeatureVector
└── Core Motion
    └── Accelerometer + gyroscope → MotionFeatureVector
          ↓
    Personal Baseline Engine (EMA, local only)
          ↓
    Anomaly Detection (z-score, personalized)
    ├── FacialAnomalyDetector
    ├── MotionAnomalyDetector
    └── TemporalAnalyzer (rolling window)
          ↓
    Multimodal Fusion (weighted confidence)
          ↓
    DetectionStateMachine
    ├── NORMAL  → update baseline
    ├── MEDIUM  → ask user, 15s timer (Laptop B)
    └── HIGH    → emergency workflow (Laptop B)
```

---

## Project Structure

```
LifeOptimizer (StrOK)/
├── App/                           Minimal app shell
├── Sensors/
│   ├── Face/                      ARKit + Mock face providers
│   └── Motion/                    CoreMotion + Mock motion providers
├── Intelligence/
│   ├── Models/FeatureVector.swift  ← Laptop B integration surface
│   ├── Baseline/                  Personal EMA baseline
│   ├── Anomaly/                   Z-score detectors + temporal
│   └── Fusion/                    Confidence engine + state machine
├── Persistence/Models.swift       SwiftData schemas
└── Demo/                          Deterministic demo mode
```

---

## Requirements

- iOS 17.0+
- iPhone X or later (TrueDepth front camera for ARKit face tracking)
- Xcode 15+

---

## Build & Run

1. Open `LifeOptimizer.xcodeproj` in Xcode
2. Select your device (ARKit requires physical device)
3. Add capabilities: Camera Usage, Motion Usage
4. Build: `Cmd+B`
5. Test: `Cmd+U`

### Demo Mode (Simulator-friendly)

The app defaults to demo mode — no physical device needed for the demo UI.
Change scenario in the picker:
- **Normal** — baseline behavior
- **Facial Anomaly** — unilateral facial drooping
- **Medium** — combined facial + motion anomaly
- **High** — severe anomaly, triggers emergency workflow

---

## Integration

- **Laptop A** (this repo): Sensing + intelligence engine
- **Laptop B**: App UI + emergency workflow

See [`INTEGRATION_A.md`](INTEGRATION_A.md) for the full integration guide.

---

## Key Design Principles

1. **Personalized** — compares against *your* baseline, not a population model
2. **Privacy-preserving** — baseline stays on device; only incident metadata goes to backend
3. **Anomaly-gated** — anomalous observations never corrupt the baseline
4. **Modular** — all sensing behind protocols; TrueDepth and speech are optional
5. **Deterministic demo** — hackathon presentation works without reproducing exact anomalies

import Foundation

/// Stretch goal (P2). Kept as a thin protocol + mock so it never blocks the
/// MVP -- nothing in the core state machine depends on this producing a
/// real result. A future implementation could use Apple's Speech
/// framework; speech recognition correctness must never be treated as
/// equivalent to medical stroke detection.
protocol SpeechAnalyzer {
    func performTest() async -> SpeechResult
}

final class MockSpeechAnalyzer: SpeechAnalyzer {
    func performTest() async -> SpeechResult {
        SpeechResult(slurScore: 0.0, confidence: 0.0)
    }
}

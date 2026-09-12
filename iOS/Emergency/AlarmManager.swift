import AVFAudio
import Foundation

protocol AlarmService {
    func start()
    func stop()
}

/// Local escalating alarm (spec section 9). Generates its own tone with
/// `AVAudioEngine` rather than bundling an audio asset, and ramps volume on
/// a fixed schedule: 0-5s 20%, 5-10s 40%, 10-15s 60%, 15-20s 80%, 20s+ 100%.
/// Always trivially stoppable via the "I'm Safe" button (`stop()`).
final class AlarmManager: AlarmService {
    private let engine = AVAudioEngine()
    private let playerNode = AVAudioPlayerNode()
    private let toneBuffer: AVAudioPCMBuffer
    private var escalationTimer: Timer?
    private var elapsed: TimeInterval = 0

    init() {
        let format = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 1)!
        toneBuffer = Self.makeToneBuffer(format: format, frequency: 880, duration: 0.5)
        engine.attach(playerNode)
        engine.connect(playerNode, to: engine.mainMixerNode, format: format)
    }

    func start() {
        elapsed = 0
        playerNode.volume = 0.2

        do {
            try engine.start()
        } catch {
            print("AlarmManager: failed to start audio engine: \(error)")
            return
        }

        playerNode.scheduleBuffer(toneBuffer, at: nil, options: .loops)
        playerNode.play()

        escalationTimer?.invalidate()
        escalationTimer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            self?.escalate()
        }
    }

    func stop() {
        escalationTimer?.invalidate()
        escalationTimer = nil
        playerNode.stop()
        engine.stop()
    }

    private func escalate() {
        elapsed += 5
        switch elapsed {
        case ..<10: playerNode.volume = 0.4
        case ..<15: playerNode.volume = 0.6
        case ..<20: playerNode.volume = 0.8
        default: playerNode.volume = 1.0
        }
    }

    private static func makeToneBuffer(format: AVAudioFormat, frequency: Double, duration: Double) -> AVAudioPCMBuffer {
        let frameCount = AVAudioFrameCount(format.sampleRate * duration)
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount)!
        buffer.frameLength = frameCount
        let channel = buffer.floatChannelData![0]
        for frame in 0..<Int(frameCount) {
            let value = sin(2.0 * .pi * frequency * Double(frame) / format.sampleRate)
            channel[frame] = Float(value) * 0.5
        }
        return buffer
    }
}

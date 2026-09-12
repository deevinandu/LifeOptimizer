import AVFAudio
import Foundation
import MediaPlayer
import UIKit

protocol AlarmService {
    func start()
    func stop()
}

/// Local siren alarm (spec section 9). The point of this sound is to get
/// someone physically nearby to come help -- so it goes to full volume
/// immediately (no gentle ramp-up) and follows a fixed on/off pattern:
/// 30s on, 10s off, 30s on, repeating in that same 30/10 cycle
/// indefinitely until explicitly silenced via `stop()`. Once silenced it
/// stays off permanently -- it never resumes on its own, even mid-cycle.
final class AlarmManager: AlarmService {
    private let engine = AVAudioEngine()
    private let playerNode = AVAudioPlayerNode()
    private let toneBuffer: AVAudioPCMBuffer
    private var cycleTask: Task<Void, Never>?

    private static let onDuration: UInt64 = 30_000_000_000
    private static let offDuration: UInt64 = 10_000_000_000

    init() {
        let format = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 1)!
        // A harsh two-tone "yelp" (square wave, abruptly alternating
        // 1200Hz/1800Hz every 130ms) -- the same family of sound as a car
        // alarm or civil-defense siren. A square wave is deliberately
        // harsher/buzzier than a smooth sine (it's full of upper
        // harmonics), and the abrupt tone-switching is far more jarring
        // than a smooth warble -- unpleasant on purpose, since a pleasant
        // tone is exactly what's easy to tune out.
        toneBuffer = Self.makeSirenBuffer(format: format, duration: 1.04)
        engine.attach(playerNode)
        engine.connect(playerNode, to: engine.mainMixerNode, format: format)

        // `.playback` ignores the physical Ring/Silent switch -- an
        // emergency siren meant to summon help from anyone nearby must
        // not go silent just because the phone happens to be muted.
        try? AVAudioSession.sharedInstance().setCategory(.playback, options: [.duckOthers])
    }

    func start() {
        cycleTask?.cancel()
        try? AVAudioSession.sharedInstance().setActive(true)
        maximizeSystemVolume()

        cycleTask = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                self.beginPlaying()
                try? await Task.sleep(nanoseconds: Self.onDuration)
                guard !Task.isCancelled else { break }
                self.pausePlaying()
                try? await Task.sleep(nanoseconds: Self.offDuration)
            }
        }
    }

    /// Silences the alarm immediately and permanently for this incident --
    /// cancels the on/off cycle outright rather than just pausing it, so
    /// it will not resume on its own after this call.
    func stop() {
        cycleTask?.cancel()
        cycleTask = nil
        pausePlaying()
        engine.stop()
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    private func beginPlaying() {
        playerNode.volume = 1.0
        if !engine.isRunning {
            try? engine.start()
        }
        playerNode.scheduleBuffer(toneBuffer, at: nil, options: .loops)
        playerNode.play()
    }

    private func pausePlaying() {
        playerNode.stop()
    }

    /// Forces the device's *system* output volume to max, not just our own
    /// audio-session gain. `playerNode.volume = 1.0` above only maxes our
    /// app's own signal relative to whatever the hardware volume happens
    /// to be set to -- if the user last had it turned down, the alarm
    /// would quietly play at that lower level despite our own gain being
    /// maxed. iOS has no public API to set system volume directly; this
    /// is the standard (App-Store-safe) workaround: an offscreen
    /// `MPVolumeView` exposes a real `UISlider` wired to the system
    /// volume, and setting its value moves the actual hardware level.
    private func maximizeSystemVolume() {
        DispatchQueue.main.async {
            let volumeView = MPVolumeView(frame: .zero)
            guard let window = UIApplication.shared.connectedScenes
                .compactMap({ ($0 as? UIWindowScene)?.keyWindow })
                .first
            else { return }
            volumeView.alpha = 0.0001
            window.addSubview(volumeView)
            // The slider only reflects/controls the real system volume
            // once it's actually attached to a window -- give it one run
            // loop turn before touching it.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                if let slider = volumeView.subviews.first(where: { $0 is UISlider }) as? UISlider {
                    // Setting `.value` directly only moves the slider's
                    // visual thumb -- MPVolumeView's real wiring to the
                    // system volume lives on its `.valueChanged` target,
                    // which only fires from user interaction or an
                    // explicit `sendActions` call. Without this line the
                    // hardware volume silently does not change at all.
                    slider.setValue(1.0, animated: false)
                    slider.sendActions(for: .valueChanged)
                }
                volumeView.removeFromSuperview()
            }
        }
    }

    private static func makeSirenBuffer(format: AVAudioFormat, duration: Double) -> AVAudioPCMBuffer {
        let frameCount = AVAudioFrameCount(format.sampleRate * duration)
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount)!
        buffer.frameLength = frameCount
        let channel = buffer.floatChannelData![0]
        let sampleRate = format.sampleRate

        let toneDuration = 0.13
        let lowFrequency = 1200.0
        let highFrequency = 1800.0

        var phase = 0.0
        for frame in 0..<Int(frameCount) {
            let t = Double(frame) / sampleRate
            let toneIndex = Int(t / toneDuration) % 2
            let frequency = toneIndex == 0 ? lowFrequency : highFrequency
            phase += 2.0 * .pi * frequency / sampleRate
            // Square wave (hard on/off at the zero-crossing), not a sine --
            // this is what makes it sound like an actual siren/alarm
            // instead of a musical tone.
            let value: Float = sin(phase) >= 0 ? 1.0 : -1.0
            channel[frame] = value * 0.9
        }
        return buffer
    }
}

import Foundation
import AVFoundation
import LiveKit
import Observation

/// Live microphone level, so changing the input device can be verified rather
/// than assumed.
@Observable
@MainActor
final class AudioLevelMonitor {
    /// 0…1, already smoothed for display.
    private(set) var level: Float = 0

    private var renderer: LevelRenderer?

    func start() {
        guard renderer == nil else { return }
        let renderer = LevelRenderer { [weak self] rms in
            Task { @MainActor in self?.apply(rms) }
        }
        self.renderer = renderer
        AudioManager.shared.add(localAudioRenderer: renderer)
    }

    func stop() {
        guard let renderer else { return }
        AudioManager.shared.remove(localAudioRenderer: renderer)
        self.renderer = nil
        level = 0
    }

    /// Fast attack, slow release — a meter that drops instantly reads as
    /// broken even when audio is fine.
    private func apply(_ rms: Float) {
        let scaled = min(max(rms * 12, 0), 1)
        level = scaled > level ? scaled : level * 0.85 + scaled * 0.15
    }
}

private final class LevelRenderer: NSObject, AudioRenderer, @unchecked Sendable {
    private let onLevel: @Sendable (Float) -> Void

    init(onLevel: @escaping @Sendable (Float) -> Void) {
        self.onLevel = onLevel
        super.init()
    }

    func render(pcmBuffer: AVAudioPCMBuffer) {
        guard let channel = pcmBuffer.floatChannelData?[0] else { return }
        let count = Int(pcmBuffer.frameLength)
        guard count > 0 else { return }

        var sum: Float = 0
        for index in 0 ..< count {
            let sample = channel[index]
            sum += sample * sample
        }
        onLevel(sqrt(sum / Float(count)))
    }
}

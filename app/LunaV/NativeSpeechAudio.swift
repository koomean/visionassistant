import AVFoundation
import Foundation

/// Reuse the established silence/tone/broadband-noise gate before native STT.
/// The recording itself is preserved; this scan never changes its timing.
enum NativeSpeechAudio {
    static func validate(_ file: AVAudioFile) throws {
        let format = file.processingFormat
        guard format.sampleRate > 0, format.channelCount > 0, file.length > 0 else {
            throw NativeSpeechDecoderError.noSpeech
        }
        let duration = Double(file.length) / format.sampleRate
        guard duration <= 120 else { throw NativeSpeechDecoderError.recordingTooLong }
        guard duration >= 0.3, file.length <= 24_000_000, format.channelCount <= 8 else {
            throw NativeSpeechDecoderError.noSpeech
        }
        let originalPosition = file.framePosition
        defer { file.framePosition = originalPosition }
        let count = min(LocalSpeechAudio.maximumSamples, Int(Double(file.length) * 16_000 / format.sampleRate))
        guard count >= 4_800 else { throw NativeSpeechDecoderError.noSpeech }
        // Two bounded passes retain the exact mean-centred gate used by Whisper,
        // without allocating normalized/padded audio that native Dictation ignores.
        var sum: Float = 0
        try forEachMonoSample(file, count: count) { sample in
            guard sample.isFinite else { throw NativeSpeechDecoderError.noSpeech }
            sum += sample
        }
        let mean = sum / Float(count)
        var scan = LocalSpeechAudio.ValidationScan()
        try forEachMonoSample(file, count: count) { scan.observe(centered: $0 - mean) }
        guard scan.acceptsSpeech else { throw NativeSpeechDecoderError.noSpeech }
    }

    private static func forEachMonoSample(_ file: AVAudioFile, count: Int,
                                         consume: (Float) throws -> Void) throws {
        let format = file.processingFormat
        let capacity = AVAudioFrameCount(min(file.length, 16_384))
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: capacity) else {
            throw NativeSpeechDecoderError.noSpeech
        }
        file.framePosition = 0
        var blockStart: AVAudioFramePosition = 0
        let channels = Int(format.channelCount)
        for index in 0..<count {
            let source = min(file.length - 1, AVAudioFramePosition(Double(index) * format.sampleRate / 16_000))
            while buffer.frameLength == 0 || source >= blockStart + AVAudioFramePosition(buffer.frameLength) {
                blockStart = file.framePosition
                try file.read(into: buffer, frameCount: capacity)
                guard buffer.frameLength > 0 else { throw NativeSpeechDecoderError.noSpeech }
            }
            guard let samples = buffer.floatChannelData else { throw NativeSpeechDecoderError.noSpeech }
            let offset = Int(source - blockStart)
            var value: Float = 0
            for channel in 0..<channels { value += samples[channel][offset] }
            try consume(value / Float(channels))
        }
    }
}

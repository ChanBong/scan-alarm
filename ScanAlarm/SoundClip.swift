import AVFoundation

/// System alarms and notifications only accept short uncompressed sounds,
/// so the chosen tune is cut down to a WAV clip for them.
enum SoundClip {
    static let maxSeconds: Double = 29

    static func make(from source: URL, to destination: URL) throws {
        let input = try AVAudioFile(forReading: source)
        let format = input.processingFormat
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: format.sampleRate,
            AVNumberOfChannelsKey: format.channelCount,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false,
        ]
        let output = try AVAudioFile(forWriting: destination, settings: settings,
                                     commonFormat: format.commonFormat,
                                     interleaved: format.isInterleaved)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 32768) else {
            throw CocoaError(.fileReadUnknown)
        }
        var remaining = AVAudioFrameCount(min(Double(input.length), format.sampleRate * maxSeconds))
        while remaining > 0 {
            try input.read(into: buffer, frameCount: min(32768, remaining))
            if buffer.frameLength == 0 { break }
            try output.write(from: buffer)
            remaining -= min(remaining, buffer.frameLength)
        }
    }
}

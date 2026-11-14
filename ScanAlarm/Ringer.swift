import AVFoundation

/// Loops the alarm sound while the app is open and ringing. Uses the playback
/// category, so it ignores the silent switch and keeps going if the phone is locked.
final class Ringer {
    static let shared = Ringer()

    private var player: AVAudioPlayer?

    func start(url: URL?) {
        if let player {
            if !player.isPlaying { player.play() }
            return
        }
        guard let url else { return }
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .default, options: [])
        try? session.setActive(true)
        let newPlayer = try? AVAudioPlayer(contentsOf: url)
        newPlayer?.numberOfLoops = -1
        newPlayer?.volume = 1
        newPlayer?.play()
        player = newPlayer
    }

    func stop() {
        guard let player else { return }
        player.stop()
        self.player = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
}

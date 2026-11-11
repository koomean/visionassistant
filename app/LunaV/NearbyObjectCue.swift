import AudioToolbox
import UIKit

enum NearbyObjectCue {
    @MainActor static func play() {
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        guard let url = Bundle.main.url(forResource: "ObjectCentered", withExtension: "wav") else { return }
        var sound: SystemSoundID = 0
        guard AudioServicesCreateSystemSoundID(url as CFURL, &sound) == kAudioServicesNoError else { return }
        let cue = sound
        AudioServicesPlaySystemSoundWithCompletion(cue) {
            AudioServicesDisposeSystemSoundID(cue)
        }
    }
}

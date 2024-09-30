//
//  Calibration.swift
//  overdub
//
//  Created by Colin Fox on 9/21/24.
//

import AVFoundation

class Calibrator: NSObject, AVAudioPlayerDelegate, ObservableObject {
    var audioPlayer: AVAudioPlayer?
    
    // Observable property to track if audio finished playing
    @Published var calibrationFinished = false

    func playWavFile() {
        // Ensure the file is included in the app's bundle
        if let url = Bundle.main.url(forResource: "wn-10-12k", withExtension: "wav") {
            do {
                audioPlayer = try AVAudioPlayer(contentsOf: url)
                audioPlayer?.delegate = self
                audioPlayer?.prepareToPlay()
                audioPlayer?.play()
            } catch {
                print("Error playing WAV file: \(error.localizedDescription)")
            }
        } else {
            print("WAV file not found")
        }
    }
    
    // Delegate method to detect when the audio finishes playing
    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        if flag {
            print("Calibration complete.")
            self.audioPlayer = nil
            self.calibrationFinished = true  // Notify the view of the event
        } else {
            print("Calibration complete, but there was an issue.")
        }
    }
}

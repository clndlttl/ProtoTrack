//
//  Calibration.swift
//  overdub
//
//  Created by Colin Fox on 9/21/24.
//

import AVFoundation
import Accelerate

class Calibrator: NSObject, AVAudioPlayerDelegate, ObservableObject {
    var audioPlayer: AVAudioPlayer?
    
    let stimFilename: String = "wn-5-44100"
    
    // Observable property to track if audio finished playing
    @Published var calibrationFinished = false

    func playWavFile(atTime: TimeInterval) {
        // Ensure the file is included in the app's bundle
        if let url = Bundle.main.url(forResource: self.stimFilename, withExtension: "wav") {
            do {
                audioPlayer = try AVAudioPlayer(contentsOf: url)
                audioPlayer?.delegate = self
                audioPlayer?.prepareToPlay()
                audioPlayer?.play(atTime: atTime)
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
    
   
    
    // Compute the time shift between stimulus and response
    func getTransferFunc(_ filename: String) -> DSPSplitComplex? {
        
        let audioFilename = getDocumentsDirectory().appendingPathComponent(filename)

        guard let stimURL = Bundle.main.url(forResource: self.stimFilename, withExtension: "wav") else {
            print("Cannot find calibration stimulus")
            return nil
        }
        
        guard let stimBuffer = readAudioFile(url: stimURL),
              let respBuffer = readAudioFile(url: audioFilename) else {
            print("Cannot read stim/resp")
            return nil
        }
        
        guard let H = estimateTransferFunction(stim: stimBuffer, resp: respBuffer) else {
            print("Cannot estimate TF")
            return nil
        }
        
        return H
    }
}

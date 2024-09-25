//
//  AudioPlayerManager.swift
//  overdub
//
//  Created by Colin Fox on 9/18/24.
//

import AVFoundation
import Accelerate

class AudioPlayerManager: NSObject, AVAudioPlayerDelegate, ObservableObject {
    var audioPlayer: AVAudioPlayer?
    
    // Observable property to track if audio finished playing
    @Published var audioFinished = false
    
    func prepareAudio(filename: String) {
        let audioFilename = getDocumentsDirectory().appendingPathComponent(filename)
                
        do {
            audioPlayer = try AVAudioPlayer(contentsOf: audioFilename)
            audioPlayer?.delegate = self  // Set the delegate
            audioPlayer?.prepareToPlay()  // Start playing the audio
            print("Audio prepared.")
        } catch {
            print("Failed to prepare audio: \(error.localizedDescription)")
        }
    }
    
    func playAudio() {
        audioPlayer?.play()
    }
    
    func pauseAudio() -> TimeInterval {
        audioPlayer?.pause()
        return audioPlayer?.currentTime ?? 0.0
    }
   
    func stopAudio() {
        audioPlayer?.stop()
        audioPlayer = nil
    }
    
    func setCurrentTime(time: TimeInterval) {
        audioPlayer?.currentTime = time
    }
    
    // Delegate method to detect when the audio finishes playing
    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        if flag {
            print("Audio finished playing successfully.")
            DispatchQueue.main.async {
                self.audioFinished = true  // Notify the view of the event
            }
        } else {
            print("Audio finished playing, but there was an issue.")
        }
    }
    
    func getEnvelope(bins: Int) -> [Float]? {
        
        let base = getDocumentsDirectory().appendingPathComponent("base.m4a")
        guard let buffer = readAudioFile(url: base) else {
            print("No envelope to get.")
            return nil
        }
        
        guard let floatData = buffer.floatChannelData else {
            return nil
        }
        
        let framesPerBin = Int(buffer.frameLength) / bins
        
        var envelope = Array(repeating: Float(0), count: bins)
        
        for i in 0..<bins {
            vDSP_svesq(&floatData[0][i*framesPerBin], 1, &envelope[i], vDSP_Length(framesPerBin))
        }
        
        // normalize
        var maxval: Float = 1.0 / (envelope.max() ?? 1.0)
        vDSP_vsmul(envelope, 1, &maxval, &envelope, 1, vDSP_Length(bins))
        
        return envelope
    }
}

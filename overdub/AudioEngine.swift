//
//  AudioRecorderManager.swift
//  overdub
//
//  Created by Colin Fox on 10/10/24.
//

import AVFoundation
import SwiftUI

class AudioEngine: ObservableObject {
    private var audioEngine: AVAudioEngine?
    private var inputNode: AVAudioInputNode?
    @Published var micBuffer: AVAudioPCMBuffer?
    
    func start() {
        audioEngine = AVAudioEngine()
        inputNode = audioEngine?.inputNode
        
        if let inode = inputNode,
           let inputFormat = inputNode?.inputFormat(forBus: 0) {
            inode.installTap(onBus: 0, bufferSize: 4800, format: inputFormat) { buffer, time in
                //print("Mic callback")
                DispatchQueue.main.async {
                    // Capture the audio buffer in real-time
                    self.micBuffer = buffer
                }
            }
        }
        try! audioEngine?.start()
    }
    
    func stop() {
        audioEngine?.stop()
        inputNode?.removeTap(onBus: 0)
    }
}

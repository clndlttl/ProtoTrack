//
//  AudioRecorderManager.swift
//  overdub
//
//  Created by Colin Fox on 10/10/24.
//

import AVFoundation
import SwiftUI

class AudioEngine: ObservableObject {
    private var audioEngine: AVAudioEngine!
    private var inputNode: AVAudioInputNode!
    @Published var micBuffer: AVAudioPCMBuffer?
    @Published var engineFinished: Bool
    
    init() {
        audioEngine = AVAudioEngine()
        inputNode = audioEngine.inputNode
        engineFinished = false
    }

    func start() {
        let inputFormat = inputNode.inputFormat(forBus: 0)

        inputNode.installTap(onBus: 0, bufferSize: 4800, format: inputFormat) { buffer, time in
            DispatchQueue.main.async {
                // Capture the audio buffer in real-time
                self.micBuffer = buffer
            }
        }

        try! audioEngine.start()
    }
    
    func stop() {
        audioEngine.stop()
        inputNode.removeTap(onBus: 0)
        engineFinished = true
    }
}

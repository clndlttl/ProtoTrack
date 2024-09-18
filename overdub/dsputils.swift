//
//  dsputils.swift
//  overdub
//
//  Created by Colin Fox on 9/17/24.
//

import Foundation
import AVFoundation
import Accelerate

// Function to read an audio file and return its PCM buffer
func readAudioFile(url: URL) -> AVAudioPCMBuffer? {
    let audioFile: AVAudioFile
    
    do {
        audioFile = try AVAudioFile(forReading: url)
    } catch {
        print("Error opening audio file: \(error)")
        return nil
    }

    let format = audioFile.processingFormat
    let frameCount = UInt32(audioFile.length)
    
    guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else {
        print("Error creating PCM buffer.")
        return nil
    }

    do {
        try audioFile.read(into: buffer)
    } catch {
        print("Error reading audio file: \(error)")
        return nil
    }
    
    return buffer
}

// Function to add two PCM buffers together using Accelerate
func addAudioBuffers(buffer1: AVAudioPCMBuffer, buffer2: AVAudioPCMBuffer) -> AVAudioPCMBuffer? {
    let frameCount = min(buffer1.frameLength, buffer2.frameLength)
    
    guard let format = AVAudioFormat(commonFormat: buffer1.format.commonFormat, sampleRate: buffer1.format.sampleRate, channels: buffer1.format.channelCount, interleaved: false) else {
        return nil
    }

    guard let outputBuffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else {
        return nil
    }

    // Get pointers to the raw float32 data in each buffer
    guard let buffer1Data = buffer1.floatChannelData,
          let buffer2Data = buffer2.floatChannelData,
          let outputData = outputBuffer.floatChannelData else {
        return nil
    }

    // Add audio samples together for each channel
    for channel in 0..<Int(buffer1.format.channelCount) {
        vDSP_vadd(buffer1Data[channel], 1, buffer2Data[channel], 1, outputData[channel], 1, vDSP_Length(frameCount))
        
        // Normalize to avoid clipping (optional, depending on desired outcome)
        var maxAmplitude: Float = 0
        vDSP_maxv(outputData[channel], 1, &maxAmplitude, vDSP_Length(frameCount))
        if maxAmplitude > 1.0 {
            var scale: Float = 1.0 / maxAmplitude
            vDSP_vsmul(outputData[channel], 1, &scale, outputData[channel], 1, vDSP_Length(frameCount))
        }
    }

    outputBuffer.frameLength = frameCount
    return outputBuffer
}

// Function to write a PCM buffer to an .m4a file
func writeAudioFile(buffer: AVAudioPCMBuffer, url: URL) {
    let format = buffer.format
    do {
        let audioFile = try AVAudioFile(forWriting: url, settings: format.settings, commonFormat: .pcmFormatFloat32, interleaved: false)
        try audioFile.write(from: buffer)
    } catch {
        print("Error writing audio file: \(error)")
    }
}

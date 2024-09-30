//
//  dsputils.swift
//  overdub
//
//  Created by Colin Fox on 9/17/24.
//

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

func removeFirstNFrames(from buffer: AVAudioPCMBuffer, numberOfFramesToRemove: AVAudioFrameCount) -> AVAudioPCMBuffer? {
    guard numberOfFramesToRemove < buffer.frameLength else {
        // If N is larger than the buffer length, return nil
        print("Cannot remove more frames than are available in the buffer.")
        return nil
    }
    
    let remainingFrames = buffer.frameLength - numberOfFramesToRemove
    
    // Create a new AVAudioPCMBuffer for the remaining frames
    guard let format = buffer.format as AVAudioFormat?,
          let newBuffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: remainingFrames) else {
        print("Failed to create new buffer.")
        return nil
    }
    
    newBuffer.frameLength = remainingFrames

    let numChannels = Int(buffer.format.channelCount)

    for channel in 0..<numChannels {
        if let sourceChannelData = buffer.floatChannelData?[channel],
           let destinationChannelData = newBuffer.floatChannelData?[channel] {
            // Copy from the N-th frame onward to the new buffer
            let sourcePointer = sourceChannelData.advanced(by: Int(numberOfFramesToRemove))
            vDSP_mmov(sourcePointer, destinationChannelData, vDSP_Length(remainingFrames), 1, 1, 1)
        }
    }
    
    return newBuffer
}

func prependZerosToBuffer(buffer: AVAudioPCMBuffer, zeroFrames: AVAudioFrameCount) -> AVAudioPCMBuffer? {
    guard let format = buffer.format as AVAudioFormat? else {
        print("Invalid buffer format")
        return nil
    }
    
    if zeroFrames == 0 {
        return buffer
    }

    let originalFrameCount = buffer.frameLength
    let totalFrameCount = originalFrameCount + zeroFrames
    let channelCount = Int(buffer.format.channelCount)
    
    // Create a new buffer with total frames (zeros + original audio)
    guard let newBuffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: totalFrameCount) else {
        print("Failed to create new buffer")
        return nil
    }
    
    // Set the frameLength of the new buffer to total frames
    newBuffer.frameLength = totalFrameCount

    for channel in 0..<channelCount {
        if let originalChannelData = buffer.floatChannelData?[channel],
           let newChannelData = newBuffer.floatChannelData?[channel] {
            vDSP_mmov(originalChannelData, newChannelData.advanced(by: Int(zeroFrames)), vDSP_Length(originalFrameCount), 1, 1, 1)
        }
    }
    
    return newBuffer
}


func appendZerosToBuffer(buffer: AVAudioPCMBuffer, zeroFrames: AVAudioFrameCount) -> AVAudioPCMBuffer? {
    guard let format = buffer.format as AVAudioFormat? else {
        print("Invalid buffer format")
        return nil
    }
    
    if zeroFrames == 0 {
        return buffer
    }

    let originalFrameCount = buffer.frameLength
    let totalFrameCount = originalFrameCount + zeroFrames
    let channelCount = Int(buffer.format.channelCount)
    
    // Create a new buffer with total frames (original audio + zeros)
    guard let newBuffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: totalFrameCount) else {
        print("Failed to create new buffer")
        return nil
    }
    
    // Set the frameLength of the new buffer to total frames
    newBuffer.frameLength = totalFrameCount

    for channel in 0..<channelCount {
        if let originalChannelData = buffer.floatChannelData?[channel],
           let newChannelData = newBuffer.floatChannelData?[channel] {
            vDSP_mmov(originalChannelData, newChannelData, vDSP_Length(originalFrameCount), 1, 1, 1)
        }
    }
    
    return newBuffer
}


// Function to add two PCM buffers together using Accelerate
func addAudioBuffers(baseUrl: URL, dubUrl: URL, atTime: TimeInterval, audioDelaySecs: TimeInterval = 0.1, doEchoCancellation: Bool = false) -> AVAudioPCMBuffer? {
    
    guard let base = readAudioFile(url: baseUrl), let dub = readAudioFile(url: dubUrl) else {
        print("Cannot read audio in addAudioBuffers()")
        return nil
    }
    
    // infer format from buffer1
    guard let format = AVAudioFormat(commonFormat: base.format.commonFormat, sampleRate: base.format.sampleRate, channels: base.format.channelCount, interleaved: false) else {
        return nil
    }
    
    // Since recording begins before playback, need to remove some frames from the dub
    let frameCorrection: Int = Int(round(format.sampleRate * audioDelaySecs))
    // expected frame offset
    let frameOffset: Int = Int(round(format.sampleRate * atTime))
    
    let numPrependToDub: Int = frameOffset - frameCorrection
    
    let prependedDubFrameCount = numPrependToDub + Int(dub.frameLength)

    guard prependedDubFrameCount > 0 else {
        print("Dub is too short!!!")
        return nil
    }
    
    let baseLen: Int = Int(base.frameLength)
    
    let endEchoTime: TimeInterval = baseLen > prependedDubFrameCount ? Double(prependedDubFrameCount) / format.sampleRate : Double(baseLen) / format.sampleRate
    
    // the endTime (for echo cancellation) is the min

    let numAppendToBase = prependedDubFrameCount > baseLen ? prependedDubFrameCount - baseLen : 0
    let numAppendToDub = baseLen > prependedDubFrameCount ? baseLen - prependedDubFrameCount : 0
    
    guard let dubPrepended = numPrependToDub >= 0 ? prependZerosToBuffer(buffer: dub, zeroFrames: AVAudioFrameCount(numPrependToDub)) :
            removeFirstNFrames(from: dub, numberOfFramesToRemove: AVAudioFrameCount(-numPrependToDub)) else {
        print("Cannot prepend to dub")
        return nil
    }
            
    guard let dubAppended = appendZerosToBuffer(buffer: dubPrepended, zeroFrames: AVAudioFrameCount(numAppendToDub)) else {
        print("Cannot append to dub")
        return nil
    }
    guard let baseAppended = appendZerosToBuffer(buffer: base, zeroFrames: AVAudioFrameCount(numAppendToBase)) else {
        print("Cannot append to base")
        return nil
    }
    
    let framesOut = max(baseAppended.frameLength, dubAppended.frameLength)
    
    guard let outputBuffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: framesOut) else {
        return nil
    }

    // Get pointers to the raw float32 data in each buffer
    guard let basePtr = baseAppended.floatChannelData,
          let dubPtr = dubAppended.floatChannelData,
          let outputPtr = outputBuffer.floatChannelData else {
        return nil
    }
    
    // Here's the magic...
    if doEchoCancellation {
        cancelEcho(basePtr, dubPtr, atTime, endEchoTime) // Must process dubData in-place
    }

    // Add audio samples together for each channel
    for channel in 0..<Int(base.format.channelCount) {
        vDSP_vadd(basePtr[channel], 1, dubPtr[channel], 1, outputPtr[channel], 1, vDSP_Length(framesOut))
        
        // Normalize to avoid clipping (optional, depending on desired outcome)
        var maxAmplitude: Float = 0
        vDSP_maxv(outputPtr[channel], 1, &maxAmplitude, vDSP_Length(framesOut))
        if maxAmplitude > 1.0 {
            var scale: Float = 1.0 / maxAmplitude
            vDSP_vsmul(outputPtr[channel], 1, &scale, outputPtr[channel], 1, vDSP_Length(framesOut))
        }
    }

    outputBuffer.frameLength = framesOut
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

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
            let destinationPointer = destinationChannelData
            vDSP_mmov(sourcePointer, destinationPointer, vDSP_Length(remainingFrames), 1, vDSP_Length(remainingFrames), 1)
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
            
            // Prepend zeroes using Accelerate
            vDSP_vclr(newChannelData, 1, vDSP_Length(zeroFrames))
            
            // Copy the original buffer data into the new buffer after the zeros
            cblas_scopy(Int32(Int(originalFrameCount)), originalChannelData, 1, newChannelData.advanced(by: Int(zeroFrames)), 1)
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
            
            // Copy the original buffer data into the new buffer first
            cblas_scopy(Int32(Int(originalFrameCount)), originalChannelData, 1, newChannelData, 1)
            
            // Append zeroes using Accelerate
            vDSP_vclr(newChannelData.advanced(by: Int(originalFrameCount)), 1, vDSP_Length(zeroFrames))
        }
    }
    
    return newBuffer
}


// Function to add two PCM buffers together using Accelerate
func addAudioBuffers(baseUrl: URL, dubUrl: URL, offset: TimeInterval) -> AVAudioPCMBuffer? {
    
    guard let base = readAudioFile(url: baseUrl), let dub = readAudioFile(url: dubUrl) else {
        print("Cannot read audio in addAudioBuffers()")
        return nil
    }
    
    // infer format from buffer1
    guard let format = AVAudioFormat(commonFormat: base.format.commonFormat, sampleRate: base.format.sampleRate, channels: base.format.channelCount, interleaved: false) else {
        return nil
    }
    
    // First apply time correction, then prepend zeros to dub. Then, append zeros either to base or dub.
    let frameCorrection: UInt32 = UInt32(round(format.sampleRate * 0.1)) // sampleRate * delay (about 0.1 sec)
    
    let numPrependToDub: UInt32 = UInt32(round(format.sampleRate * offset))
    let adjustedDubFrameCount = numPrependToDub + dub.frameLength
    
    let numAppendToBase = adjustedDubFrameCount > base.frameLength ? adjustedDubFrameCount - base.frameLength : 0
    let numAppendToDub = base.frameLength > adjustedDubFrameCount ? base.frameLength - adjustedDubFrameCount : 0
    
    guard let dubCorrected = removeFirstNFrames(from: dub, numberOfFramesToRemove: frameCorrection) else {
        print("Cannot apply frame correction")
        return nil
    }
    
    guard let dubPad = prependZerosToBuffer(buffer: dubCorrected, zeroFrames: numPrependToDub) else {
        print("Cannot prepend to dub")
        return nil
    }
    guard let dubPad2 = appendZerosToBuffer(buffer: dubPad, zeroFrames: numAppendToDub) else {
        print("Cannot append to dub")
        return nil
    }
    guard let basePad = appendZerosToBuffer(buffer: base, zeroFrames: numAppendToBase) else {
        print("Cannot append to base")
        return nil
    }
    
    let framesOut = max(basePad.frameLength, dubPad2.frameLength)
    
    guard let outputBuffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: framesOut) else {
        return nil
    }

    // Get pointers to the raw float32 data in each buffer
    guard let buffer1Data = basePad.floatChannelData,
          let buffer2Data = dubPad2.floatChannelData,
          let outputData = outputBuffer.floatChannelData else {
        return nil
    }

    // Add audio samples together for each channel
    for channel in 0..<Int(base.format.channelCount) {
        vDSP_vadd(buffer1Data[channel], 1, buffer2Data[channel], 1, outputData[channel], 1, vDSP_Length(framesOut))
        
        // Normalize to avoid clipping (optional, depending on desired outcome)
        var maxAmplitude: Float = 0
        vDSP_maxv(outputData[channel], 1, &maxAmplitude, vDSP_Length(framesOut))
        if maxAmplitude > 1.0 {
            var scale: Float = 1.0 / maxAmplitude
            vDSP_vsmul(outputData[channel], 1, &scale, outputData[channel], 1, vDSP_Length(framesOut))
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

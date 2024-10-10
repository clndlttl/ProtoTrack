//
//  EchoCanceller.swift
//  overdub
//
//  Created by Colin Fox on 9/26/24.
//

import AVFoundation
import Accelerate

func cancelEcho(driver: AVAudioPCMBuffer, mic: AVAudioPCMBuffer, transferFunction: DSPSplitComplex?, startTime: TimeInterval, endTime: TimeInterval) {
    
    print("cancelEcho")
    
    // Get pointers to the raw float32 data in each buffer
    guard let driverPtr = driver.floatChannelData?[0],
          let micPtr = mic.floatChannelData?[0]
        else {
        return
    }
    
    guard let H = transferFunction else {
        print("No Transfer Function; exit cancelEcho")
        return
    }
    
    let firstIdx: Int = Int(round(driver.format.sampleRate * startTime))
    let lastIdx: Int = Int(round(driver.format.sampleRate * endTime))
    
    let totalSamples = lastIdx - firstIdx
    let N: Int = 10001 // use odd
    let ovlp: Int = (N + 1) / 2
    let L: Int = N - ovlp
    let numSteps: Int = 1 + (totalSamples - N) / L
    
    let nfft = getFFTLength(frameCount: N)
    let NFFT: Int = nfft.nbins
    
    print("blockLen = \(N), stepSize = \(L), numSteps = \(numSteps), nbins = \(NFFT)")
    
    guard let setup = getFFTSetup(log2n: nfft.log2n) else {
        return
    }
    
    var x = [Float](repeating: 0.0, count: N)
    var y = [Float](repeating: 0.0, count: N)
    
    let X = getNewComplexBuffer(len: N, initialize: false)
    let Y = getNewComplexBuffer(len: N, initialize: false)
    
    let ifftBuffer = getNewComplexBuffer(len: NFFT, initialize: true)
    
    let window = UnsafeMutablePointer<Float>.allocate(capacity: N)
    // Create the Hamming window
    vDSP_hann_window(window, vDSP_Length(N), 2)
    
    for i in 0..<numSteps {
        
        memcpy(&x, driverPtr.advanced(by: firstIdx + i*L), N * MemoryLayout<Float>.size)
        vDSP_vmul(x, 1, window, 1, &x, 1, vDSP_Length(N))
        
        memcpy(&y, micPtr.advanced(by: firstIdx + i*L), N * MemoryLayout<Float>.size)
        vDSP_vmul(y, 1, window, 1, &y, 1, vDSP_Length(N))
        
        
        withUnsafePointer(to: X) { X in
            withUnsafePointer(to: Y) { Y in
                doFFT(inp: x, outp: X, frameCount: N, setup: setup)
                doFFT(inp: y, outp: Y, frameCount: N, setup: setup)
//                withUnsafePointer(to: H) { H in
//                    // Put H*X back into X
//                    vDSP_zvmul(X, 1, H, 1, X, 1, vDSP_Length(nfft.nbins), 0)
//                }
            }
        }
        
        // Strip off the echo
        //vDSP_zvsub(&Y, 1, &X, 1, &Y, 1, vDSP_Length(len.nbins))
        
        withUnsafePointer(to: Y) { Y in
            withUnsafePointer(to: ifftBuffer) { B in
                vDSP_fft_zop(setup, Y, 1, B, 1, vDSP_Length(nfft.log2n), FFTDirection(kFFTDirection_Inverse))
            }
        }
        
        //var gain: Float = 1.0
        //vDSP_vsmul(ifftBuffer.realp, 1, &gain, ifftBuffer.realp, 1, vDSP_Length(N))
        
        // synthesis window
        vDSP_vmul(ifftBuffer.realp, 1, window, 1, ifftBuffer.realp, 1, vDSP_Length(N))
        
        // write this right back to mic
        memcpy(micPtr.advanced(by: firstIdx + i*L), ifftBuffer.realp, N * MemoryLayout<Float>.size)
    }
    
    window.deallocate()
}


// Function to add two PCM buffers together using Accelerate
func addAudioBuffers(baseUrl: URL, dubUrl: URL, atTime: TimeInterval, transferFunction: DSPSplitComplex?,
                     doEchoCancellation: Bool = true, debug: Bool = false) -> AVAudioPCMBuffer? {
    
    guard let base = readAudioFile(url: baseUrl),
          let dub = readAudioFile(url: dubUrl) else {
        print("Cannot read audio in addAudioBuffers()")
        return nil
    }
        
    // infer format from buffer1
    guard let format = AVAudioFormat(commonFormat: base.format.commonFormat, sampleRate: base.format.sampleRate, channels: base.format.channelCount, interleaved: false) else {
        return nil
    }
    
    // num to cutoff from the begininning of the dub
    let correction: Int = Int(round(format.sampleRate * 0.05))
    
    // expected frame offset
    let numPrependToDub: Int = Int(round(format.sampleRate * atTime)) - correction
    print("atTime: \(atTime), prepending \(numPrependToDub) zeros")
        
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
        
    guard let dubAligned = appendZerosToBuffer(buffer: dubPrepended, zeroFrames: AVAudioFrameCount(numAppendToDub)) else {
        print("Cannot append to dub")
        return nil
    }
    guard let baseAligned = appendZerosToBuffer(buffer: base, zeroFrames: AVAudioFrameCount(numAppendToBase)) else {
        print("Cannot append to base")
        return nil
    }
        
    let framesOut = max(baseAligned.frameLength, dubAligned.frameLength)
        
    guard let outputBuffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: framesOut) else {
        return nil
    }
        
    // Here's the magic...
    if doEchoCancellation {
        cancelEcho(driver: baseAligned, mic: dubAligned, transferFunction: transferFunction, startTime: atTime, endTime: endEchoTime) // Must process dub in-place
    }
        
    // Get pointers to the raw float32 data in each buffer
    guard let driverPtr = baseAligned.floatChannelData?[0],
          let micPtr = dubAligned.floatChannelData?[0],
          let outPtr = outputBuffer.floatChannelData?[0]
        else {
        return nil
    }
    
    if debug {
        // Let's hear the mic signal only
        print("Isolating microphone.")
        //vDSP_mmov(micPtr, outPtr, vDSP_Length(framesOut), 1, 1, 1)
        memcpy(outPtr, micPtr, Int(framesOut) * MemoryLayout<Float>.size)
    }
    else {
        // Add audio samples together
        print("Adding dub to base.")
        vDSP_vadd(driverPtr, 1, micPtr, 1, outPtr, 1, vDSP_Length(framesOut))
    }
        
    // Normalize to avoid clipping (optional, depending on desired outcome)
    var maxAmplitude: Float = 0
    vDSP_maxv(outPtr, 1, &maxAmplitude, vDSP_Length(framesOut))
    if maxAmplitude > 1.0 {
        print("Avoiding clipping!")
        var scale: Float = 1.0 / maxAmplitude
        vDSP_vsmul(outPtr, 1, &scale, outPtr, 1, vDSP_Length(framesOut))
    }
        
    outputBuffer.frameLength = framesOut
    return outputBuffer
}



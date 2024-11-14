//
//  dsputils.swift
//  overdub
//
//  Created by Colin Fox on 9/17/24.
//

import AVFoundation
import Accelerate




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
            //vDSP_mmov(sourcePointer, destinationChannelData, vDSP_Length(remainingFrames), 1, 1, 1)
            memcpy(destinationChannelData, sourcePointer, Int(remainingFrames) * MemoryLayout<Float>.size)
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
            //vDSP_mmov(originalChannelData, newChannelData.advanced(by: Int(zeroFrames)), vDSP_Length(originalFrameCount), 1, 1, 1)
            memcpy(newChannelData.advanced(by: Int(zeroFrames)), originalChannelData, Int(originalFrameCount) * MemoryLayout<Float>.size )
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
            //vDSP_mmov(originalChannelData, newChannelData, vDSP_Length(originalFrameCount), 1, 1, 1)
            memcpy(newChannelData, originalChannelData, Int(originalFrameCount) * MemoryLayout<Float>.size)
        }
    }
    
    return newBuffer
}

func getNewComplexBuffer(len: Int, initialize: Bool) -> DSPSplitComplex {
    
    // Allocate memory for the real and imaginary parts
    let realPointer = UnsafeMutablePointer<Float>.allocate(capacity: len)
    let imagPointer = UnsafeMutablePointer<Float>.allocate(capacity: len)
    
    // Initialize DSPSplitComplex with allocated real and imaginary pointers
    let cmplxPointer = DSPSplitComplex(realp: realPointer, imagp: imagPointer)
    
    if initialize {
        // Initialize the real and imaginary parts to 0.0
        realPointer.initialize(repeating: 0.0, count: len)
        imagPointer.initialize(repeating: 0.0, count: len)
    }
    
    return cmplxPointer
}

func serializeDSPSplitComplex(_ cmplx: DSPSplitComplex, count: Int) -> Data {
    // Calculate the size of the real and imaginary parts
    let realpSize = count * MemoryLayout<Float>.size
    let imagpSize = count * MemoryLayout<Float>.size

    // Allocate memory to hold both realp and imagp values
    var data = Data(capacity: realpSize + imagpSize)

    // Copy the realp and imagp into the Data object
    // Append realp memory to the Data object
    data.append(UnsafeBufferPointer(start: cmplx.realp, count: count))
        
    // Append imagp memory to the Data object
    data.append(UnsafeBufferPointer(start: cmplx.imagp, count: count))
        
    return data
}

func deserializeDSPSplitComplex(_ data: Data, count: Int) -> DSPSplitComplex? {
    let realpSize = count * MemoryLayout<Float>.size
    let imagpSize = count * MemoryLayout<Float>.size

    // Ensure the data size is correct
    guard data.count == realpSize + imagpSize else { return nil }

    // Allocate memory for realp and imagp
    let realp = UnsafeMutablePointer<Float>.allocate(capacity: count)
    let imagp = UnsafeMutablePointer<Float>.allocate(capacity: count)

    // Copy data into the allocated memory for realp
    data.copyBytes(to: UnsafeMutableBufferPointer(start: realp, count: count), from: 0..<realpSize)

    // Copy data into the allocated memory for imagp
    data.copyBytes(to: UnsafeMutableBufferPointer(start: imagp, count: count), from: realpSize..<realpSize+imagpSize)

    // Create and return DSPSplitComplex
    return DSPSplitComplex(realp: realp, imagp: imagp)
}

//func gccPhat(x: DSPSplitComplex, y: DSPSplitComplex, nbins: Int) -> DSPSplitComplex {
//    
//    // (a + jb)(c + jd) = (ac + bd) + j(bc + ad)
//    //                    ----------------------
//    //                    sqrt(re^2 + im^2)
//    
//    withUnsafePointer(to: x) { xp in
//        withUnsafePointer(to: y) { yp in
//            
//            let outRealp = UnsafeMutablePointer<Float>.allocate(capacity: nbins)
//            let outImagp = UnsafeMutablePointer<Float>.allocate(capacity: nbins)
//            var output = DSPSplitComplex(realp: outRealp, imagp: outImagp)
//            vDSP_zvmul(xp, 1, yp, 1, &output, 1, vDSP_Length(nbins), -1) // -1 means conjugate x
//            
//            let magnitude = UnsafeMutablePointer<Float>.allocate(capacity: nbins)
//            vDSP_zvabs(&output, 1, magnitude, 1, vDSP_Length(nbins))
//        
//            vDSP_vdiv(output.realp, 1, magnitude, 1, output.realp, 1, vDSP_Length(nbins))
//            vDSP_vdiv(output.imagp, 1, magnitude, 1, output.imagp, 1, vDSP_Length(nbins))
//            
//            magnitude.deallocate()
//            return output
//        }
//    }
//    
//}

//func estimateLagInSec(stim: AVAudioPCMBuffer, resp: AVAudioPCMBuffer) -> TimeInterval? {
//    
//    var lag: TimeInterval?
//    
//    guard let stimPtr = stim.floatChannelData?[0],
//          let respPtr = resp.floatChannelData?[0] else {
//        print("Cannot get data from stim/resp")
//        return lag
//    }
//   
//    let totalSamples = Int(min(stim.frameLength, resp.frameLength))
//    
//    // Chunk through both arrays in block sizes wide enough to capture lag
//    let blockLen: Int = Int(stim.format.sampleRate * 0.2)
//    let stepSize: Int = Int(Float(blockLen) * 0.2) // cannot be 0.0!
//    let numSteps: Int = 1 + (totalSamples - blockLen) / stepSize
//    
//    // Get the size of the fft
//    let len = getFFTLength(frameCount: blockLen)
//    
//    print("blockLen = \(blockLen), stepSize = \(stepSize), numSteps = \(numSteps), nbins = \(len.nbins)")
//    
//    guard let setup = getFFTSetup(log2n: len.log2n) else {
//        print("Bad fftSetup")
//        return lag
//    }
//    
//    // accumulate correlations
//    var accumBuffer = getNewComplexBuffer(len: len.nbins, initialize: true)
//    
//    var x = [Float](repeating: 0.0, count: blockLen)
//    var y = [Float](repeating: 0.0, count: blockLen)
//
//    for i in 0..<numSteps {
//        
//        //vDSP_mmov(&stimPtr[i*stepSize], &x, vDSP_Length(blockLen), 1, 1, 1)
//        memcpy(&x, stimPtr.advanced(by: i*stepSize), blockLen * MemoryLayout<Float>.size)
//        subtractMeanInPlace(buffer: &x, nsamp: blockLen)
//        applyWindowInPlace(buffer: &x, nsamp: blockLen)
//        
//        //vDSP_mmov(&respPtr[i*stepSize], &y, vDSP_Length(blockLen), 1, 1, 1)
//        memcpy(&y, respPtr.advanced(by: i*stepSize), blockLen * MemoryLayout<Float>.size)
//        subtractMeanInPlace(buffer: &y, nsamp: blockLen)
//        applyWindowInPlace(buffer: &y, nsamp: blockLen)
//
//        guard let X = doFFT(on: &x, frameCount: blockLen, setup: setup),
//              let Y = doFFT(on: &y, frameCount: blockLen, setup: setup) else {
//            return lag
//        }
//        
//        var correlation = gccPhat(x: X, y: Y, nbins: len.nbins)
//        vDSP_zvadd(&accumBuffer, 1, &correlation, 1, &accumBuffer, 1, vDSP_Length(len.nbins))
//    }
//    
//    var fChunks: Float = 1.0 / Float(numSteps)
//    vDSP_vsmul(accumBuffer.realp, 1, &fChunks, accumBuffer.realp, 1, vDSP_Length(len.nbins))
//    vDSP_vsmul(accumBuffer.imagp, 1, &fChunks, accumBuffer.imagp, 1, vDSP_Length(len.nbins))
//
//    var ifftBuffer = getNewComplexBuffer(len: len.nbins, initialize: true)
//
//    // Perform inverse FFT
//    vDSP_fft_zop(setup, &accumBuffer, 1, &ifftBuffer, 1, vDSP_Length(len.log2n), FFTDirection(kFFTDirection_Inverse))
//    
//    print("ifft.realp[0] = \(ifftBuffer.realp[0]), ifft.imagp[1] = \(ifftBuffer.imagp[1])")
//    
//    // Now we find the peak
//    // Find the maximum value and its index
//    var maxValue: Float = 0.0
//    var maxIndex: vDSP_Length = 0
//    vDSP_maxvi(ifftBuffer.realp, 1, &maxValue, &maxIndex, vDSP_Length(blockLen))
//    
//    print("maxValue = \(maxValue), maxIndex = \(maxIndex)")
//    
//    lag = Double(maxIndex) / stim.format.sampleRate
//    
//    vDSP_destroy_fftsetup(setup)
//    return lag
//}

func estimateTransferFunction(stim: AVAudioPCMBuffer, resp: AVAudioPCMBuffer) -> DSPSplitComplex? {
    
    guard let stimPtr = stim.floatChannelData?[0],
          let respPtr = resp.floatChannelData?[0] else {
        print("Cannot get data from stim/resp")
        return nil
    }
   
    let totalSamples = Int(min(stim.frameLength, resp.frameLength))
    
    // Chunk through both arrays in block sizes wide enough to capture lag
    // N = L + ovlp
    let N: Int = 512
    let L: Int = N / 2 // number of new samples
    let numSteps: Int = 1 + (totalSamples - N) / L
    
    // Get the size of the fft
    let nfft = getFFTLength(frameCount: N)
    
    print("blockLen = \(N), stepSize = \(L), numSteps = \(numSteps), nbins = \(nfft.nbins)")
    
    guard let setup = getFFTSetup(log2n: nfft.log2n) else {
        print("Bad fftSetup")
        return nil
    }
    
    let window = UnsafeMutablePointer<Float>.allocate(capacity: N)
    vDSP_hann_window(window, vDSP_Length(N), 2)
   
    var x = [Float](repeating: 0.0, count: N)
    var y = [Float](repeating: 0.0, count: N)
    
    let X = getNewComplexBuffer(len: nfft.nbins, initialize: false)
    let Y = getNewComplexBuffer(len: nfft.nbins, initialize: false)

    let H = getNewComplexBuffer(len: nfft.nbins, initialize: false)
    let HAccum = getNewComplexBuffer(len: nfft.nbins, initialize: true)
    
    for i in 0..<numSteps {
        
        memcpy(&x, stimPtr.advanced(by: i*L), N * MemoryLayout<Float>.size)
        vDSP_vmul(x, 1, window, 1, &x, 1, vDSP_Length(N))
        
        memcpy(&y, respPtr.advanced(by: i*L), N * MemoryLayout<Float>.size)
        vDSP_vmul(y, 1, window, 1, &y, 1, vDSP_Length(N))

        
        //vDSP_zvmul(&X, 1, &Y, 1, &numerator, 1, vDSP_Length(len.nbins), -1) // conj X
        //vDSP_zvmul(&X, 1, &X, 1, &denominator, 1, vDSP_Length(len.nbins), -1)
        withUnsafePointer(to: X) { X in
            withUnsafePointer(to: Y) { Y in
                doFFT(inp: x, outp: X, frameCount: N, setup: setup)
                doFFT(inp: y, outp: Y, frameCount: N, setup: setup)
                withUnsafePointer(to: H) { H in
                    // H = Y / X
                    vDSP_zvdiv(X, 1, Y, 1, H, 1, vDSP_Length(nfft.nbins))
                    withUnsafePointer(to: HAccum) { Haccum in
                        vDSP_zvadd(H, 1, Haccum, 1, Haccum, 1, vDSP_Length(nfft.nbins))
                    }
                }
            }
        }
        
        if H.realp[L].isNaN {
            print("iter \(i): H[L] is nan; X[L] = \(X.realp[L]) + j\(X.imagp[L]); Y[32] = \(Y.realp[L]) + j\(Y.imagp[L])" )
        }
    }
    
    var scale: Float = 1.0 / Float(numSteps)
    vDSP_vsmul(HAccum.realp, 1, &scale, HAccum.realp, 1, vDSP_Length(nfft.nbins))
    vDSP_vsmul(HAccum.imagp, 1, &scale, HAccum.imagp, 1, vDSP_Length(nfft.nbins))
    
    // print out ALL values
//    for i in 0..<nfft.nbins {
//        print("H_\(i): \(HAccum.realp[i]), \(HAccum.imagp[i])")
//    }
    
    vDSP_destroy_fftsetup(setup)
    X.realp.deallocate()
    X.imagp.deallocate()
    
    Y.realp.deallocate()
    Y.imagp.deallocate()
    
    H.realp.deallocate()
    H.imagp.deallocate()
    
    return HAccum
}

func getFFTLength(frameCount: Int) -> (nbins: Int, log2n: Float) {
    let log2n = ceil(log2(Float(frameCount)))
    let fftLength = Int(pow(2.0, log2n))
    return (nbins: fftLength, log2n: log2n)
}

func getFFTSetup(log2n: Float) -> FFTSetup? {
    guard let fftSetup = vDSP_create_fftsetup(vDSP_Length(log2n), FFTRadix(kFFTRadix2)) else {
        return nil
    }
    return fftSetup
}

func subtractMeanInPlace(buffer: UnsafeMutablePointer<Float>, nsamp: Int) {
    var mean: Float = 0.0
    vDSP_meanv(buffer, 1, &mean, vDSP_Length(nsamp))
    mean *= -1
    vDSP_vsadd(buffer, 1, &mean, buffer, 1, vDSP_Length(nsamp))
}

func applyWindowInPlace(buffer: UnsafeMutablePointer<Float>, nsamp: Int) {
    // Create an array to hold the Hamming window
    let window = UnsafeMutablePointer<Float>.allocate(capacity: nsamp)

    // Create the Hamming window
    vDSP_hann_window(window, vDSP_Length(nsamp), 2)

    // Apply the window (element-wise multiplication)
    vDSP_vmul(buffer, 1, window, 1, buffer, 1, vDSP_Length(nsamp))
    
    window.deallocate()
}

func doFFT(inp: UnsafePointer<Float>, outp: UnsafePointer<DSPSplitComplex>, frameCount: Int, setup: FFTSetup) {
    
    let len = getFFTLength(frameCount: frameCount)
    
    let input = getNewComplexBuffer(len: len.nbins, initialize: true)
    
    memcpy(input.realp, inp, frameCount * MemoryLayout<Float>.size) // automatically zero-pads
    
    // Perform forward FFT
    withUnsafePointer(to: input) { pIn in
        vDSP_fft_zop(setup, pIn, 1, outp, 1, vDSP_Length(len.log2n), FFTDirection(kFFTDirection_Forward))
    }
    
    var scale: Float = 1.0 / Float(len.nbins)
    vDSP_vsmul(outp.pointee.realp, 1, &scale, outp.pointee.realp, 1, vDSP_Length(len.nbins))
    vDSP_vsmul(outp.pointee.imagp, 1, &scale, outp.pointee.imagp, 1, vDSP_Length(len.nbins))

    // Calculate magnitude from real and imaginary parts
    //var magnitudes = [Float](repeating: 0.0, count: len.nbins)
    //vDSP_zvmags(&fftBuffer, 1, &magnitudes, 1, vDSP_Length(len.nbins))
    //print("FFT Magnitudes: \(magnitudes)")

    // Cleanup
    input.realp.deallocate()
    input.imagp.deallocate()
    
}
func getImpulseResponse(inp: UnsafePointer<DSPSplitComplex>, outp: UnsafeMutablePointer<Float>, nBinsIn: Int, nSampOut: Int) {
    
    print("Enter getImpulseResponse")
    print("DC bin: \(inp.pointee.realp[0]) + j\(inp.pointee.imagp[0])")
    
    inp.pointee.realp[0] = 0.0
    
    let nfft = getFFTLength(frameCount: nBinsIn)
    
    let samplesOut: Int = min(nSampOut, nBinsIn)
    
    guard let setup = getFFTSetup(log2n: nfft.log2n) else {
        print("Bad fftSetup")
        return
    }
    
    let ifft = getNewComplexBuffer(len: nfft.nbins, initialize: true)
    
    // Perform inverse FFT
    withUnsafePointer(to: ifft) { f in
        vDSP_fft_zop(setup, inp, 1, f, 1, vDSP_Length(nfft.log2n), FFTDirection(kFFTDirection_Inverse))
    }
    
    // normalize
    var maxval: Float = 0.0
    vDSP_maxv(ifft.realp, 1, &maxval, vDSP_Length(samplesOut))
    var minval: Float = 0.0
    vDSP_minv(ifft.realp, 1, &minval, vDSP_Length(samplesOut))
    print("maxval = \(maxval), minval = \(minval)")
    
    let norm: Float = max(abs(maxval), abs(minval))
    
    if norm != 0.0 {
        print("Normalize impulse response by = \(norm)")
        withUnsafePointer(to: norm) { n in
            vDSP_vsdiv(ifft.realp, 1, n, ifft.realp, 1, vDSP_Length(samplesOut))
        }
    }
    
    memcpy(outp, ifft.realp, samplesOut * MemoryLayout<Float>.size)
    
    vDSP_destroy_fftsetup(setup)
    ifft.realp.deallocate()
    ifft.imagp.deallocate()

}

// Function to add two PCM buffers together using Accelerate
func addAudioBuffers(baseUrl: URL, dubUrl: URL, atTime: TimeInterval) -> AVAudioPCMBuffer? {
    
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
        
    //let endEchoTime: TimeInterval = baseLen > prependedDubFrameCount ? Double(prependedDubFrameCount) / format.sampleRate : Double(baseLen) / format.sampleRate
        
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
    //cancelEcho(driver: baseAligned, mic: dubAligned, transferFunction: transferFunction, startTime: atTime, endTime: endEchoTime) // Must process dub in-place
        
    // Get pointers to the raw float32 data in each buffer
    guard let driverPtr = baseAligned.floatChannelData?[0],
          let micPtr = dubAligned.floatChannelData?[0],
          let outPtr = outputBuffer.floatChannelData?[0]
        else {
        return nil
    }
    
    // Add audio samples together
    vDSP_vadd(driverPtr, 1, micPtr, 1, outPtr, 1, vDSP_Length(framesOut))
        
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

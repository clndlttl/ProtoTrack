//
//  EchoCanceller.swift
//  overdub
//
//  Created by Colin Fox on 9/26/24.
//

import AVFoundation
import Accelerate

func performFFT(on ptr: UnsafePointer<UnsafeMutablePointer<Float>>, frameCount: Int) {

    let log2n = ceil(log2(Float(frameCount)))
    print("log2n = \(log2n)")
    
    let fftLength = Int(pow(2.0, log2n))
    print("fftLength = \(fftLength)")
    
    // Create FFT setup
    guard let fftSetup = vDSP_create_fftsetup(vDSP_Length(log2n), FFTRadix(kFFTRadix2)) else {
        fatalError("Cannot create FFT setup.")
    }

    // Allocate memory for the complex buffer (real and imaginary parts)
    var realp = [Float](repeating: 0.0, count: fftLength)
    var imagp = [Float](repeating: 0.0, count: fftLength)
    var fftRealp = [Float](repeating: 0.0, count: fftLength)
    var fftImagp = [Float](repeating: 0.0, count: fftLength)
    

    vDSP_mmov(ptr[0], &realp, vDSP_Length(frameCount), 1, 1, 1) // automatically zero pads
    
    var complexBuffer = DSPSplitComplex(realp: &realp, imagp: &imagp)
    var fftBuffer = DSPSplitComplex(realp: &fftRealp, imagp: &fftImagp)

    print("realp: \(realp)")
    print("imagp: \(imagp)")
    // Perform in-place forward FFT
    vDSP_fft_zop(fftSetup, &complexBuffer, 1, &fftBuffer, 1, vDSP_Length(log2n), FFTDirection(kFFTDirection_Forward))

    print("fftRealp: \(fftRealp)")
    print("fftImagp: \(fftImagp)")
    // Now complexBuffer contains the FFT result in realp and imagp
    // You can calculate the magnitude or phase if needed
    
    // Calculate magnitude from real and imaginary parts
    var magnitudes = [Float](repeating: 0.0, count: fftLength)
    vDSP_zvmags(&fftBuffer, 1, &magnitudes, 1, vDSP_Length(fftLength))
    
    // Output or process magnitudes
    //print("FFT Magnitudes: \(magnitudes)")
    
    // Convert to decibels
    //var normalizedMagnitudes = [Float](repeating: 0.0, count: frameCount)
    //vDSP_vdbcon(magnitudes, 1, [Float(1.0)], &normalizedMagnitudes, 1, vDSP_Length(frameCount), 1)
    //print("FFT Norm Magnitudes: \(normalizedMagnitudes)")

    // Cleanup
    vDSP_destroy_fftsetup(fftSetup)
    
}

func cancelEcho(_ driverData: UnsafePointer<UnsafeMutablePointer<Float>>, _ micData: UnsafePointer<UnsafeMutablePointer<Float>>, _ startTime: TimeInterval, _ endTime: TimeInterval) {
    
    print("TODO: cancelEcho")
    
    performFFT(on: micData, frameCount: 10)
    
}


//
//  CircularBuffer.swift
//  overdub
//
//  Created by Colin Fox on 10/26/24.
//

import AVFoundation
import Accelerate

class CircularBuffer: ObservableObject {
    private var circBuf: [Float]?
    private var unwrappedBuf: [Float]?

    @Published var ready: Bool!

    private var buflen: Int = 0
    private var rwPointer: Int = 0
    
    private var noiseFloorInDB: Float = -80
    
    func setSize(width: Int) {
        ready = false
        buflen = width
        rwPointer = 0
        circBuf = [Float](repeating: noiseFloorInDB, count: width)
        unwrappedBuf = [Float](repeating: noiseFloorInDB, count: width)
    }
    
    func write(_ buffer: AVAudioPCMBuffer) {
        let N = Int(buffer.frameLength)
        
        // We want to squash the incoming signal
        let deciLen: Int = 16

        var sumOfSquares = [Float](repeating: 0.0, count: deciLen)
        
        guard let data = buffer.floatChannelData?[0] else {
            print("Cannot get mic data")
            return
        }
        
        let framesPerBin = N / deciLen
        
        for i in 0..<deciLen {
            vDSP_svesq(&data[i*framesPerBin], 1, &sumOfSquares[i], vDSP_Length(framesPerBin))
        }
        
        // normalize
        var norm: Float = pow( Float(framesPerBin), -1 )
        vDSP_vsmul(sumOfSquares, 1, &norm, &sumOfSquares, 1, vDSP_Length(deciLen))
        
        var localMin: Float = 0
        
        for i in 0..<deciLen {
            var db = 10.0 * log10( sumOfSquares[i] )
            if db.isFinite {
                localMin = min(localMin, db)
            } else {
                db = noiseFloorInDB
            }
            circBuf![ (rwPointer + i) % buflen ] = db
        }
        
        if localMin < -40 {
            noiseFloorInDB = noiseFloorInDB * 0.975 + localMin * 0.025
        }
        
        rwPointer = (rwPointer + deciLen) % buflen
        
        for i in 0..<buflen {
            unwrappedBuf![i] = circBuf![ (rwPointer + i) % buflen ]
        }
        
        self.ready = true
    }
    
    func read() -> [Float] {
        return self.unwrappedBuf!
    }
    
    func getNoiseFloorInDB() -> Float {
        noiseFloorInDB
    }
 
    func clear() {
        rwPointer = 0
        var dB: Float = -80
        vDSP_vfill(&dB, &circBuf!, 1, vDSP_Length(buflen))
        vDSP_vfill(&dB, &unwrappedBuf!, 1, vDSP_Length(buflen))
        self.ready = true
    }
}

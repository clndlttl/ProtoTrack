//
//  ContentView.swift
//  overdub
//
//  Created by Colin Fox on 9/12/24.
//

import SwiftUI
import AVFoundation
import Accelerate

enum AppState {
    case STOP
    case PLAY
    case RECORD
    case CALIBRATE
}

// Helper function to get the path to the app's documents directory
func getDocumentsDirectory() -> URL {
    let paths = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)
    return paths[0]
}

struct EnvelopeView: View {
    @Binding var envelope: [Float]?

    var body: some View {
        Canvas { context, size in
            print("Redrawing waveform!!!")
            let midY = size.height / 2.0
            if let env = self.envelope {
                for (idx, point) in env.enumerated() {
                    var linePath = Path()
                    linePath.move(to: CGPoint(x: CGFloat(idx), y: midY*(1.0+CGFloat(point))))
                    linePath.addLine(to: CGPoint(x: CGFloat(idx), y: midY*(1.0-CGFloat(point))))
                    context.stroke(linePath, with: .color(.teal))
                }
            }
        }
    }
}

struct LiveView: View {
    @Binding var liveview: [Float]?

    var body: some View {
        Canvas { context, size in
            print("Redrawing liveview!!!")
            let midY = size.height / 2.0
            if let env = self.liveview {
                for (idx, point) in env.enumerated() {
                    var linePath = Path()
                    linePath.move(to: CGPoint(x: CGFloat(idx), y: midY*(1.0-CGFloat(point))))
                    linePath.addLine(to: CGPoint(x: CGFloat(idx), y: midY))
                    context.stroke(linePath, with: .color(.teal))
                }
            }
        }
    }
}

struct ContentView: View {

    @State private var state: AppState = .STOP
    @State private var trackExists: Bool = false
    
    @State private var playhead: TimeInterval = 0.0
    @State private var previousPlayhead: TimeInterval = 0.0
    @State private var duration: TimeInterval = 0.0
    
    @State private var audioRecorder: AVAudioRecorder?
    @StateObject private var audioPlayerManager = AudioPlayerManager()
    @StateObject private var calibrator = Calibrator()

    @State private var userNotification: String = "Please record a base track."
    @State private var showCalibrationAlert: Bool = false
    
    @State private var envelope: [Float]?
    @State private var liveview: [Float]?
    
    @State private var canvasWidth: Double = 0.0
    
    @AppStorage("TFData") var TFData: Data?
    @State private var TFComplex: DSPSplitComplex?
    
    var body: some View {
        GeometryReader { outerGeometry in
            VStack
            {
                ZStack {
                    Canvas { context, size in
                        //print("Redrawing rect")
                        let rect = CGRect(origin: .zero, size: size)
                        context.fill(Path(rect), with: .color(.black))
                    }
                    
                    Canvas { context, size in
                        //print("Redrawing playhead")
                        // Draw playhead
                        if self.trackExists && self.duration > 0 {
                            let percentage: Double = min(self.playhead / self.duration, 1.0)
                            let playheadX = percentage * Double(size.width)
                            let shaded = CGRect(origin: .zero, size: CGSize(width: Int(playheadX), height: Int(size.height)) )
                            context.fill(Path(shaded), with: .color(.purple))
                        }
                    }
                    
                    Canvas { context, size in
                        //print("Redrawing axis")
                        var linePath = Path()
                        linePath.move(to: CGPoint(x: 0, y: size.height/2))
                        linePath.addLine(to: CGPoint(x: size.width, y: size.height/2))
                        context.stroke(linePath, with: .color(.gray))
                    }
                        
                    EnvelopeView(envelope: self.$envelope)
                }
                .gesture(
                    DragGesture(minimumDistance: 0)
                    .onEnded { value in
                        
                        if self.state == .STOP {
                            let translation = value.translation
                                    
                            // Detect a swipe based on horizontal translation
                            if translation.width < -50 {
                                self.playhead = 0.0
                            } else {
                                self.playhead = (value.location.x / outerGeometry.size.width) * self.duration
                            }
                            audioPlayerManager.setCurrentTime(time: self.playhead)
                        }
                        
                    }
                )
                .frame(width: outerGeometry.size.width, height: 200)
                
                Text(String(format: "%.2f", self.playhead))
                    .frame(width: outerGeometry.size.width, height: 20, alignment: .center)
                    .padding()
                
                HStack {
                    
                    Spacer()
                    // PLAY / PAUSE BUTTON
                    Button {
                        switch self.state {
                        case .STOP:
                            play()
                        case .PLAY:
                            pause()
                        case .RECORD:
                            stopRecording()
                        case .CALIBRATE:
                            break
                        }
                    } label: {
                        Image(systemName: self.state == .STOP ? "play" : "pause")
                            .resizable()
                            .frame(width:60,height: 60)
                            .foregroundColor(Color.green)
                    }//.padding(.horizontal, 30)
                    Spacer()

                    // RECORD BUTTON
                    Button {
                        switch self.state {
                        case .STOP:
                            requestMicrophoneAccessAndStartRecording()
                        case .PLAY:
                            self.userNotification = "Please pause before recording."
                        case .RECORD:
                            stopRecording()
                        case .CALIBRATE:
                            break
                        }
                    } label: {
                        Image(systemName: self.state == .RECORD ? "stop" : "record.circle").resizable().frame(width: 60, height: 60).foregroundColor(.red)
                    }//.padding(.horizontal, 30)
                    Spacer()
                }
                
                // NOTIFICATION
                Text(userNotification)
                    .frame(width: outerGeometry.size.width, height: 20, alignment: .center)
                    .padding()
                
                ZStack {
                    Canvas { context, size in
                        print("Redrawing rect2")
                        let rect = CGRect(origin: .zero, size: size)
                        context.fill(Path(rect), with: .color(.black))
                    }
                    
                    Canvas { context, size in
                        print("Redrawing axis2")
                        var linePath = Path()
                        linePath.move(to: CGPoint(x: 0, y: size.height/2))
                        linePath.addLine(to: CGPoint(x: size.width, y: size.height/2))
                        context.stroke(linePath, with: .color(.gray))
                    }
                        
                    LiveView(liveview: self.$liveview)
                }
                .frame(width: outerGeometry.size.width, height: 200)

                HStack {
                    // CALIBRATE BUTTON
                    Button {
                        if self.state == .STOP {
                            showCalibrationAlert = true
                        }
                    } label:
                    {
                        Image(systemName: "stethoscope")
                            .resizable()
                            .frame(width:60,height: 50)
                            .foregroundColor(Color.gray)
                    }
                    .padding()
                    .alert(isPresented: $showCalibrationAlert, content: {
                        Alert(
                            title: Text("Calibration"),
                            message: Text("Before calibrating the echo canceller, seek a quiet environment and remain silent until the process completes."),
                            primaryButton: .default(Text("Begin"), action: {
                                // OK action
                                print("OK pressed")
                                requestMicrophoneAccessAndStartCalibrating()
                            }),
                            secondaryButton: .cancel(Text("Cancel"), action: {
                                // Cancel action
                                print("Cancel pressed")
                            })
                        )
                    })
                    
                    
                    // SAVE BUTTON
                    Button {
                        if self.state == .STOP {
                            save()
                        } else {
                            self.userNotification = "Stop audio before saving."
                        }
                    } label:
                    {
                        Image(systemName: "square.and.arrow.up").resizable().frame(width: 38, height: 50).foregroundColor(Color.gray)
                    }.padding(.horizontal,50)
                    
                    
                    // RESET BUTTON
                    Button {
                        if self.state == .RECORD {
                            abortRecording()
                        } else if self.state != .CALIBRATE {
                            reset()
                        }
                    } label:
                    {
                        Image(systemName: "trash")
                            .resizable()
                            .frame(width:50,height:50)
                            .foregroundColor(Color.gray)
                    }.padding()
                }
                
            }
            .onAppear {
                configureAudioSession()
                self.canvasWidth = outerGeometry.size.width
                if let tf = self.TFData {
                    print("Deserialize TFData")
                    self.TFComplex = deserializeDSPSplitComplex(tf, count: 1024)
                }
            }
            .onReceive(audioPlayerManager.$currentPlaytime) { time in
                self.playhead = time
            }
            .onReceive(audioPlayerManager.$audioFinished) { finished in
                if finished {
                    print("onReceive: Playback finished")
                    
                    if self.state != .RECORD {
                        self.state = .STOP
                        self.playhead = 0.0
                    }
                }
            }
            .onReceive(calibrator.$calibrationFinished) { finished in
                if finished {
                    print("onReceive: Calibration complete")
                    stopCalibrating()
                }
            }
            .frame(width: outerGeometry.size.width, height: outerGeometry.size.height)  // Full-screen alignment
        }.edgesIgnoringSafeArea(.horizontal)  // Ensure the view takes up the entire screen area
    }
    
    // Configure the audio session
    func configureAudioSession() {
        do {
            let audioSession = AVAudioSession.sharedInstance()
            try audioSession.setCategory(.playAndRecord, mode: .default)
            // Override the output to route to the speaker (as opposed to earpiece)
            try audioSession.overrideOutputAudioPort(.speaker)
            try audioSession.setActive(true)
        } catch {
            print("Failed to configure audio session: \(error.localizedDescription)")
        }
    }
    
    // Request microphone access with completion handler
    func requestMicrophoneAccessAndStartCalibrating() {
        AVAudioApplication.requestRecordPermission { granted in
            DispatchQueue.main.async {
                if granted {
                    print("Microphone access granted.")
                    startCalibrating()
                } else {
                    print("Microphone access denied.")
                    self.state = .STOP  // Ensure we don't change to "Stop Recording"
                }
            }
        }
    }
    
    func startCalibrating() {
        print("start calibrating")
        
        let recordingSettings = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 44100,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
        ]
        
        let audioFilename = getDocumentsDirectory().appendingPathComponent("cal.m4a")
        
        do {
            audioRecorder = try AVAudioRecorder(url: audioFilename, settings: recordingSettings)
            audioRecorder?.prepareToRecord()
            
            if let t = audioRecorder?.deviceCurrentTime {
                let t1: TimeInterval = t + 0.5
                audioRecorder?.record(atTime: t1)
                self.calibrator.playWavFile(atTime: t1)
            }
            
            self.userNotification = "Calibrating..."
            print("Calibrating...")
            self.state = .CALIBRATE
        } catch {
            print("Failed to start recording: \(error.localizedDescription)")
            self.state = .STOP  // Handle error and reset the state
        }
    }
    
    
    
    func stopCalibrating() {
        print("stop calibrating")
        audioRecorder?.stop()
        audioRecorder = nil
        
        self.state = .STOP
        
        self.TFComplex = calibrator.getTransferFunc("cal.m4a")
        
        if let cmplx = self.TFComplex {
            // Save to AppStorage
            self.TFData = serializeDSPSplitComplex(cmplx, count: 512)
        }
        
        if let cmplx = self.TFComplex {
            var impResp = [Float](repeating: 0.0, count: Int(self.canvasWidth))
            withUnsafePointer(to: cmplx) { c in
                getImpulseResponse(inp: c, outp: &impResp, nBinsIn: 512, nSampOut: Int(self.canvasWidth))
            }
            //print("\(impResp)")
            self.liveview = impResp
        }
        
        self.userNotification = "Calibration complete."
        
    }
    
    // Request microphone access with completion handler
    func requestMicrophoneAccessAndStartRecording() {
        AVAudioApplication.requestRecordPermission { granted in
            DispatchQueue.main.async {
                if granted {
                    print("Microphone access granted.")
                    startRecording()
                } else {
                    print("Microphone access denied.")
                    self.state = .STOP  // Ensure we don't change to "Stop Recording"
                }
            }
        }
    }
    
    func startRecording() {
        print("start recording")
        
        let recordingSettings = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 44100,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
        ]
        
        let audioFilename = getDocumentsDirectory().appendingPathComponent(
            self.trackExists ? "dub.m4a" : "base.m4a")
        
        do {
            audioRecorder = try AVAudioRecorder(url: audioFilename, settings: recordingSettings)
            audioRecorder?.prepareToRecord()
            
            if self.trackExists {
                self.previousPlayhead = self.playhead
                
                if let t = audioRecorder?.deviceCurrentTime {
                    let t1: TimeInterval = t + 0.5
                    audioRecorder?.record(atTime: t1)
                    audioPlayerManager.playAudio(atTime: t1)
                }
                
            } else {
                audioRecorder?.record()
            }

            self.userNotification = "Recording..."
            print("Recording...")
            self.state = .RECORD
        } catch {
            print("Failed to start recording: \(error.localizedDescription)")
            self.state = .STOP  // Handle error and reset the state
        }
    }
    
    func abortRecording() {
        print("abortRecording")
        audioRecorder?.stop()
        audioRecorder = nil
        
        self.userNotification = "Recording ignored"
        
        self.state = .STOP
        if self.trackExists {
            audioPlayerManager.pauseAudio()
            audioPlayerManager.setCurrentTime(time: self.playhead)
        } else {
            // this premiere recording was saved as base.m4a
            reset()
            return
        }
    }
    
    func stopRecording() {
        print("stop recording")
        audioRecorder?.stop()
        audioRecorder = nil
        
        self.userNotification = ""
        
        self.state = .STOP
        if self.trackExists {
            audioPlayerManager.pauseAudio()
            self.playhead = 0.0
        } else {
            // this premiere recording was saved as base.m4a
            self.duration = audioPlayerManager.prepareAudio(filename: "base.m4a")
            self.envelope = audioPlayerManager.getEnvelope(bins: Int(self.canvasWidth))
            self.playhead = 0.0
            self.trackExists = true

            return
        }
        
        // For now, just overlay dub.m4a over base.m4a, save to base.m4a
        let base = getDocumentsDirectory().appendingPathComponent("base.m4a")
        let dub = getDocumentsDirectory().appendingPathComponent("dub.m4a")
        
        if let combinedBuffer = addAudioBuffers(baseUrl: base, dubUrl: dub, atTime: previousPlayhead, 
                                                transferFunction: self.TFComplex, doEchoCancellation: false, debug: false) {
            writeAudioFile(buffer: combinedBuffer, url: base)
            print("Audio files combined successfully!")
            
            // prepare Audio, set currentTime
            self.duration = audioPlayerManager.prepareAudio(filename: "base.m4a")
            self.envelope = audioPlayerManager.getEnvelope(bins: Int(self.canvasWidth))
            audioPlayerManager.setCurrentTime(time: self.playhead)
            
        } else {
            print("Error combining audio buffers.")
        }
    }
    
    func play() {
        print("start playback")
        
        if !self.trackExists {
            self.userNotification = "Please record a base track."
            print("Track does not exist")
            return
        }
        
        self.audioPlayerManager.playAudioNow()
        self.state = .PLAY
    }
    
    func pause() {
        print("pause playback")
        audioPlayerManager.pauseAudio()
        self.state = .STOP
    }
    
    func reset() {
        print("reset")
        
        if self.state == .RECORD {
            audioRecorder?.stop()
            audioRecorder = nil
        }
        
        self.state = .STOP
        self.playhead = 0.0
        self.envelope = nil
        
        if self.trackExists {
            audioPlayerManager.stopAudio()
        
            let audioFilename = getDocumentsDirectory().appendingPathComponent("base.m4a")
            do {
                try FileManager.default.removeItem(at: audioFilename)
                self.userNotification = "Reset complete."
                print("base.m4a deleted")
                self.trackExists = false
            } catch {
                print("Exception in reset()")
            }
        } else {
            self.userNotification = "Please record a base track."
        }
    }
    
    func save() {
        print("save")
        
        if !self.trackExists {
            self.userNotification = "Please record a base track."
            print("Track does not exist")
            return
        }
        
        // TODO: save to files
    }

}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}

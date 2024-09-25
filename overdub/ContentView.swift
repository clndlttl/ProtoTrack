//
//  ContentView.swift
//  overdub
//
//  Created by Colin Fox on 9/12/24.
//

import SwiftUI
import AVFoundation

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


struct ContentView: View {

    @State private var state: AppState = .STOP
    @State private var trackExists: Bool = false
    
    @State private var playhead: TimeInterval = 0.0
    
    @State private var audioRecorder: AVAudioRecorder?
    @StateObject var audioPlayerManager = AudioPlayerManager()
    @StateObject var calibrator = Calibrator()

    @State private var userNotification: String = "Please record a base track."
    @State private var showCalibrationAlert: Bool = false
    
    @State private var shouldRedrawWaveform: Bool = false

    var body: some View {
        GeometryReader { geometry in
            VStack
            {
                Canvas { context, size in
                    
                    let rect = CGRect(origin: .zero, size: size)
                    
                    context.fill(
                        Path(rect),
                        with: .color(.white)
                    )
                    
                    let minX = rect.minX
                    let midY = rect.midY
                    let startPoint = CGPoint(x: minX, y: midY)
                    let endPoint = CGPoint(x: rect.maxX, y: midY)
                    
                    var linePath = Path()
                    linePath.move(to: startPoint)
                    linePath.addLine(to: endPoint)
                    
                    context.stroke(linePath, with: .color(.gray))
                    
                    // Draw base.m4a
                    if shouldRedrawWaveform && self.trackExists {
                        if let envelope = audioPlayerManager.getEnvelope(bins: Int(rect.maxX - minX)) {
                            for (idx, point) in envelope.enumerated() {
                                linePath = Path()
                                linePath.move(to: CGPoint(x: minX+CGFloat(idx), y: midY*(1.0+CGFloat(point))))
                                linePath.addLine(to: CGPoint(x: minX+CGFloat(idx), y: midY*(1.0-CGFloat(point))))
                                
                                context.stroke(linePath, with: .color(.black))
                            }
                        }
                    }
                    
                    
                }
                .frame(width: geometry.size.width, height: 200)
                
                //Spacer()
                
                Text(String(format: "%.2f", self.playhead))
                    .frame(width: geometry.size.width, height: 20, alignment: .center)
                    .padding()
                
                HStack {
                    // PLAY FROM TOP BUTTON
                    Button {
                        if self.state == .RECORD {
                            stopRecording()
                        }
                        rewind()
                    } label: {
                        Image(systemName: "gobackward")
                            .resizable()
                            .frame(width:60,height: 60)
                            .foregroundColor(Color.blue)
                    }
                    
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
                    }.padding(.horizontal,50)
                    
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
                    }
                    
                }
                
                // NOTIFICATION
                Text(userNotification)
                    .frame(width: geometry.size.width, height: 20, alignment: .center)
                    .padding()
                
                //Spacer()
                
                Canvas { context, size in
                    
                    let rect = CGRect(origin: .zero, size: size)
                    
                    context.fill(
                        Path(rect),
                        with: .color(.white)
                    )
                }
                .frame(width: geometry.size.width, height: 200)

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
                                calibrate()
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
                    self.state = .STOP
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height)  // Full-screen alignment
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
    
    func calibrate() {
        print("calibrate")
        self.state = .CALIBRATE
        calibrator.playWavFile()
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
            AVSampleRateKey: 12000,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
        ]
        
        let audioFilename = getDocumentsDirectory().appendingPathComponent(
            self.trackExists ? "dub.m4a" : "base.m4a")
        
        do {
            audioRecorder = try AVAudioRecorder(url: audioFilename, settings: recordingSettings)
            audioRecorder?.record()
            if self.trackExists {
                self.audioPlayerManager.playAudio()
            }
            // May need to deduce the delay between new recording and playback
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
            _ = audioPlayerManager.pauseAudio()
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
        let previousPlayhead: TimeInterval = self.playhead
        
        self.state = .STOP
        if self.trackExists {
            self.playhead = audioPlayerManager.pauseAudio()
            print("Set playhead to \(self.playhead)")
        } else {
            // this premiere recording was saved as base.m4a
            self.trackExists = true
            audioPlayerManager.prepareAudio(filename: "base.m4a")
            shouldRedrawWaveform = false
            shouldRedrawWaveform = true
            return
        }
        
        // TODO: DSP tasks
        
        // For now, just overlay dub.m4a over base.m4a, save to base.m4a
        let base = getDocumentsDirectory().appendingPathComponent("base.m4a")
        let dub = getDocumentsDirectory().appendingPathComponent("dub.m4a")
        
        if let combinedBuffer = addAudioBuffers(baseUrl: base, dubUrl: dub, offset: previousPlayhead) {
            writeAudioFile(buffer: combinedBuffer, url: base)
            print("Audio files combined successfully!")
            
            // prepare Audio, set currentTime
            audioPlayerManager.prepareAudio(filename: "base.m4a")
            audioPlayerManager.setCurrentTime(time: self.playhead)

            shouldRedrawWaveform = false
            shouldRedrawWaveform = true
             
        } else {
            print("Error combining audio buffers.")
        }
    }

    func rewind() {
        print("rewind")
        
        if !self.trackExists {
            self.userNotification = "Please record a base track."
            print("Track does not exist")
            return
        }
        
        if self.state == .PLAY {
            _ = self.audioPlayerManager.pauseAudio()
        }
        
        self.audioPlayerManager.setCurrentTime(time: 0.0)
        self.playhead = 0.0

        if self.state == .PLAY {
            self.audioPlayerManager.playAudio()
        }
    }
    
    func play() {
        print("start playback")
        
        if !self.trackExists {
            self.userNotification = "Please record a base track."
            print("Track does not exist")
            return
        }
        
        self.audioPlayerManager.playAudio()
        self.state = .PLAY
    }
    
    func pause() {
        print("pause playback, update playhead")
        self.playhead = audioPlayerManager.pauseAudio()
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

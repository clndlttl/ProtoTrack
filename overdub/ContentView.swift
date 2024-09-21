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
    
    @State private var userNotification: String = "Please record a base track."

    var body: some View {
        GeometryReader { geometry in
            VStack
            {
                // RESET BUTTON
                Button {
                    reset()
                } label:
                {
                    Text("Reset")
                        .font(.title)
                        .padding()
                        .background(Color.gray)
                        .foregroundColor(.white)
                        .cornerRadius(10)
                }
                
                Spacer()
                
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
                        Image(systemName: "backward.end.circle")
                            .resizable()
                            .frame(width:100,height: 100)
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
                        }
                    } label: {
                        Image(systemName: self.state == .STOP ? "play.circle" : "pause.circle")
                            .resizable()
                            .frame(width:100,height: 100)
                            .foregroundColor(self.state == .STOP ? Color.green : Color.yellow)
                    }.padding(.horizontal,25)
                    
                    // RECORD BUTTON
                    Button {
                        switch self.state {
                        case .STOP:
                            requestMicrophoneAccessAndStartRecording()
                        case .PLAY:
                            self.userNotification = "Please pause before recording."
                        case .RECORD:
                            stopRecording()
                        }
                    } label: {
                        Image(systemName: self.state == .RECORD ? "square.fill" : "record.circle").resizable().frame(width: 100, height: 100).foregroundColor(.red)
                    }
                    
                }
                // NOTIFICATION
                Text(userNotification)
                    .frame(width: geometry.size.width, height: 20, alignment: .center)
                    .padding()
                
                Spacer()
                
                // SAVE BUTTON
                Button {
                    if self.state == .STOP {
                        save()
                    } else {
                        self.userNotification = "Stop audio before saving."
                    }
                } label:
                {
                    Text("Save")
                        .font(.title)
                        .padding()
                        .background(Color.gray)
                        .foregroundColor(.white)
                        .cornerRadius(10)
                }
                
            }
            .onAppear {
                configureAudioSession()
            }
            .onReceive(audioPlayerManager.$audioFinished) { finished in
                if finished {
                    print("Playback finished")
                    
                    if self.state != .RECORD {
                        self.state = .STOP
                        self.playhead = 0.0
                    }
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
            return
        }
        
        // TODO: DSP tasks
        
        // For now, just overlay dub.m4a over base.m4a, save to base.m4a
        let base = getDocumentsDirectory().appendingPathComponent("base.m4a")
        let dub = getDocumentsDirectory().appendingPathComponent("dub.m4a")
        
        if let combinedBuffer = addAudioBuffers(baseUrl: base, dubUrl: dub, offset: previousPlayhead) {
            writeAudioFile(buffer: combinedBuffer, url: base)
            print("Audio files combined successfully!")
            
            // note currentTime, prepare Audio, reset currentTime
            audioPlayerManager.prepareAudio(filename: "base.m4a")
            audioPlayerManager.setCurrentTime(time: self.playhead)
             
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
            print(audioFilename)
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

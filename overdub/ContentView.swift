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

class AudioPlayerManager: NSObject, AVAudioPlayerDelegate, ObservableObject {
    var audioPlayer: AVAudioPlayer?
    private var prepared: Bool = false
    
    // Observable property to track if audio finished playing
    @Published var audioFinished = false
    
    func prepareAudio(filename: String) {
        let audioFilename = getDocumentsDirectory().appendingPathComponent(filename)
                
        do {
            audioPlayer = try AVAudioPlayer(contentsOf: audioFilename)
            audioPlayer?.delegate = self  // Set the delegate
            audioPlayer?.prepareToPlay()  // Start playing the audio
            self.prepared = true
            print("Audio prepared.")
        } catch {
            print("Failed to prepare audio: \(error.localizedDescription)")
        }
    }
    
    func markAsUnprepared() {
        self.prepared = false
    }
    
    func playAudio() {
        if !self.prepared {
            prepareAudio(filename: "base.m4a")
        }
        audioPlayer?.play()
    }
    
    func pauseAudio() {
        audioPlayer?.pause()
    }
    
    // Delegate method to detect when the audio finishes playing
    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        if flag {
            print("Audio finished playing successfully.")
            DispatchQueue.main.async {
                self.audioFinished = true  // Notify the view of the event
            }
        } else {
            print("Audio finished playing, but there was an issue.")
        }
    }
}

struct ContentView: View {

    @State private var state: AppState = .STOP
    @State private var trackExists: Bool = false
    
    @State private var audioRecorder: AVAudioRecorder?
    @StateObject var audioPlayerManager = AudioPlayerManager()
    
    @State private var userNotification: String = ""

    var body: some View {
        VStack
        {
            // RESET BUTTON
            Button {
                switch self.state {
                case .RECORD:
                    stopRecording()
                case .PLAY:
                    pause()
                case .STOP:
                    break
                }
                        
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
            
            HStack {
                // PLAY FROM TOP BUTTON
                Button {
                    switch self.state {
                    case .STOP:
                        initPlayback()
                    case .PLAY:
                        pause()
                        initPlayback()
                    case .RECORD:
                        break
                    }
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
                        unpause()
                    case .PLAY:
                        pause()
                    case .RECORD:
                        break
                    }
                } label: {
                    Image(systemName: self.state == .STOP ? "play.circle" : "pause.circle")
                        .resizable()
                        .frame(width:100,height: 100)
                        .foregroundColor(self.state == .STOP ? Color.green : Color.blue)
                }.padding(.horizontal,25)
                
                // RECORD BUTTON
                Button {
                    switch self.state {
                    case .STOP:
                        requestMicrophoneAccessAndStartRecording()
                    case .PLAY:
                        break
                    case .RECORD:
                        stopRecording()
                    }
                } label: {
                    Image(systemName: self.state == .RECORD ? "square.fill" : "record.circle").resizable().frame(width: 100, height: 100).foregroundColor(.red)
                }
                
            }
            // NOTIFICATION
            Text(userNotification).padding()
            
            Spacer()
            
            // SAVE BUTTON
            Button {
                if self.state == .STOP {
                    save()
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
                }
            }
        }
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
        
        if self.trackExists {
            audioPlayerManager.prepareAudio(filename: "base.m4a")
        }

        do {
            audioRecorder = try AVAudioRecorder(url: audioFilename, settings: recordingSettings)
            audioRecorder?.record()
            if self.trackExists {
                self.audioPlayerManager.playAudio()
            }
            // May need to deduce the delay between new recording and playback
            print("Recording started.")
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
        
        if self.trackExists {
            pause()
        } else {
            self.trackExists = true
            self.state = .STOP
            return
        }
        
        // TODO: DSP tasks
        
        // For now, just overlay dub.m4a over base.m4a, save to base.m4a
        let base = getDocumentsDirectory().appendingPathComponent("base.m4a")
        let dub = getDocumentsDirectory().appendingPathComponent("dub.m4a")
        
        if let buffer1 = readAudioFile(url: base), let buffer2 = readAudioFile(url: dub) {
            if let combinedBuffer = addAudioBuffers(buffer1: buffer1, buffer2: buffer2) {
                writeAudioFile(buffer: combinedBuffer, url: base)
                audioPlayerManager.markAsUnprepared()
                print("Audio files combined successfully!")
            } else {
                print("Error combining audio buffers.")
            }
        }
    }
    
    func initPlayback() {
        print("init playback")
        
        if !self.trackExists {
            self.userNotification = "Please record a base track first"
            print("Track does not exist")
            return
        }
        
        self.audioPlayerManager.prepareAudio(filename: "base.m4a")
        self.audioPlayerManager.playAudio()
        self.state = .PLAY
    }
    
    func unpause() {
        print("start playback")
        
        if !self.trackExists {
            self.userNotification = "Please record a base track first"
            print("Track does not exist")
            return
        }
        
        self.audioPlayerManager.playAudio()
        self.state = .PLAY
    }
    
    func pause() {
        print("stop playback")
        audioPlayerManager.pauseAudio()
        self.state = .STOP
    }
    
    func reset() {
        print("reset")
        self.state = .STOP
        if !self.trackExists {
            self.userNotification = "Nothing to reset"
            print("Track does not exist")
            return
        }
        
        let audioFilename = getDocumentsDirectory().appendingPathComponent("base.m4a")
        do {
            try FileManager.default.removeItem(at: audioFilename)
            self.userNotification = "Reset complete"
            print("base.m4a deleted")
            self.trackExists = false
        } catch {
            print("Exception in reset()")
        }
    }
    
    func save() {
        print("save")
        
        if !self.trackExists {
            self.userNotification = "Please record a base track first"
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

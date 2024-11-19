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
}

struct OptionsView: View {
    
    @Environment(\.dismiss) private var dismiss
    
    @Binding var useMainSpeaker: Bool
    
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Toggle("Use main speaker", isOn: $useMainSpeaker)
                        Text("The main speaker output will appear on the microphone. Use earbuds for best recording quality.")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                }
            }
            .navigationTitle("Options")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
}

struct EnvelopeView: View {
    @Binding var envelope: [Float]?

    var body: some View {
        Canvas { context, size in
            // print("Redrawing waveform!!!")
            let midY = size.height / 2.0
            if let env = self.envelope {
                for (idx, point) in env.enumerated() {
                    var linePath = Path()
                    linePath.move(to: CGPoint(x: CGFloat(idx), y: midY*(1.0+0.9*CGFloat(point))))
                    linePath.addLine(to: CGPoint(x: CGFloat(idx), y: midY*(1.0-0.9*CGFloat(point))))
                    context.stroke(linePath, with: .color(.white))
                }
            }
        }
    }
}

struct LiveView: View {
    @Binding var noisefloor: Float?
    @Binding var liveview: [Float]?

    var body: some View {
        Canvas { context, size in
            //print("Redrawing liveview size = \(size)!!!")
            guard let nf = noisefloor else { return }
            let slope = Float(size.height) / nf
            
            if let dB = self.liveview {
                for idx in 0..<Int(size.width) {
                    let samp = dB[idx] * slope
                    var linePath = Path()
                    linePath.move(to: CGPoint(x: CGFloat(idx), y: CGFloat(samp) ))
                    linePath.addLine(to: CGPoint(x: CGFloat(idx), y: size.height))
                    context.stroke(linePath, with: .color(.teal))
                }
            }
        }
    }
}

struct ContentView: View {
    
    @StateObject private var audioPlayerManager = AudioPlayerManager()
    @StateObject private var circularBuffer = CircularBuffer()
    @StateObject private var audioEngine = AudioEngine()
    @StateObject private var bluetoothMgr = BluetoothManager()

    @State private var state: AppState = .STOP
    @State private var trackExists: Bool = false
    @State private var trackName: String = "new-track.m4a"
    @State private var lastTrackName: String?
    
    @State private var playhead: TimeInterval = 0.0
    @State private var previousPlayhead: TimeInterval = 0.0
    @State private var playheadX: Double = 0.0
    @State private var duration: TimeInterval = 0.0
   
    
    @State private var audioRecorder: AVAudioRecorder?

    private let MSG_PROMPT: String = "Please record a base track."
    @State private var userNotification: String = ""
    
    @State private var isOptionsPresented: Bool = false
    @State private var isSharePresented: Bool = false
    @State private var isUploadPresented: Bool = false
    @State private var fileUploaded: String = ""
    
    @State private var envelope: [Float]?
    
    @State private var noisefloor: Float?
    @State private var liveview: [Float]?
    
    @State private var canvasWidth: Double = 0.0
    
    @State private var animateButtons: Bool = false
    
    @State private var useMainSpeaker: Bool = false
    
    @State private var keyboardHeight: CGFloat = 0
    private var keyboardWillShow = NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)
    private var keyboardWillHide = NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)
    
    @Environment(\.scenePhase) var scenePhase
    
    var body: some View {
        GeometryReader { outerGeometry in
            VStack(spacing: 0)
            {
                HStack(alignment: .center) {
                    TextField("Track name", text: self.$trackName)
                        .onSubmit {
                            trackName = getSafeTrackName(trackName)
                            if let ltn = self.lastTrackName {
                                let track = getDocumentsDirectory().appendingPathComponent(ltn)
                                renameFile(at: track, to: trackName)
                                self.lastTrackName = trackName
                            }
                        }
                        .padding() // for the text
                        .background(Color(UIColor.systemGray6))  // Set background color (light gray)
                        .cornerRadius(8)  // Round the corners
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Color.blue, lineWidth: 2)  // Add a blue border
                        )
                        .padding(.trailing)
                    
                    Button {
                        isUploadPresented.toggle()
                    } label:
                    {
                        Image(systemName: "plus")
                            .resizable()
                            .frame(width:30,height: 30)
                            .foregroundColor(Color.gray)
                    }
                    .sheet(isPresented: $isUploadPresented, content: {
                        DocumentPickerView(fileUploaded: self.$fileUploaded)
                    })
                    .onChange(of: self.fileUploaded) { oldFile, newFile in
                        // Load into AudioPlayer, etc
                        print("onChange of \(newFile)")
                        self.duration = self.audioPlayerManager.prepareAudio(filename: newFile)
                        if self.duration > 0 {
                            self.trackName = newFile
                            self.lastTrackName = newFile
                            self.envelope = audioPlayerManager.getEnvelope(name: newFile, bins: Int(self.canvasWidth))
                            self.playhead = 0.0
                            self.trackExists = true
                            redrawPlayhead()
                        }
                    }

                }
                .padding()
                
                ZStack(alignment: .leading) {
                    Canvas { context, size in
                        //print("Redrawing rect")
                        let rect = CGRect(origin: .zero, size: size)
                        context.fill(Path(rect), with: .color(.gray))
                    }
                    
                    Canvas { context, size in
                        //print("Redrawing playhead")
                        // Draw playhead
                        if trackExists {
                            let shaded = CGRect(origin: .zero, size: CGSize(width: Int(size.width), height: Int(size.height)) )
                            context.fill(Path(shaded), with: .color(.yellow))
                        }
                    }
                    .frame(width: playheadX, height: 160)
                    
                    Canvas { context, size in
                        //print("Redrawing axis")
                        var linePath = Path()
                        linePath.move(to: CGPoint(x: 0, y: size.height/2))
                        linePath.addLine(to: CGPoint(x: size.width, y: size.height/2))
                        context.stroke(linePath, with: .color(.white))
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
                            redrawPlayhead()
                        }
                        
                    }
                )
                .frame(width: outerGeometry.size.width, height: 160)
                
                ZStack {
                    LinearGradient(colors: [.gray,.black], startPoint: .top, endPoint: .bottom)
                    
                    VStack {
                        Text(String(format: "%.2f", self.playhead))
                            .frame(width: outerGeometry.size.width, height: 20, alignment: .center)
                            .padding()
                            .foregroundStyle(.yellow)
                            .shadow(color: .black, radius: 7, x: -10, y: 10)

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
                                }
                            } label: {
                                Image(systemName: self.state == .STOP ? "play" : "pause")
                                    .resizable()
                                    .frame(width:60,height: 60)
                                    .foregroundColor(Color.green)
                            }
                            .shadow(color: .black, radius: 7, x: -10, y: 10)
                            
                            Spacer()
                            
                            // RECORD BUTTON
                            Button {
                                switch self.state {
                                case .STOP:
                                    withAnimation(.easeInOut(duration: 1.0).repeatForever()) {
                                        animateButtons = true
                                    }
                                    requestMicrophoneAccessAndStartRecording()
                                case .PLAY:
                                    self.userNotification = "Please pause before recording."
                                case .RECORD:
                                    withAnimation {
                                        animateButtons = false
                                    }
                                    stopRecording()
                                }
                            } label: {
                                Image(systemName: self.state == .RECORD ? "stop" : "record.circle").resizable().frame(width: 60, height: 60).foregroundColor(.red)
                            }
                            .shadow(color: .black, radius: 7, x: -10, y: 10)
                            .scaleEffect(animateButtons ? 1.2 : 1.0)
                            
                            Spacer()
                        }
                        
                        // NOTIFICATION
                        Text(userNotification)
                            .frame(width: outerGeometry.size.width, height: 20, alignment: .center)
                            .padding()
                    }
                }
                
                ZStack {
                    Canvas { context, size in
                        print("Redrawing rect2")
                        let rect = CGRect(origin: .zero, size: size)
                        context.fill(Path(rect), with: .color(.black))
                    }
                    
                    Group {
                        Canvas { context, size in
                            print("Redrawing axis2")
                            var linePath = Path()
                            linePath.move(to: CGPoint(x: 0, y: size.height))
                            linePath.addLine(to: CGPoint(x: size.width, y: size.height))
                            context.stroke(linePath, with: .color(.white))
                        }
                        
                        LiveView(noisefloor: self.$noisefloor, liveview: self.$liveview)
                    }
                    .padding(.bottom, 50)
                }
                .frame(width: outerGeometry.size.width, height: 200)

                HStack {
                    
                    // OPTIONS BUTTON
                    Button {
                        if self.state == .STOP {
                            self.isOptionsPresented = true
                        }
                    } label:
                    {
                        Image(systemName: "gearshape")
                            .resizable()
                            .frame(width:50,height: 50)
                            .foregroundColor(Color.gray)
                    }
                    .padding()
                    .sheet(isPresented: self.$isOptionsPresented, content: {
                        OptionsView(useMainSpeaker: self.$useMainSpeaker)
                            .onChange(of: self.useMainSpeaker) { oldVal, newVal in
                                print("call configureAudioSession")
                                configureAudioSession()
                            }
                    })
                    
                    // SAVE BUTTON
                    Button {
                        if self.state == .STOP {
                            if self.trackExists {
                                self.isSharePresented = true
                            } else {
                                self.userNotification = MSG_PROMPT
                            }
                        } else {
                            self.userNotification = "Stop audio before saving."
                        }
                    } label:
                    {
                        Image(systemName: "square.and.arrow.up").resizable().frame(width: 38, height: 50).foregroundColor(Color.gray)
                    }
                    .padding(.horizontal,50)
                    .sheet(isPresented: $isSharePresented, content: {
                            let track = getDocumentsDirectory().appendingPathComponent(self.trackName)
                            ActivityViewController(activityItems: [track])
                        })
                    
                    // RESET BUTTON
                    Button {
                        if self.state == .RECORD {
                            withAnimation {
                                animateButtons = false
                            }
                            abortRecording()
                        } else {
                            reset()
                        }
                    } label:
                    {
                        Image(systemName: "trash")
                            .resizable()
                            .frame(width:50,height:50)
                            .foregroundColor(Color.gray)
                    }
                    .padding()
                    .scaleEffect(animateButtons ? 1.2 : 1.0)
                }
                
            }
            .onAppear {
                //configureAudioSession()
                self.canvasWidth = outerGeometry.size.width
                self.circularBuffer.setSize(width: Int(self.canvasWidth))
                self.userNotification = MSG_PROMPT
            }
            .onChange(of: scenePhase) { oldPhase, newPhase in
                if newPhase == .active {
                    // App has returned to the foreground
                    print("App is now active")
                    if oldPhase == .inactive {
                        configureAudioSession()
                    }
                }
                //else if newPhase == .background {
                //    print("App is in the background")
                //} else if newPhase == .inactive {
                //    print("App is inactive")
                //}
            }
            .onReceive(bluetoothMgr.$isBluetoothConnected) { val in
                if val {
                    print("Yes, BT connected")
                }
                else {
                    print("BT is not connected")
                }
            }
            .onReceive(audioPlayerManager.$currentPlaytime) { time in
                self.playhead = time
                redrawPlayhead()
            }
            .onReceive(audioPlayerManager.$audioFinished) { finished in
                if finished {
                    print("onReceive: Playback finished")
                    
                    if self.state != .RECORD {
                        self.state = .STOP
                        self.playhead = 0.0
                        redrawPlayhead()
                    }
                }
            }
            .onReceive(audioEngine.$micBuffer) { mic in
                if let m = mic {
                    self.circularBuffer.write( m )
                }
            }
            .onReceive(circularBuffer.$ready) { ready in
                if ready != nil {
                    //print("onReceive circBuf ready")
                    
                    // update noisefloor and liveview
                    self.noisefloor = self.circularBuffer.getNoiseFloorInDB()
                    self.liveview = self.circularBuffer.read()
                }
            }
            .frame(width: outerGeometry.size.width, height: outerGeometry.size.height)  // Full-screen alignment
            .padding(.top, keyboardHeight)  // Add padding to move view up
            .onReceive(keyboardWillShow) { notification in
                if let keyboardFrame = notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect {
                    keyboardHeight = keyboardFrame.height
                }
            }
            .onReceive(keyboardWillHide) { _ in
                keyboardHeight = 0
            }
            
        }.edgesIgnoringSafeArea(.horizontal)  // Ensure the view takes up the entire screen area
    }
    
    func redrawPlayhead() {
        if duration > 0 {
            let percentage: Double = min(playhead / duration, 1.0)
            withAnimation(.easeOut) {
                playheadX = percentage * Double(canvasWidth)
            }
        }
    }


    // Configure the audio session
    func configureAudioSession() {
        print("configureAudioSession()")
        do {
            let audioSession = AVAudioSession.sharedInstance()
            try audioSession.setCategory(.playAndRecord, mode: .default, options: [.allowBluetooth, .allowBluetoothA2DP])
            // Check if a Bluetooth audio device is available. If not, vverride the output to route to the speaker (as opposed to earpiece)
            
            if self.useMainSpeaker {
                print("override .speaker")
                try audioSession.overrideOutputAudioPort(.speaker)
            } else {
                print("don't override .speaker")
                try audioSession.overrideOutputAudioPort(.none)

            }
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
        
        self.circularBuffer.clear()
        
        // prevent sleep
        UIApplication.shared.isIdleTimerDisabled = true
        
        let recordingSettings = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 44100,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
        ]
        
        let audioFilename = getDocumentsDirectory().appendingPathComponent(
            self.trackExists ? "__temp__.m4a" : self.trackName)
        
        do {
            audioEngine.start()
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

        UIApplication.shared.isIdleTimerDisabled = false
        audioRecorder?.stop()
        audioRecorder = nil
        
        audioEngine.stop()
        
        self.state = .STOP
        if self.trackExists {
            self.userNotification = "Recording discarded."
            audioPlayerManager.pauseAudio()
        } else {
            // this premiere recording was saved
            reset()
            return
        }
    }
    
    func stopRecording() {
        print("stop recording")
        
        UIApplication.shared.isIdleTimerDisabled = false
        audioRecorder?.stop()
        audioRecorder = nil
        
        audioEngine.stop()
        self.userNotification = "Record again to overdub."

        self.state = .STOP
        if self.trackExists {
            audioPlayerManager.pauseAudio()
            self.playhead = 0.0
            redrawPlayhead()
        } else {
            // this premiere recording is now saved
            self.duration = audioPlayerManager.prepareAudio(filename: self.trackName)
            self.envelope = audioPlayerManager.getEnvelope(name: self.trackName, bins: Int(self.canvasWidth))
            self.playhead = 0.0
            self.trackExists = true
            self.lastTrackName = self.trackName
            return
        }
        
        let base = getDocumentsDirectory().appendingPathComponent(self.trackName)
        let dub = getDocumentsDirectory().appendingPathComponent("__temp__.m4a")
        
        if let combinedBuffer = addAudioBuffers(baseUrl: base, dubUrl: dub, atTime: previousPlayhead) {
            writeAudioFile(buffer: combinedBuffer, url: base)
            print("Audio files combined successfully!")
            
            // prepare Audio, set currentTime
            self.duration = audioPlayerManager.prepareAudio(filename: self.trackName)
            self.envelope = audioPlayerManager.getEnvelope(name: self.trackName, bins: Int(self.canvasWidth))
            audioPlayerManager.setCurrentTime(time: self.playhead)
            
        } else {
            print("Error combining audio buffers.")
        }
    }
    
    func play() {
        print("start playback")
        
        if !self.trackExists {
            self.userNotification = MSG_PROMPT
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
        
        if self.trackExists {
            audioPlayerManager.stopAudio()
        }
        
        self.state = .STOP
        self.playhead = 0.0
        self.duration = 0.0
        self.envelope = nil
        self.trackExists = false
        self.userNotification = MSG_PROMPT
        
        // clear liveview
        self.circularBuffer.clear()
      
        // Delete all .m4a files
        for name in getM4AFiles() {
            
            let audioFilename = getDocumentsDirectory().appendingPathComponent(name)
            do {
                try FileManager.default.removeItem(at: audioFilename)
                print("\(name) deleted")
            } catch {
                print("Exception in reset()")
            }
            
        }
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}

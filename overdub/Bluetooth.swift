//
//  Bluetooth.swift
//  overdub
//
//  Created by Colin Fox on 11/18/24.
//

import AVFoundation

class BluetoothManager: ObservableObject {
    @Published var isBluetoothConnected: Bool = false

    init() {
        setupAudioSession()
        checkCurrentAudioRoute()
    }

    private func setupAudioSession() {
        let audioSession = AVAudioSession.sharedInstance()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(audioRouteChanged(_:)),
            name: AVAudioSession.routeChangeNotification,
            object: audioSession
        )
    }
    
    @objc private func audioRouteChanged(_ notification: Notification) {
        checkCurrentAudioRoute()
    }

    private func checkCurrentAudioRoute() {
        let audioSession = AVAudioSession.sharedInstance()
        let bluetoothRoutes: [AVAudioSession.Port] = [.bluetoothA2DP, .bluetoothHFP, .bluetoothLE]
        let isBluetoothConnected = audioSession.currentRoute.outputs.contains { output in
            bluetoothRoutes.contains(output.portType)
        }
        
        // Update published property
        DispatchQueue.main.async {
            self.isBluetoothConnected = isBluetoothConnected
        }
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }
}

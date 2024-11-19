//
//  FileManager.swift
//  overdub
//
//  Created by Colin Fox on 10/10/24.
//

import AVFoundation
//import UIKit
import SwiftUI

// Helper function to get the path to the app's documents directory
func getDocumentsDirectory() -> URL {
    let paths = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)
    return paths[0]
}

// For sharing files
struct ActivityViewController: UIViewControllerRepresentable {

    var activityItems: [Any]
    var applicationActivities: [UIActivity]? = nil
    @Environment(\.presentationMode) var presentationMode

    func makeUIViewController(context: UIViewControllerRepresentableContext<ActivityViewController>) -> UIActivityViewController {
        let controller = UIActivityViewController(activityItems: activityItems, applicationActivities: applicationActivities)
        controller.completionWithItemsHandler = { (activityType, completed, returnedItems, error) in
            self.presentationMode.wrappedValue.dismiss()
        }
        return controller
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: UIViewControllerRepresentableContext<ActivityViewController>) {}
}

// Function to read an audio file and return its PCM buffer
func readAudioFile(url: URL) -> AVAudioPCMBuffer? {
    let audioFile: AVAudioFile
    
    do {
        audioFile = try AVAudioFile(forReading: url)
    } catch {
        print("Error opening audio file: \(error)")
        return nil
    }

    let format = audioFile.processingFormat
    let frameCount = UInt32(audioFile.length)
    
    guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else {
        print("Error creating PCM buffer.")
        return nil
    }

    do {
        try audioFile.read(into: buffer)
    } catch {
        print("Error reading audio file: \(error)")
        return nil
    }
    
    return buffer
}

// Function to write a PCM buffer to an .m4a file
func writeAudioFile(buffer: AVAudioPCMBuffer, url: URL) {
    let format = buffer.format
    do {
        let audioFile = try AVAudioFile(forWriting: url, settings: format.settings, commonFormat: .pcmFormatFloat32, interleaved: false)
        try audioFile.write(from: buffer)
    } catch {
        print("Error writing audio file: \(error)")
    }
}

// Function to sanitize .m4a filenames
func getSafeTrackName(_ input: String) -> String {
    var sanitized = input
        
    // Remove any slashes
    sanitized = sanitized.replacingOccurrences(of: "/", with: "-")
    sanitized = sanitized.replacingOccurrences(of: " ", with: "_")

    // Ensure the file name ends with ".m4a"
    if !sanitized.hasSuffix(".m4a") {
        sanitized += ".m4a"
    }
        
    return sanitized
}

// Rename existing file
func renameFile(at originalURL: URL, to newName: String) {
    let fileManager = FileManager.default
    
    // Get the directory of the original file
    let directory = originalURL.deletingLastPathComponent()
    
    // Create the new URL with the new file name
    let newURL = directory.appendingPathComponent(newName)
    
    do {
        // Move the file to the new URL (essentially renaming it)
        try fileManager.moveItem(at: originalURL, to: newURL)
        print("File renamed successfully to \(newURL.lastPathComponent)")
    } catch {
        print("Failed to rename file: \(error.localizedDescription)")
    }
}

func getM4AFiles() -> [String] {
    let fileManager = FileManager.default
    
    // Get the document directory URL
    guard let documentsDirectory = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first else {
        print("Could not find the documents directory.")
        return []
    }
    
    do {
        // Get the contents of the documents directory
        let allFiles = try fileManager.contentsOfDirectory(atPath: documentsDirectory.path)
        
        // Filter the files that end with ".m4a"
        let m4aFiles = allFiles.filter { $0.hasSuffix(".m4a") }
        
        return m4aFiles
    } catch {
        print("Error retrieving contents of document directory: \(error.localizedDescription)")
        return []
    }
}


struct DocumentPickerView: UIViewControllerRepresentable {
    
    @Binding var fileUploaded: String
    
    func makeCoordinator() -> Coordinator {
        return Coordinator(self)
    }

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        // Define the types of files you want to support
        let documentPicker = UIDocumentPickerViewController(forOpeningContentTypes: [.audio])
        documentPicker.delegate = context.coordinator
        documentPicker.allowsMultipleSelection = false
        return documentPicker
    }

    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {}

    class Coordinator: NSObject, UIDocumentPickerDelegate {
        var parent: DocumentPickerView

        init(_ parent: DocumentPickerView) {
            self.parent = parent
        }

        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            guard let pickedURL = urls.first else { return }
            
            do {
                let fileManager = FileManager.default
                let appDirectory = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first!
                let destinationURL = appDirectory.appendingPathComponent(pickedURL.lastPathComponent)

                if fileManager.fileExists(atPath: destinationURL.path) {
                    try fileManager.removeItem(at: destinationURL)
                }
                
                try fileManager.copyItem(at: pickedURL, to: destinationURL)
                parent.fileUploaded = pickedURL.lastPathComponent
            } catch {
                print("Failed to copy file: \(error.localizedDescription)")
            }
        }
    }
}

import Foundation
import SwiftUI
import AVFoundation
import ElevenlabsSwift

@MainActor
class WhisperState: NSObject, ObservableObject, AVAudioRecorderDelegate {
    @Published var isModelLoaded = false
    @Published var messageLog = ""
    @Published var canTranscribe = false
    @Published var isRecording = false
    
    private var whisperContext: WhisperContext?
    private let recorder = Recorder()
    private var recordedFile: URL? = nil
    private var audioPlayer: AVAudioPlayer?
    private var context = "";
    private var apiURL = URL(string: "https://uivo50ps6j.execute-api.us-east-2.amazonaws.com/dev")!
    private var parameters: [String: Any] = [
            "return_full_text": false,
            "max_new_tokens": 1000
    ]
    private var Elevenlabs_API_key = "18649fed33aacf4ad0d14efc8516db8e"
    private var v_id = "gatbLVODbNLqoIAy6Wga"
    
    private var modelUrl: URL? {
        Bundle.main.url(forResource: "ggml-base", withExtension: "bin", subdirectory: "models")
    }
    
    private var sampleUrl: URL? {
        Bundle.main.url(forResource: "jfk", withExtension: "wav", subdirectory: "samples")
    }
    
    private enum LoadError: Error {
        case couldNotLocateModel
    }
    
    override init() {
        super.init()
        do {
            try loadModel()
            canTranscribe = true
        } catch {
            print(error.localizedDescription)
            messageLog += "\(error.localizedDescription)\n"
        }
    }
    
    
    private func loadModel() throws {
        messageLog += "Loading model...\n"
        if let modelUrl {
            whisperContext = try WhisperContext.createContext(path: modelUrl.path())
            messageLog += "Loaded model \(modelUrl.lastPathComponent)\n"
        } else {
            messageLog += "Could not locate model\n"
        }
    }
    
    func transcribeSample() async {
        if let sampleUrl {
            await transcribeAudio(sampleUrl)
        } else {
            messageLog += "Could not locate sample\n"
        }
    }
    
    private func getVoiceResponse(text: String) async {
        
        let elevenApi = ElevenlabsSwift(elevenLabsAPI: Elevenlabs_API_key)
        do {
            
            let url = try await elevenApi.textToSpeech(voice_id: v_id, text: text)
            print(url)
            _ = try startPlayback(url)
            print("done")
        } catch {
            print(error.localizedDescription)
            messageLog += "\(error.localizedDescription)\n"
        }
        
    }
    
    private func getAIResponse(text: String) async {

        let prompt = "### Instruction:\nYou are a friendly assistant named Elle. You are having a conversation with a person who is caring for someone with Alzheimer's Disease. Try to have a comforting conversation with them. Do not use emojis, and be very polite. Make sure that you answer their questions" + context + "\n### Input\nUser:" + text + "\n### Response\nAssistant: "

        let payload: [String: Any] = [
            "inputs": prompt,
            "parameters": parameters
        ]

        do {
            let jsonData = try JSONSerialization.data(withJSONObject: payload)

            var request = URLRequest(url: apiURL)

            request.httpMethod = "POST"
            request.httpBody = jsonData
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")

            do {
                
                var startTime = DispatchTime.now()
                let (data, _) = try await URLSession.shared.data(for: request)
                var endTime = DispatchTime.now()
                var nanoseconds = endTime.uptimeNanoseconds - startTime.uptimeNanoseconds
                var timeInterval = Double(nanoseconds) / 1_000_000_000.0

                print("Time for AI chat Response:", timeInterval,"s")
                if let jsonResponse = try JSONSerialization.jsonObject(with: data, options: []) as? [[String: String]] {
                    for res in jsonResponse {
                        if let gen = res["generated_text"] {
                            var startTime = DispatchTime.now()
                            try await self.getVoiceResponse(text: gen)
                            var endTime = DispatchTime.now()
                            var nanoseconds = endTime.uptimeNanoseconds - startTime.uptimeNanoseconds
                            var timeInterval = Double(nanoseconds) / 1_000_000_000.0

                            print("Time for AI Voice Response:", timeInterval,"s")
                            print("Response \(gen)")
                            self.messageLog += "\nAssistant: \(String(describing: gen))\n"
                            self.context += "\nUser: " + text + "\nAssistant: " + gen
                        }
                    }
                }
            } catch {
                print("Error parsing JSON: \(error.localizedDescription)")
            }

        } catch {
            print("Error: \(error.localizedDescription)")
        }
    }

    private func transcribeAudio(_ url: URL) async {
        if (!canTranscribe) {
            return
        }
        guard let whisperContext else {
            return
        }
        
        do {
            canTranscribe = false
            messageLog += "Reading wave samples...\n"
            let data = try readAudioSamples(url)
            messageLog += "Transcribing data...\n"
            await whisperContext.fullTranscribe(samples: data)
            let text = await whisperContext.getTranscription()
            messageLog += "\nUser: \(text)\n"
            await getAIResponse(text: text)
            
        } catch {
            print(error.localizedDescription)
            messageLog += "\(error.localizedDescription)\n"
        }
        
        canTranscribe = true
    }
    
    private func readAudioSamples(_ url: URL) throws -> [Float] {
        stopPlayback()
        try startPlayback(url)
        return try decodeWaveFile(url)
    }
    
    func toggleRecord() async {
        if isRecording {
            await recorder.stopRecording()
            isRecording = false
            if let recordedFile {
                await transcribeAudio(recordedFile)
            }
        } else {
            requestRecordPermission { granted in
                if granted {
                    Task {
                        do {
                            self.stopPlayback()
                            let file = try FileManager.default.url(for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
                                .appending(path: "output.wav")
                            try await self.recorder.startRecording(toOutputFile: file, delegate: self)
                            self.isRecording = true
                            self.recordedFile = file
                        } catch {
                            print(error.localizedDescription)
                            self.messageLog += "\(error.localizedDescription)\n"
                            self.isRecording = false
                        }
                    }
                }
            }
        }
    }
    
    private func requestRecordPermission(response: @escaping (Bool) -> Void) {
#if os(macOS)
        response(true)
#else
        AVAudioSession.sharedInstance().requestRecordPermission { granted in
            response(granted)
        }
#endif
    }
    
    private func startPlayback(_ url: URL) throws {
        audioPlayer = try AVAudioPlayer(contentsOf: url)
        audioPlayer?.play()
    }
    
    private func stopPlayback() {
        audioPlayer?.stop()
        audioPlayer = nil
    }
    
    // MARK: AVAudioRecorderDelegate
    
    nonisolated func audioRecorderEncodeErrorDidOccur(_ recorder: AVAudioRecorder, error: Error?) {
        if let error {
            Task {
                await handleRecError(error)
            }
        }
    }
    
    private func handleRecError(_ error: Error) {
        print(error.localizedDescription)
        messageLog += "\(error.localizedDescription)\n"
        isRecording = false
    }
    
    nonisolated func audioRecorderDidFinishRecording(_ recorder: AVAudioRecorder, successfully flag: Bool) {
        Task {
            await onDidFinishRecording()
        }
    }
    
    private func onDidFinishRecording() {
        isRecording = false
    }
}

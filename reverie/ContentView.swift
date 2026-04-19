import SwiftUI
import UniformTypeIdentifiers
import AVFoundation
import Combine
import QuartzCore
import UIKit

struct ContentView: View {
    @StateObject private var audioManager = AudioEngineManager()

    @State private var exportedFileURL: URL?
    @State private var showShareSheet = false
    @State private var isExporting = false

    @State private var isImporterPresented = false
    @State private var selectedFileName: String = "No file selected"
    @State private var importErrorMessage: String = ""
    @State private var showImportError = false
    @State private var waveformSamples: [CGFloat] = []

    var body: some View {
        VStack {
            if !audioManager.hasAudioLoaded {
                Spacer()
            }

            VStack(spacing: 24) {
                Text("Reverie")
                    .font(.system(.largeTitle, design: .monospaced))
                    .bold()
                    .foregroundColor(.white)

                Text(selectedFileName)
                    .font(.system(.subheadline, design: .monospaced))
                    .foregroundColor(.gray)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)

                Button {
                    isImporterPresented = true
                } label: {
                    Label("Import MP3", systemImage: "music.note")
                        .font(.system(.headline, design: .monospaced))
                        .padding()
                        .frame(maxWidth: .infinity)
                        .background(Color.indigo)
                        .foregroundColor(.white)
                        .cornerRadius(12)
                }
                .padding(.horizontal)

                /*
                Button {
                    do {
                        try audioManager.loadBundledMP3(named: "griffith_timeless")
                        selectedFileName = "griffith_timeless.MP3"

                        if let url = Bundle.main.url(forResource: "griffith_timeless", withExtension: "MP3")
                            ?? Bundle.main.url(forResource: "griffith_timeless", withExtension: "mp3") {
                            waveformSamples = WaveformExtractor.samples(from: url)
                        }
                    } catch {
                        importErrorMessage = error.localizedDescription
                        showImportError = true
                    }
                } label: {
                    Label("Load Test MP3", systemImage: "folder.fill")
                        .font(.system(.headline, design: .monospaced))
                        .padding()
                        .frame(maxWidth: .infinity)
                        .background(Color.orange)
                        .foregroundColor(.white)
                        .cornerRadius(12)
                }
                .padding(.horizontal)
                */

                if audioManager.hasAudioLoaded {
                    if !waveformSamples.isEmpty {
                        WaveformView(
                            samples: waveformSamples,
                            progress: audioManager.progress,
                            onSeek: { newProgress in
                                audioManager.seek(to: newProgress)
                            }
                        )
                        .padding(.horizontal)
                    }

                    HStack {
                        Text(formatTime(audioManager.currentTime))
                            .font(.system(.caption, design: .monospaced))
                            .foregroundColor(.white)

                        Spacer()

                        Text(formatTime(audioManager.duration))
                            .font(.system(.caption, design: .monospaced))
                            .foregroundColor(.gray)
                    }
                    .padding(.horizontal)

                    ProgressView(value: audioManager.progress)
                        .tint(.white)
                        .padding(.horizontal)

                    VStack(spacing: 12) {
                        Text("Slowed Amount")
                            .font(.system(.headline, design: .monospaced))
                            .foregroundColor(.white)

                        Slider(
                            value: Binding(
                                get: { Double(audioManager.rate) },
                                set: { audioManager.rate = Float($0) }
                            ),
                            in: 0.5...1.0
                        )
                        .padding(.horizontal)

                        Text(String(format: "Rate: %.2fx", audioManager.rate))
                            .font(.system(.subheadline, design: .monospaced))
                            .foregroundColor(.gray)

                        Text("Reverb")
                            .font(.system(.headline, design: .monospaced))
                            .foregroundColor(.white)
                            .padding(.top, 8)

                        Slider(
                            value: Binding(
                                get: { Double(audioManager.reverbMix) },
                                set: { audioManager.reverbMix = Float($0) }
                            ),
                            in: 0...100
                        )
                        .padding(.horizontal)

                        Text(String(format: "Wet/Dry Mix: %.0f%%", audioManager.reverbMix))
                            .font(.system(.subheadline, design: .monospaced))
                            .foregroundColor(.gray)
                    }
                    .padding(.horizontal)

                    HStack(spacing: 20) {
                        Button {
                            do {
                                try audioManager.togglePlayback()
                            } catch {
                                importErrorMessage = error.localizedDescription
                                showImportError = true
                            }
                        } label: {
                            Image(systemName: audioManager.isPlaying ? "pause.fill" : "play.fill")
                                .font(.system(size: 22, weight: .bold))
                                .frame(width: 56, height: 56)
                                .background(audioManager.isPlaying ? Color.orange : Color.green)
                                .foregroundColor(.white)
                                .clipShape(Circle())
                        }

                        Button {
                            audioManager.stop()
                        } label: {
                            Image(systemName: "stop.fill")
                                .font(.system(size: 22, weight: .bold))
                                .frame(width: 56, height: 56)
                                .background(Color.red)
                                .foregroundColor(.white)
                                .clipShape(Circle())
                        }
                    }
                    .padding(.horizontal)

                    Button {
                        Task {
                            do {
                                isExporting = true
                                let url = try audioManager.exportProcessedAudio()
                                exportedFileURL = url
                                showShareSheet = true
                                isExporting = false
                            } catch {
                                isExporting = false
                                importErrorMessage = error.localizedDescription
                                showImportError = true
                            }
                        }
                    } label: {
                        Label(isExporting ? "Exporting..." : "Export Audio", systemImage: "square.and.arrow.up")
                            .font(.system(.headline, design: .monospaced))
                            .padding()
                            .frame(maxWidth: .infinity)
                            .background(Color.blue)
                            .foregroundColor(.white)
                            .cornerRadius(12)
                    }
                    .padding(.horizontal)
                    .disabled(!audioManager.hasAudioLoaded || isExporting)
                }
            }

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black.ignoresSafeArea())
        .preferredColorScheme(.dark)
        .fileImporter(
            isPresented: $isImporterPresented,
            allowedContentTypes: [.mp3, .audio],
            allowsMultipleSelection: false
        ) { result in
            handleImport(result: result)
        }
        .alert("Error", isPresented: $showImportError) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(importErrorMessage)
        }
        .sheet(isPresented: $showShareSheet) {
            if let exportedFileURL {
                ShareSheet(activityItems: [exportedFileURL])
            }
        }
    }

    private func formatTime(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "0:00" }
        let total = Int(seconds)
        let mins = total / 60
        let secs = total % 60
        return String(format: "%d:%02d", mins, secs)
    }

    private func handleImport(result: Result<[URL], Error>) {
        do {
            let urls = try result.get()
            guard let pickedURL = urls.first else { return }

            let didAccess = pickedURL.startAccessingSecurityScopedResource()
            defer {
                if didAccess {
                    pickedURL.stopAccessingSecurityScopedResource()
                }
            }

            if !didAccess {
                throw NSError(
                    domain: "Import",
                    code: 1,
                    userInfo: [NSLocalizedDescriptionKey: "Couldn't access file."]
                )
            }

            let fileManager = FileManager.default
            let documentsDirectory = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first!
            let savedURL = documentsDirectory.appendingPathComponent(pickedURL.lastPathComponent)

            if fileManager.fileExists(atPath: savedURL.path) {
                try fileManager.removeItem(at: savedURL)
            }

            try fileManager.copyItem(at: pickedURL, to: savedURL)

            try audioManager.loadFile(from: savedURL)
            selectedFileName = savedURL.lastPathComponent
            waveformSamples = WaveformExtractor.samples(from: savedURL)
        } catch {
            importErrorMessage = error.localizedDescription
            showImportError = true
        }
    }
}

final class AudioEngineManager: NSObject, ObservableObject {
    @Published var isPlaying = false
    @Published var hasAudioLoaded = false
    @Published var rate: Float = 0.78 {
        didSet { timePitch.rate = rate }
    }
    @Published var reverbMix: Float = 35 {
        didSet { reverb.wetDryMix = reverbMix }
    }
    @Published var progress: Double = 0
    @Published var currentTime: Double = 0
    @Published var duration: Double = 0

    private let engine = AVAudioEngine()
    private let playerNode = AVAudioPlayerNode()
    private let timePitch = AVAudioUnitTimePitch()
    private let reverb = AVAudioUnitReverb()

    private var sourceURL: URL?
    private var audioFile: AVAudioFile?
    private var pausedFrame: AVAudioFramePosition = 0
    private var displayLink: CADisplayLink?
    private var playbackSessionID: Int = 0

    override init() {
        super.init()
        configureAudioSession()
        configureEngine()
    }

    private func configureEngine() {
        engine.attach(playerNode)
        engine.attach(timePitch)
        engine.attach(reverb)

        timePitch.rate = rate
        timePitch.pitch = -150

        reverb.loadFactoryPreset(.largeHall)
        reverb.wetDryMix = reverbMix

        let format = engine.mainMixerNode.outputFormat(forBus: 0)
        engine.connect(playerNode, to: timePitch, format: format)
        engine.connect(timePitch, to: reverb, format: format)
        engine.connect(reverb, to: engine.mainMixerNode, format: format)
    }

    private func configureAudioSession() {
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .default, options: [])
            try session.setActive(true)
        } catch {
            print("Audio session setup failed: \\(error)")
        }
    }

    func loadBundledMP3(named name: String) throws {
        guard let url = Bundle.main.url(forResource: name, withExtension: "MP3")
                ?? Bundle.main.url(forResource: name, withExtension: "mp3") else {
            throw NSError(
                domain: "Bundle",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Could not find \\(name).mp3 in the app bundle."]
            )
        }
        try loadFile(from: url)
    }

    func loadFile(from url: URL) throws {
        stop()
        sourceURL = url

        let file = try AVAudioFile(forReading: url)
        audioFile = file

        let sampleRate = file.processingFormat.sampleRate
        duration = sampleRate > 0 ? Double(file.length) / sampleRate : 0

        pausedFrame = 0
        progress = 0
        currentTime = 0
        hasAudioLoaded = true
    }

    func togglePlayback() throws {
        if isPlaying {
            pause()
        } else {
            try play()
        }
    }

    func play() throws {
        guard audioFile != nil else { return }

        if isPlaying { return }

        if !engine.isRunning {
            try engine.start()
        }

        let framesLeft = (audioFile?.length ?? 0) - pausedFrame
        guard framesLeft > 0, let audioFile else {
            pausedFrame = 0
            currentTime = 0
            progress = 0
            try play()
            return
        }

        playbackSessionID += 1
        let currentSessionID = playbackSessionID

        playerNode.stop()
        playerNode.scheduleSegment(
            audioFile,
            startingFrame: pausedFrame,
            frameCount: AVAudioFrameCount(framesLeft),
            at: nil
        ) { [weak self] in
            DispatchQueue.main.async {
                guard let self, self.playbackSessionID == currentSessionID else { return }
                self.isPlaying = false
                self.pausedFrame = 0
                self.progress = 0
                self.currentTime = 0
                self.stopDisplayLink()
            }
        }

        playerNode.play()
        isPlaying = true
        startDisplayLink()
    }

    func pause() {
        if !isPlaying {
            return
        }

        playbackSessionID += 1

        guard let nodeTime = playerNode.lastRenderTime,
              let playerTime = playerNode.playerTime(forNodeTime: nodeTime) else {
            playerNode.pause()
            isPlaying = false
            stopDisplayLink()
            return
        }

        let consumedFrames = AVAudioFramePosition(Double(playerTime.sampleTime) * Double(rate))
        pausedFrame += consumedFrames

        if let audioFile {
            pausedFrame = min(pausedFrame, audioFile.length)
        }

        playerNode.pause()
        isPlaying = false
        stopDisplayLink()
    }

    func stop() {
        playbackSessionID += 1
        playerNode.stop()
        engine.pause()
        pausedFrame = 0
        progress = 0
        currentTime = 0
        isPlaying = false
        stopDisplayLink()
    }

    func seek(to progressValue: Double) {
        guard let audioFile else { return }

        let clamped = min(max(progressValue, 0), 1)
        let targetFrame = AVAudioFramePosition(Double(audioFile.length) * clamped)

        pausedFrame = targetFrame
        progress = clamped
        currentTime = duration * clamped

        if isPlaying {
            playbackSessionID += 1
            playerNode.stop()
            isPlaying = false
            stopDisplayLink()
            try? play()
        }
    }

    private func startDisplayLink() {
        stopDisplayLink()
        displayLink = CADisplayLink(target: self, selector: #selector(updateProgress))
        displayLink?.add(to: .main, forMode: .common)
    }

    private func stopDisplayLink() {
        displayLink?.invalidate()
        displayLink = nil
    }

    @objc private func updateProgress() {
        guard let audioFile,
              isPlaying,
              let nodeTime = playerNode.lastRenderTime,
              let playerTime = playerNode.playerTime(forNodeTime: nodeTime) else { return }

        let sampleRate = audioFile.processingFormat.sampleRate
        let consumedFrames = AVAudioFramePosition(Double(playerTime.sampleTime) * Double(rate))
        let currentFrame = pausedFrame + consumedFrames
        let totalFrames = max(audioFile.length, 1)

        progress = min(max(Double(currentFrame) / Double(totalFrames), 0), 1)
        currentTime = sampleRate > 0 ? min(Double(currentFrame) / sampleRate, duration) : 0
    }

    func exportProcessedAudio() throws -> URL {
        guard let sourceURL else {
            throw NSError(
                domain: "Export",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "No audio file loaded."]
            )
        }

        let inputFile = try AVAudioFile(forReading: sourceURL)
        let inputFormat = inputFile.processingFormat

        let exportEngine = AVAudioEngine()
        let exportPlayer = AVAudioPlayerNode()
        let exportTimePitch = AVAudioUnitTimePitch()
        let exportReverb = AVAudioUnitReverb()

        exportEngine.attach(exportPlayer)
        exportEngine.attach(exportTimePitch)
        exportEngine.attach(exportReverb)

        exportTimePitch.rate = rate
        exportTimePitch.pitch = -150

        exportReverb.loadFactoryPreset(.largeHall)
        exportReverb.wetDryMix = reverbMix

        exportEngine.connect(exportPlayer, to: exportTimePitch, format: inputFormat)
        exportEngine.connect(exportTimePitch, to: exportReverb, format: inputFormat)
        exportEngine.connect(exportReverb, to: exportEngine.mainMixerNode, format: inputFormat)

        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("reverie-export-\\(UUID().uuidString).caf")

        let maxFrameCount: AVAudioFrameCount = 4096

        try exportEngine.enableManualRenderingMode(
            .offline,
            format: inputFormat,
            maximumFrameCount: maxFrameCount
        )

        let outputFile = try AVAudioFile(
            forWriting: outputURL,
            settings: exportEngine.manualRenderingFormat.settings,
            commonFormat: exportEngine.manualRenderingFormat.commonFormat,
            interleaved: exportEngine.manualRenderingFormat.isInterleaved
        )

        exportPlayer.scheduleFile(inputFile, at: nil)
        try exportEngine.start()
        exportPlayer.play()

        guard let buffer = AVAudioPCMBuffer(
            pcmFormat: exportEngine.manualRenderingFormat,
            frameCapacity: exportEngine.manualRenderingMaximumFrameCount
        ) else {
            throw NSError(
                domain: "Export",
                code: 2,
                userInfo: [NSLocalizedDescriptionKey: "Could not create render buffer."]
            )
        }

        while exportEngine.manualRenderingSampleTime < inputFile.length {
            let framesToRender = min(
                buffer.frameCapacity,
                AVAudioFrameCount(inputFile.length - exportEngine.manualRenderingSampleTime)
            )

            let status = try exportEngine.renderOffline(framesToRender, to: buffer)

            switch status {
            case .success:
                try outputFile.write(from: buffer)
            case .insufficientDataFromInputNode:
                break
            case .cannotDoInCurrentContext:
                continue
            case .error:
                throw NSError(
                    domain: "Export",
                    code: 3,
                    userInfo: [NSLocalizedDescriptionKey: "Offline render failed."]
                )
            @unknown default:
                throw NSError(
                    domain: "Export",
                    code: 4,
                    userInfo: [NSLocalizedDescriptionKey: "Unknown export error."]
                )
            }
        }

        exportPlayer.stop()
        exportEngine.stop()
        exportEngine.disableManualRenderingMode()

        return outputURL
    }
}

struct WaveformView: View {
    let samples: [CGFloat]
    let progress: Double
    let onSeek: (Double) -> Void

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let height = geometry.size.height
            let midY = height / 2
            let count = max(samples.count, 1)
            let step = width / CGFloat(count)
            let playedX = width * CGFloat(min(max(progress, 0), 1))

            ZStack(alignment: .leading) {
                ForEach(Array(samples.enumerated()), id: \.offset) { index, sample in
                    let x = CGFloat(index) * step
                    let amplitude = max(sample, 0.02) * (height / 2)
                    let isPlayed = x <= playedX

                    Path { path in
                        path.move(to: CGPoint(x: x, y: midY - amplitude))
                        path.addLine(to: CGPoint(x: x, y: midY + amplitude))
                    }
                    .stroke(
                        isPlayed ? Color.white : Color.white.opacity(0.35),
                        lineWidth: 2
                    )
                }
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        let x = min(max(value.location.x, 0), width)
                        onSeek(Double(x / width))
                    }
            )
        }
        .frame(height: 120)
        .background(Color.white.opacity(0.05))
        .cornerRadius(12)
    }
}

enum WaveformExtractor {
    static func samples(from url: URL, sampleCount: Int = 120) -> [CGFloat] {
        guard let file = try? AVAudioFile(forReading: url) else { return [] }

        let frameCount = AVAudioFrameCount(file.length)
        guard let buffer = AVAudioPCMBuffer(
            pcmFormat: file.processingFormat,
            frameCapacity: frameCount
        ) else { return [] }

        do {
            try file.read(into: buffer)
        } catch {
            return []
        }

        guard let channelData = buffer.floatChannelData?[0] else { return [] }

        let totalSamples = Int(buffer.frameLength)
        guard totalSamples > 0 else { return [] }

        let bucketSize = max(totalSamples / sampleCount, 1)
        var samples: [CGFloat] = []

        for start in stride(from: 0, to: totalSamples, by: bucketSize) {
            let end = min(start + bucketSize, totalSamples)
            var maxAmplitude: Float = 0

            for index in start..<end {
                let amplitude = abs(channelData[index])
                if amplitude > maxAmplitude {
                    maxAmplitude = amplitude
                }
            }

            samples.append(CGFloat(maxAmplitude))
        }

        return samples
    }
}

struct ShareSheet: UIViewControllerRepresentable {
    let activityItems: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) { }
}

extension UTType {
    static var mp3: UTType {
        UTType(filenameExtension: "mp3") ?? .audio
    }
}

#Preview {
    ContentView()
}

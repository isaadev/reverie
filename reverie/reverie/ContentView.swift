import SwiftUI
import UniformTypeIdentifiers
import AVFoundation
import Combine
import QuartzCore
import UIKit
import MediaPlayer

// MARK: - Models

struct QuickPreset: Identifiable {
    let id = UUID()
    let name: String
    let symbol: String
    let rate: Float
    let pitch: Float
    let reverbMix: Float
    let reverbPreset: AVAudioUnitReverbPreset
}

let kQuickPresets: [QuickPreset] = [
    .init(name: "slowed",    symbol: "🌊", rate: 0.85, pitch: -150, reverbMix: 30,  reverbPreset: .largeHall),
    .init(name: "dreamy",    symbol: "✨", rate: 0.78, pitch: -200, reverbMix: 65,  reverbPreset: .cathedral),
    .init(name: "deep",      symbol: "🌑", rate: 0.70, pitch: -300, reverbMix: 50,  reverbPreset: .largeChamber),
    .init(name: "lofi",      symbol: "📻", rate: 0.90, pitch: -100, reverbMix: 20,  reverbPreset: .mediumRoom),
    .init(name: "nightcore", symbol: "⚡", rate: 1.25, pitch: 350,  reverbMix: 10,  reverbPreset: .smallRoom),
]

struct ReverbPresetOption: Identifiable {
    let id: Int
    let label: String
    let preset: AVAudioUnitReverbPreset
}

let kReverbPresets: [ReverbPresetOption] = [
    .init(id: 0, label: "small room",  preset: .smallRoom),
    .init(id: 1, label: "medium hall", preset: .mediumHall),
    .init(id: 2, label: "large hall",  preset: .largeHall),
    .init(id: 3, label: "chamber",     preset: .largeChamber),
    .init(id: 4, label: "cathedral",   preset: .cathedral),
    .init(id: 5, label: "plate",       preset: .plate),
]

enum ExportError: LocalizedError {
    case sessionFailed, cancelled, unknown
    var errorDescription: String? {
        switch self {
        case .sessionFailed: return "Could not create export session."
        case .cancelled:     return "Export was cancelled."
        case .unknown:       return "Unknown export error."
        }
    }
}

// MARK: - YouTube Downloader

enum YouTubeError: LocalizedError {
    case invalidURL, apiError, noDownloadURL, downloadFailed
    var errorDescription: String? {
        switch self {
        case .invalidURL:     return "That doesn't look like a valid YouTube URL."
        case .apiError:       return "Couldn't contact YouTube. Check your connection."
        case .noDownloadURL:  return "No audio stream found. Video may be private or age-restricted."
        case .downloadFailed: return "Audio download failed."
        }
    }
}

enum YouTubeDownloader {

    // ── Our own yt-dlp backend (reverie/ytdl/main.py).
    // Run locally:  uvicorn main:app --port 8001
    // Or swap in your Render/Railway deploy URL.
    static var serviceBase = "http://192.168.1.19:8001"

    static func downloadAudio(from youtubeURL: String) async throws -> (url: URL, title: String) {
        guard youtubeURL.contains("youtube.com") || youtubeURL.contains("youtu.be") else {
            throw YouTubeError.invalidURL
        }

        // Build request to our backend
        var comps = URLComponents(string: "\(serviceBase)/audio")!
        comps.queryItems = [URLQueryItem(name: "url", value: youtubeURL)]
        guard let endpoint = comps.url else { throw YouTubeError.apiError }

        let req = URLRequest(url: endpoint, timeoutInterval: 90) // yt-dlp may take a moment

        guard let (tmpURL, resp) = try? await URLSession.shared.download(for: req),
              let httpResp = resp as? HTTPURLResponse
        else { throw YouTubeError.apiError }

        guard httpResp.statusCode == 200 else {
            throw httpResp.statusCode == 422 ? YouTubeError.noDownloadURL : YouTubeError.apiError
        }

        // Grab title from Content-Disposition: attachment; filename="Some Title.m4a"
        let disposition = httpResp.value(forHTTPHeaderField: "Content-Disposition") ?? ""
        var title = "youtube audio"
        if let range = disposition.range(of: "filename=\""),
           let end   = disposition[range.upperBound...].firstIndex(of: "\"") {
            let raw = String(disposition[range.upperBound..<end])
            title = raw.replacingOccurrences(of: ".m4a", with: "").lowercased()
        }

        // Move to app Documents
        let fm   = FileManager.default
        let docs = fm.urls(for: .documentDirectory, in: .userDomainMask).first!
        let dest = docs.appendingPathComponent("yt-\(UUID().uuidString).m4a")
        if fm.fileExists(atPath: dest.path) { try fm.removeItem(at: dest) }
        try fm.moveItem(at: tmpURL, to: dest)

        return (dest, title)
    }
}

// MARK: - Typewriter

struct TypewriterText: View {
    let fullText: String
    var speed: Double   = 0.055
    var font: Font      = .body
    var color: Color    = .white
    var showCursor: Bool = true

    @State private var charCount  = 0
    @State private var cursorOn   = true
    @State private var cursorTimer: Timer? = nil

    private var displayed: String { String(fullText.prefix(charCount)) }

    var body: some View {
        HStack(spacing: 0) {
            Text(displayed)
                .font(font)
                .foregroundColor(color)
            if showCursor {
                Text("▌")
                    .font(font)
                    .foregroundColor(color.opacity(cursorOn ? 0.55 : 0))
                    .animation(.linear(duration: 0.15), value: cursorOn)
            }
        }
        .onAppear { startTyping() }
        .onChange(of: fullText) { _ in charCount = 0; startTyping() }
        .onDisappear { cursorTimer?.invalidate() }
    }

    private func startTyping() {
        cursorTimer?.invalidate()
        charCount = 0
        let chars = fullText.count
        for i in 0..<chars {
            DispatchQueue.main.asyncAfter(deadline: .now() + speed * Double(i)) {
                charCount = i + 1
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + speed * Double(chars) + 0.1) {
            cursorTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { _ in
                cursorOn.toggle()
            }
        }
    }
}

// MARK: - ContentView

struct ContentView: View {
    @StateObject private var audioManager = AudioEngineManager()

    @State private var exportedFileURL: URL?
    @State private var showShareSheet      = false
    @State private var isExporting         = false
    @State private var isImporterPresented = false
    @State private var selectedFileName    = ""
    @State private var importErrorMessage  = ""
    @State private var showImportError     = false
    @State private var waveformSamples: [CGFloat] = []
    @State private var activePresetName: String?  = nil
    @State private var youtubeURL          = ""
    @State private var isDownloadingYouTube = false

    // Very dark purple-tinted black
    private let bgColor = Color(red: 0.02, green: 0.02, blue: 0.04)
    private let cardBg  = Color.white.opacity(0.028)
    private let border  = Color.white.opacity(0.06)

    var body: some View {
        ZStack {
            bgColor.ignoresSafeArea()

            // Faint ambient glow at top
            RadialGradient(
                colors: [Color.purple.opacity(0.09), Color.clear],
                center: .top, startRadius: 0, endRadius: 380
            )
            .ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(spacing: 22) {
                    headerSection
                    if audioManager.hasAudioLoaded {
                        waveformSection
                        presetsSection
                        playbackControls
                        effectsSection
                        exportButton
                    } else {
                        emptyState
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 24)
            }
        }
        .preferredColorScheme(.dark)
        .fileImporter(
            isPresented: $isImporterPresented,
            allowedContentTypes: [.mp3, .audio],
            allowsMultipleSelection: false,
            onCompletion: handleImport
        )
        .alert("error", isPresented: $showImportError) {
            Button("ok", role: .cancel) {}
        } message: {
            Text(importErrorMessage)
        }
        .sheet(isPresented: $showShareSheet) {
            if let exportedFileURL {
                ShareSheet(activityItems: [exportedFileURL])
            }
        }
    }

    // MARK: Header

    private var headerSection: some View {
        VStack(spacing: 8) {
            TypewriterText(
                fullText: "reverie",
                speed: 0.08,
                font: .system(size: 38, weight: .bold, design: .monospaced),
                color: .white
            )
            .tracking(8)

            if selectedFileName.isEmpty {
                TypewriterText(
                    fullText: "slowed · reverb · pitch",
                    speed: 0.035,
                    font: .system(.subheadline, design: .monospaced),
                    color: .white.opacity(0.28),
                    showCursor: false
                )
            } else {
                HStack(spacing: 5) {
                    Image(systemName: "music.note")
                        .font(.caption2)
                        .foregroundColor(.purple.opacity(0.6))
                    Text(selectedFileName.lowercased())
                        .font(.system(.subheadline, design: .monospaced))
                        .foregroundColor(.white.opacity(0.5))
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 4)
    }

    // MARK: Empty state

    private var emptyState: some View {
        VStack(spacing: 20) {
            Spacer().frame(height: 36)

            ZStack {
                Circle()
                    .fill(Color.purple.opacity(0.07))
                    .frame(width: 96, height: 96)
                Image(systemName: "waveform")
                    .font(.system(size: 40))
                    .foregroundColor(.purple.opacity(0.45))
            }

            VStack(spacing: 6) {
                TypewriterText(
                    fullText: "no audio loaded",
                    speed: 0.045,
                    font: .system(.headline, design: .monospaced),
                    color: .white.opacity(0.65)
                )
                Text("import a file or paste a youtube link")
                    .font(.system(.caption, design: .monospaced))
                    .foregroundColor(.white.opacity(0.25))
            }

            // YouTube input
            VStack(spacing: 10) {
                HStack(spacing: 10) {
                    Image(systemName: "play.rectangle.fill")
                        .foregroundColor(.red.opacity(0.65))
                        .font(.system(size: 16))

                    TextField("paste youtube url...", text: $youtubeURL)
                        .font(.system(.subheadline, design: .monospaced))
                        .foregroundColor(.white)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                        .onSubmit { Task { await handleYouTubeDownload() } }

                    if !youtubeURL.isEmpty {
                        Button { youtubeURL = "" } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(.white.opacity(0.25))
                        }
                    }
                }
                .padding(13)
                .background(cardBg)
                .cornerRadius(13)
                .overlay(RoundedRectangle(cornerRadius: 13).stroke(border, lineWidth: 1))

                Button { Task { await handleYouTubeDownload() } } label: {
                    HStack(spacing: 8) {
                        if isDownloadingYouTube {
                            ProgressView().tint(.white).scaleEffect(0.75)
                            Text("downloading...")
                        } else {
                            Image(systemName: "arrow.down.circle.fill")
                            Text("download & edit")
                        }
                    }
                    .font(.system(.subheadline, design: .monospaced, weight: .semibold))
                    .padding(.vertical, 13)
                    .frame(maxWidth: .infinity)
                    .background(
                        youtubeURL.isEmpty || isDownloadingYouTube
                            ? AnyView(Color.white.opacity(0.04))
                            : AnyView(LinearGradient(
                                colors: [Color.red.opacity(0.7), Color.orange.opacity(0.6)],
                                startPoint: .leading, endPoint: .trailing))
                    )
                    .foregroundColor(youtubeURL.isEmpty ? .white.opacity(0.2) : .white)
                    .cornerRadius(13)
                }
                .disabled(youtubeURL.isEmpty || isDownloadingYouTube)
            }

            HStack {
                Rectangle().fill(Color.white.opacity(0.06)).frame(height: 1)
                Text("or")
                    .font(.system(.caption, design: .monospaced))
                    .foregroundColor(.white.opacity(0.2))
                Rectangle().fill(Color.white.opacity(0.06)).frame(height: 1)
            }

            Button { isImporterPresented = true } label: {
                Label("import from files", systemImage: "folder")
                    .font(.system(.subheadline, design: .monospaced, weight: .semibold))
                    .padding(.vertical, 13)
                    .frame(maxWidth: .infinity)
                    .background(cardBg)
                    .foregroundColor(.white.opacity(0.55))
                    .cornerRadius(13)
                    .overlay(RoundedRectangle(cornerRadius: 13).stroke(border, lineWidth: 1))
            }

            Spacer().frame(height: 36)
        }
    }

    // MARK: Waveform

    private var waveformSection: some View {
        VStack(spacing: 10) {
            if !waveformSamples.isEmpty {
                WaveformView(
                    samples: waveformSamples,
                    progress: audioManager.progress,
                    onSeek: { audioManager.seek(to: $0) }
                )
            }
            HStack {
                Text(formatTime(audioManager.currentTime))
                    .font(.system(.caption, design: .monospaced))
                    .foregroundColor(.white.opacity(0.55))
                Spacer()
                Text(formatTime(audioManager.duration))
                    .font(.system(.caption, design: .monospaced))
                    .foregroundColor(.white.opacity(0.22))
            }
        }
        .padding(16)
        .background(cardBg)
        .cornerRadius(16)
    }

    // MARK: Quick Presets

    private var presetsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("presets")
                .font(.system(.caption, design: .monospaced, weight: .semibold))
                .foregroundColor(.white.opacity(0.28))
                .padding(.horizontal, 2)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(kQuickPresets) { preset in
                        Button { applyPreset(preset) } label: {
                            VStack(spacing: 5) {
                                Text(preset.symbol).font(.title3)
                                Text(preset.name)
                                    .font(.system(.caption, design: .monospaced, weight: .semibold))
                                    .foregroundColor(activePresetName == preset.name ? .white : .white.opacity(0.55))
                            }
                            .frame(width: 74, height: 64)
                            .background(
                                activePresetName == preset.name
                                    ? LinearGradient(colors: [.purple.opacity(0.7), .indigo.opacity(0.7)],
                                                     startPoint: .topLeading, endPoint: .bottomTrailing)
                                    : LinearGradient(colors: [cardBg, cardBg],
                                                     startPoint: .top, endPoint: .bottom)
                            )
                            .cornerRadius(14)
                            .overlay(
                                RoundedRectangle(cornerRadius: 14)
                                    .stroke(activePresetName == preset.name
                                            ? Color.purple.opacity(0.4)
                                            : border, lineWidth: 1)
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    // MARK: Playback controls

    private var playbackControls: some View {
        HStack(spacing: 0) {
            Button { isImporterPresented = true } label: {
                Image(systemName: "plus.circle")
                    .font(.system(size: 22))
                    .foregroundColor(.white.opacity(0.28))
                    .frame(maxWidth: .infinity)
            }

            Button { audioManager.seek(to: 0) } label: {
                Image(systemName: "backward.end.fill")
                    .font(.system(size: 20))
                    .foregroundColor(.white.opacity(0.45))
                    .frame(width: 50, height: 50)
                    .background(cardBg)
                    .clipShape(Circle())
                    .overlay(Circle().stroke(border, lineWidth: 1))
            }

            Button {
                do { try audioManager.togglePlayback() }
                catch { showError(error) }
            } label: {
                Image(systemName: audioManager.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 28, weight: .bold))
                    .foregroundColor(.white)
                    .frame(width: 68, height: 68)
                    .background(LinearGradient(
                        colors: [Color.purple.opacity(0.85), Color.indigo.opacity(0.85)],
                        startPoint: .topLeading, endPoint: .bottomTrailing
                    ))
                    .clipShape(Circle())
                    .shadow(color: .purple.opacity(0.35), radius: 14, x: 0, y: 4)
            }
            .padding(.horizontal, 16)

            Button { audioManager.stop() } label: {
                Image(systemName: "stop.fill")
                    .font(.system(size: 20))
                    .foregroundColor(.white.opacity(0.45))
                    .frame(width: 50, height: 50)
                    .background(cardBg)
                    .clipShape(Circle())
                    .overlay(Circle().stroke(border, lineWidth: 1))
            }

            Button { Task { await runExport() } } label: {
                Image(systemName: isExporting ? "ellipsis" : "square.and.arrow.up")
                    .font(.system(size: 20))
                    .foregroundColor(.white.opacity(0.28))
                    .frame(maxWidth: .infinity)
            }
            .disabled(isExporting)
        }
        .padding(.vertical, 8)
    }

    // MARK: Effects

    private var effectsSection: some View {
        VStack(spacing: 0) {
            EffectSlider(
                label: "speed",
                systemImage: "gauge.with.dots.needle.67percent",
                value: Binding(get: { Double(audioManager.rate) },
                               set: { audioManager.rate = Float($0) }),
                range: 0.5...1.5,
                displayValue: String(format: "%.2fx", audioManager.rate)
            )
            sectionDivider
            EffectSlider(
                label: "pitch",
                systemImage: "music.quarternote.3",
                value: Binding(get: { Double(audioManager.pitch) },
                               set: { audioManager.pitch = Float($0) }),
                range: -600...600,
                displayValue: pitchLabel(audioManager.pitch)
            )
            sectionDivider
            EffectSlider(
                label: "reverb",
                systemImage: "dot.radiowaves.left.and.right",
                value: Binding(get: { Double(audioManager.reverbMix) },
                               set: { audioManager.reverbMix = Float($0) }),
                range: 0...100,
                displayValue: String(format: "%.0f%%", audioManager.reverbMix)
            )
            sectionDivider
            reverbPresetRow
        }
        .background(cardBg)
        .cornerRadius(16)
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(border, lineWidth: 1))
    }

    private var sectionDivider: some View {
        Rectangle()
            .fill(Color.white.opacity(0.04))
            .frame(height: 1)
            .padding(.horizontal, 16)
    }

    private var reverbPresetRow: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: "building.columns")
                    .font(.caption)
                    .foregroundColor(.purple.opacity(0.5))
                Text("room")
                    .font(.system(.subheadline, design: .monospaced, weight: .medium))
                    .foregroundColor(.white.opacity(0.7))
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(kReverbPresets) { option in
                        let isActive = audioManager.selectedReverbPreset == option.preset
                        Button {
                            audioManager.selectedReverbPreset = option.preset
                            activePresetName = nil
                        } label: {
                            Text(option.label)
                                .font(.system(.caption, design: .monospaced, weight: .semibold))
                                .padding(.horizontal, 13)
                                .padding(.vertical, 7)
                                .background(isActive ? Color.purple.opacity(0.22) : Color.white.opacity(0.04))
                                .foregroundColor(isActive ? .white : .white.opacity(0.38))
                                .cornerRadius(20)
                                .overlay(Capsule().stroke(
                                    isActive ? Color.purple.opacity(0.45) : Color.clear, lineWidth: 1
                                ))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 16)
            }
            .padding(.bottom, 14)
        }
    }

    // MARK: Export button

    private var exportButton: some View {
        Button { Task { await runExport() } } label: {
            HStack {
                Image(systemName: isExporting ? "ellipsis" : "arrow.down.circle")
                Text(isExporting ? "exporting..." : "export as m4a")
            }
            .font(.system(.headline, design: .monospaced))
            .padding()
            .frame(maxWidth: .infinity)
            .background(cardBg)
            .foregroundColor(.white.opacity(0.6))
            .cornerRadius(14)
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(border, lineWidth: 1))
        }
        .disabled(isExporting)
    }

    // MARK: Helpers

    private func applyPreset(_ preset: QuickPreset) {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
            audioManager.rate                 = preset.rate
            audioManager.pitch                = preset.pitch
            audioManager.reverbMix            = preset.reverbMix
            audioManager.selectedReverbPreset = preset.reverbPreset
            activePresetName                  = preset.name
        }
    }

    private func pitchLabel(_ cents: Float) -> String {
        guard cents != 0 else { return "0 st" }
        return String(format: "%+.0f st", cents / 100)
    }

    private func formatTime(_ t: Double) -> String {
        guard t.isFinite, t >= 0 else { return "0:00" }
        let s = Int(t); return String(format: "%d:%02d", s / 60, s % 60)
    }

    private func showError(_ error: Error) {
        importErrorMessage = error.localizedDescription
        showImportError    = true
    }

    private func runExport() async {
        do {
            isExporting = true
            let url = try await audioManager.exportProcessedAudio()
            exportedFileURL = url
            showShareSheet  = true
        } catch { showError(error) }
        isExporting = false
    }

    private func handleYouTubeDownload() async {
        let trimmed = youtubeURL.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        isDownloadingYouTube = true
        do {
            let (fileURL, title) = try await YouTubeDownloader.downloadAudio(from: trimmed)
            try audioManager.loadFile(from: fileURL)
            selectedFileName        = title.lowercased()
            audioManager.trackName  = selectedFileName
            waveformSamples         = WaveformExtractor.samples(from: fileURL)
            activePresetName        = nil
            youtubeURL              = ""
        } catch { showError(error) }
        isDownloadingYouTube = false
    }

    private func handleImport(result: Result<[URL], Error>) {
        do {
            let urls = try result.get()
            guard let pickedURL = urls.first else { return }

            let didAccess = pickedURL.startAccessingSecurityScopedResource()
            defer { if didAccess { pickedURL.stopAccessingSecurityScopedResource() } }
            guard didAccess else {
                throw NSError(domain: "Import", code: 1,
                              userInfo: [NSLocalizedDescriptionKey: "couldn't access file."])
            }

            let fm   = FileManager.default
            let docs = fm.urls(for: .documentDirectory, in: .userDomainMask).first!
            let dest = docs.appendingPathComponent(pickedURL.lastPathComponent)
            if fm.fileExists(atPath: dest.path) { try fm.removeItem(at: dest) }
            try fm.copyItem(at: pickedURL, to: dest)

            try audioManager.loadFile(from: dest)
            selectedFileName       = dest.deletingPathExtension().lastPathComponent.lowercased()
            audioManager.trackName = selectedFileName
            waveformSamples        = WaveformExtractor.samples(from: dest)
            activePresetName       = nil
        } catch { showError(error) }
    }
}

// MARK: - EffectSlider

struct EffectSlider: View {
    let label: String
    let systemImage: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let displayValue: String

    var body: some View {
        VStack(spacing: 8) {
            HStack {
                Image(systemName: systemImage)
                    .font(.caption)
                    .foregroundColor(.purple.opacity(0.65))
                    .frame(width: 16)
                Text(label)
                    .font(.system(.subheadline, design: .monospaced, weight: .medium))
                    .foregroundColor(.white.opacity(0.8))
                Spacer()
                Text(displayValue)
                    .font(.system(.subheadline, design: .monospaced))
                    .foregroundColor(.purple.opacity(0.85))
                    .frame(minWidth: 54, alignment: .trailing)
            }
            Slider(value: $value, in: range)
                .tint(.purple)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }
}

// MARK: - AudioEngineManager

final class AudioEngineManager: NSObject, ObservableObject {
    @Published var isPlaying = false
    @Published var hasAudioLoaded = false
    @Published var trackName = ""

    @Published var rate: Float = 0.85 {
        didSet { timePitch.rate = rate; updateNowPlaying() }
    }
    @Published var pitch: Float = -150 {
        didSet { timePitch.pitch = pitch }
    }
    @Published var reverbMix: Float = 35 {
        didSet { reverb.wetDryMix = reverbMix }
    }
    @Published var selectedReverbPreset: AVAudioUnitReverbPreset = .largeHall {
        didSet { reverb.loadFactoryPreset(selectedReverbPreset) }
    }
    @Published var progress: Double = 0
    @Published var currentTime: Double = 0
    @Published var duration: Double = 0

    private let engine      = AVAudioEngine()
    private let playerNode  = AVAudioPlayerNode()
    private let timePitch   = AVAudioUnitTimePitch()
    private let reverb      = AVAudioUnitReverb()

    private var sourceURL: URL?
    private var audioFile: AVAudioFile?
    private var pausedFrame: AVAudioFramePosition = 0
    private var displayLink: CADisplayLink?
    private var playbackSessionID = 0

    override init() {
        super.init()
        configureAudioSession()
        configureEngine()
        setupRemoteCommandCenter()
    }

    // MARK: Engine setup

    private func configureEngine() {
        engine.attach(playerNode)
        engine.attach(timePitch)
        engine.attach(reverb)

        timePitch.rate  = rate
        timePitch.pitch = pitch
        reverb.loadFactoryPreset(selectedReverbPreset)
        reverb.wetDryMix = reverbMix

        let fmt = engine.mainMixerNode.outputFormat(forBus: 0)
        engine.connect(playerNode, to: timePitch, format: fmt)
        engine.connect(timePitch,  to: reverb,    format: fmt)
        engine.connect(reverb, to: engine.mainMixerNode, format: fmt)
    }

    private func configureAudioSession() {
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
        try? AVAudioSession.sharedInstance().setActive(true)
    }

    // MARK: Lock screen / Now Playing
    // NOTE: Enable "Audio, AirPlay, and Picture in Picture" background mode
    // in Xcode → Target → Signing & Capabilities → Background Modes.

    private func setupRemoteCommandCenter() {
        let c = MPRemoteCommandCenter.shared()
        c.playCommand.addTarget  { [weak self] _ in try? self?.play(); return .success }
        c.pauseCommand.addTarget { [weak self] _ in self?.pause();     return .success }
        c.togglePlayPauseCommand.addTarget { [weak self] _ in
            try? self?.togglePlayback(); return .success
        }
        c.changePlaybackPositionCommand.addTarget { [weak self] event in
            guard let e = event as? MPChangePlaybackPositionCommandEvent,
                  let d = self?.duration, d > 0 else { return .commandFailed }
            self?.seek(to: e.positionTime / d)
            return .success
        }
    }

    func updateNowPlaying() {
        var info: [String: Any] = [
            MPMediaItemPropertyTitle:              trackName.isEmpty ? "Unknown" : trackName,
            MPMediaItemPropertyArtist:             "Reverie",
            MPNowPlayingInfoPropertyElapsedPlaybackTime: currentTime,
            MPMediaItemPropertyPlaybackDuration:   duration,
            MPNowPlayingInfoPropertyPlaybackRate:  isPlaying ? Double(rate) : 0.0,
        ]
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }

    // MARK: Playback

    func loadFile(from url: URL) throws {
        stop()
        sourceURL = url
        let file = try AVAudioFile(forReading: url)
        audioFile = file
        let sr = file.processingFormat.sampleRate
        duration = sr > 0 ? Double(file.length) / sr : 0
        pausedFrame = 0; progress = 0; currentTime = 0
        hasAudioLoaded = true
        updateNowPlaying()
    }

    func togglePlayback() throws {
        isPlaying ? pause() : try play()
    }

    func play() throws {
        guard let audioFile else { return }
        if isPlaying { return }
        if !engine.isRunning { try engine.start() }

        let framesLeft = audioFile.length - pausedFrame
        if framesLeft <= 0 {
            pausedFrame = 0; currentTime = 0; progress = 0
            try play(); return
        }

        playbackSessionID += 1
        let sid = playbackSessionID
        playerNode.stop()
        playerNode.scheduleSegment(
            audioFile,
            startingFrame: pausedFrame,
            frameCount: AVAudioFrameCount(framesLeft),
            at: nil
        ) { [weak self] in
            DispatchQueue.main.async {
                guard let self, self.playbackSessionID == sid else { return }
                self.isPlaying = false
                self.pausedFrame = 0; self.progress = 0; self.currentTime = 0
                self.stopDisplayLink()
                self.updateNowPlaying()
            }
        }
        playerNode.play()
        isPlaying = true
        startDisplayLink()
        updateNowPlaying()
    }

    func pause() {
        guard isPlaying else { return }
        playbackSessionID += 1
        if let nodeTime = playerNode.lastRenderTime,
           let playerTime = playerNode.playerTime(forNodeTime: nodeTime) {
            let consumed = AVAudioFramePosition(Double(playerTime.sampleTime) * Double(rate))
            pausedFrame = min(pausedFrame + consumed, audioFile?.length ?? 0)
        }
        playerNode.pause()
        isPlaying = false
        stopDisplayLink()
        updateNowPlaying()
    }

    func stop() {
        playbackSessionID += 1
        playerNode.stop()
        engine.pause()
        pausedFrame = 0; progress = 0; currentTime = 0
        isPlaying = false
        stopDisplayLink()
        updateNowPlaying()
    }

    func seek(to p: Double) {
        guard let audioFile else { return }
        let clamped = min(max(p, 0), 1)
        pausedFrame  = AVAudioFramePosition(Double(audioFile.length) * clamped)
        progress     = clamped
        currentTime  = duration * clamped
        if isPlaying {
            playbackSessionID += 1
            playerNode.stop(); isPlaying = false
            stopDisplayLink()
            try? play()
        }
    }

    // MARK: Progress display link

    private func startDisplayLink() {
        stopDisplayLink()
        displayLink = CADisplayLink(target: self, selector: #selector(tick))
        displayLink?.add(to: .main, forMode: .common)
    }

    private func stopDisplayLink() {
        displayLink?.invalidate(); displayLink = nil
    }

    @objc private func tick() {
        guard let audioFile, isPlaying,
              let nodeTime = playerNode.lastRenderTime,
              let playerTime = playerNode.playerTime(forNodeTime: nodeTime) else { return }
        let sr = audioFile.processingFormat.sampleRate
        let consumed = AVAudioFramePosition(Double(playerTime.sampleTime) * Double(rate))
        let frame = pausedFrame + consumed
        progress    = min(max(Double(frame) / Double(max(audioFile.length, 1)), 0), 1)
        currentTime = sr > 0 ? min(Double(frame) / sr, duration) : 0
    }

    // MARK: Export (M4A)

    func exportProcessedAudio() async throws -> URL {
        let cafURL = try renderToCAF()
        let m4aURL = try await convertToM4A(cafURL: cafURL)
        try? FileManager.default.removeItem(at: cafURL)
        return m4aURL
    }

    private func renderToCAF() throws -> URL {
        guard let sourceURL else {
            throw NSError(domain: "Export", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "No audio file loaded."])
        }

        let inputFile   = try AVAudioFile(forReading: sourceURL)
        let inputFormat = inputFile.processingFormat

        let exportEngine    = AVAudioEngine()
        let exportPlayer    = AVAudioPlayerNode()
        let exportTimePitch = AVAudioUnitTimePitch()
        let exportReverb    = AVAudioUnitReverb()

        exportEngine.attach(exportPlayer)
        exportEngine.attach(exportTimePitch)
        exportEngine.attach(exportReverb)

        exportTimePitch.rate  = rate
        exportTimePitch.pitch = pitch
        exportReverb.loadFactoryPreset(selectedReverbPreset)
        exportReverb.wetDryMix = reverbMix

        exportEngine.connect(exportPlayer,    to: exportTimePitch, format: inputFormat)
        exportEngine.connect(exportTimePitch, to: exportReverb,    format: inputFormat)
        exportEngine.connect(exportReverb,    to: exportEngine.mainMixerNode, format: inputFormat)

        let cafURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("reverie-render-\(UUID().uuidString).caf")

        try exportEngine.enableManualRenderingMode(.offline, format: inputFormat, maximumFrameCount: 4096)
        let outputFile = try AVAudioFile(forWriting: cafURL,
                                         settings: exportEngine.manualRenderingFormat.settings,
                                         commonFormat: exportEngine.manualRenderingFormat.commonFormat,
                                         interleaved: exportEngine.manualRenderingFormat.isInterleaved)

        exportPlayer.scheduleFile(inputFile, at: nil)
        try exportEngine.start()
        exportPlayer.play()

        guard let buffer = AVAudioPCMBuffer(pcmFormat: exportEngine.manualRenderingFormat,
                                             frameCapacity: exportEngine.manualRenderingMaximumFrameCount)
        else {
            throw NSError(domain: "Export", code: 2,
                          userInfo: [NSLocalizedDescriptionKey: "Could not create render buffer."])
        }

        while exportEngine.manualRenderingSampleTime < inputFile.length {
            let remaining = AVAudioFrameCount(inputFile.length - exportEngine.manualRenderingSampleTime)
            let frames    = min(buffer.frameCapacity, remaining)
            let status    = try exportEngine.renderOffline(frames, to: buffer)
            switch status {
            case .success:              try outputFile.write(from: buffer)
            case .insufficientDataFromInputNode: break
            case .cannotDoInCurrentContext:      continue
            default:
                throw NSError(domain: "Export", code: 3,
                              userInfo: [NSLocalizedDescriptionKey: "Offline render failed."])
            }
        }

        exportPlayer.stop()
        exportEngine.stop()
        exportEngine.disableManualRenderingMode()
        return cafURL
    }

    private func convertToM4A(cafURL: URL) async throws -> URL {
        let asset     = AVURLAsset(url: cafURL)
        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("reverie-\(UUID().uuidString).m4a")

        guard let session = AVAssetExportSession(asset: asset,
                                                  presetName: AVAssetExportPresetAppleM4A)
        else { throw ExportError.sessionFailed }

        session.outputURL      = outputURL
        session.outputFileType = .m4a

        return try await withCheckedThrowingContinuation { continuation in
            session.exportAsynchronously {
                switch session.status {
                case .completed: continuation.resume(returning: outputURL)
                case .failed:    continuation.resume(throwing: session.error ?? ExportError.unknown)
                case .cancelled: continuation.resume(throwing: ExportError.cancelled)
                default:         continuation.resume(throwing: ExportError.unknown)
                }
            }
        }
    }
}

// MARK: - WaveformView

struct WaveformView: View {
    let samples: [CGFloat]
    let progress: Double
    let onSeek: (Double) -> Void

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            let mid = h / 2
            let count = max(samples.count, 1)
            let step = w / CGFloat(count)
            let playedX = w * CGFloat(min(max(progress, 0), 1))

            ZStack(alignment: .leading) {
                ForEach(Array(samples.enumerated()), id: \.offset) { i, sample in
                    let x = CGFloat(i) * step
                    let amp = max(sample, 0.02) * mid
                    let played = x <= playedX
                    Path { p in
                        p.move(to:    CGPoint(x: x, y: mid - amp))
                        p.addLine(to: CGPoint(x: x, y: mid + amp))
                    }
                    .stroke(played ? Color.purple.opacity(0.9) : Color.white.opacity(0.22),
                            lineWidth: 2)
                }
            }
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0).onChanged { v in
                onSeek(Double(min(max(v.location.x, 0), w) / w))
            })
        }
        .frame(height: 100)
        .background(Color.white.opacity(0.03))
        .cornerRadius(12)
    }
}

// MARK: - WaveformExtractor

enum WaveformExtractor {
    static func samples(from url: URL, count: Int = 120) -> [CGFloat] {
        guard let file = try? AVAudioFile(forReading: url) else { return [] }
        let frameCount = AVAudioFrameCount(file.length)
        guard let buf = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: frameCount),
              (try? file.read(into: buf)) != nil,
              let data = buf.floatChannelData?[0] else { return [] }
        let total = Int(buf.frameLength)
        guard total > 0 else { return [] }
        let bucket = max(total / count, 1)
        return stride(from: 0, to: total, by: bucket).map { start in
            let end = min(start + bucket, total)
            return CGFloat((start..<end).map { abs(data[$0]) }.max() ?? 0)
        }
    }
}

// MARK: - ShareSheet

struct ShareSheet: UIViewControllerRepresentable {
    let activityItems: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
    }
    func updateUIViewController(_ vc: UIActivityViewController, context: Context) {}
}

extension UTType {
    static var mp3: UTType { UTType(filenameExtension: "mp3") ?? .audio }
}

#Preview { ContentView() }

import AVFoundation
import Foundation
import ComputahSpeech

@MainActor final class Voice {
    var onText: ((String, Bool, String) -> Void)?
    var onEager: ((String, String) -> Void)?
    var onResumed: (() -> Void)?
    var onInputLost: (() -> Void)?
    var onTurnBegan: ((String) -> Void)?
    var onStatus: ((String) -> Void)?
    var onLevel: ((Double) -> Void)?
    var onProviderEvent: (([String: Any]) -> Void)?
    var onUsage: ((SpeechUsage) -> Void)?
    var onDiagnosticInputFinished: (() -> Void)?
    private(set) var isListening = false
    private var engine: AVAudioEngine?
    private var socket: URLSessionWebSocketTask?
    private var session: URLSession?
    private var sender: Task<Void, Never>?
    private var receiver: Task<Void, Never>?
    private var diagnosticProducer: Task<Void, Never>?
    private var audioFeed: AudioFeed?
    private var providerSession: SpeechProviderSession?
    private var usageReported = false
    private var generation = UUID()

    func start(configuration: SpeechProviderConfiguration, key: String, diagnosticPCM: Data? = nil) {
        guard !isListening else { return }
        guard !key.isEmpty, !key.contains("\n") else {
            onStatus?("Add \(configuration.credentialName) to .env.")
            return
        }
        generation = UUID()
        let id = generation
        usageReported = false
        onStatus?(diagnosticPCM == nil ? "Checking microphone…" : "Starting audio diagnostic…")
        Task {
            if diagnosticPCM == nil, !(await AVCaptureDevice.requestAccess(for: .audio)) {
                onStatus?("Enable microphone access for Computah.")
                return
            }
            guard generation == id else { return }
            do {
                try connect(
                    configuration: configuration, key: key, id: id,
                    diagnosticPCM: diagnosticPCM)
            }
            catch { stop(message: "Microphone could not start: \(error.localizedDescription)") }
        }
    }

    private func connect(
        configuration: SpeechProviderConfiguration, key: String, id: UUID,
        diagnosticPCM: Data?
    ) throws {
        let providerSession = SpeechSessionFactory.make(configuration: configuration, key: key)
        let urlSession = URLSession(configuration: .ephemeral)
        let socket = urlSession.webSocketTask(with: providerSession.request)
        self.session = urlSession
        self.socket = socket
        self.providerSession = providerSession
        socket.resume()

        let feed = AudioFeed(capacity: 32)
        audioFeed = feed
        if let diagnosticPCM {
            produceDiagnostic(diagnosticPCM, id: id, feed: feed)
        } else {
            try startMicrophone(feed: feed, id: id)
        }
        isListening = true
        onStatus?("Listening…")
        sender = Task {
            do {
                for message in try providerSession.openingMessages() {
                    try await socket.send(message)
                }
                for await chunk in feed.stream {
                    guard generation == id, feed.isIntact else { return }
                    for message in try providerSession.audioMessages(chunk) {
                        try await socket.send(message)
                    }
                }
                for message in try providerSession.closingMessages() {
                    try await socket.send(message)
                }
                if diagnosticPCM != nil, generation == id { onDiagnosticInputFinished?() }
            } catch {
                guard generation == id else { return }
                onInputLost?()
                stop(message: "Speech stream stopped: \(error.localizedDescription)")
            }
        }
        receiver = Task {
            do {
                while generation == id {
                    let message = try await socket.receive()
                    for event in try providerSession.consume(message) {
                        consume(event, id: id)
                    }
                }
            } catch {
                guard generation == id else { return }
                onInputLost?()
                stop(message: "Speech connection stopped: \(error.localizedDescription)")
            }
        }
    }

    /// Raw 16 kHz mono signed PCM16, plus trailing silence for provider turn detection.
    private func produceDiagnostic(_ pcm: Data, id: UUID, feed: AudioFeed) {
        diagnosticProducer = Task {
            let maximumBytes = SpeechDiagnosticLimit.maximumPCMBytes
            let silenceBytes = min(16_000 * 2 * 8, max(0, maximumBytes - pcm.count))
            let data = pcm + Data(repeating: 0, count: silenceBytes)
            for offset in stride(from: 0, to: data.count, by: 2_560) {
                guard generation == id, !Task.isCancelled else { return }
                guard feed.yield(data.subdata(in: offset..<min(offset + 2_560, data.count))) else {
                    loseAudio(id: id)
                    return
                }
                do { try await Task.sleep(nanoseconds: 80_000_000) }
                catch { return }
            }
            guard generation == id else { return }
            feed.finish()
        }
    }

    private func startMicrophone(feed: AudioFeed, id: UUID) throws {
        let audio = AVAudioEngine()
        let input = audio.inputNode
        let source = input.outputFormat(forBus: 0)
        guard source.sampleRate > 0, source.channelCount > 0,
              let destination = AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: 16_000,
                                              channels: 1, interleaved: false),
              let converter = AVAudioConverter(from: source, to: destination) else {
            throw NSError(domain: "Voice", code: 1, userInfo: [NSLocalizedDescriptionKey: "Unsupported microphone format"])
        }
        input.installTap(onBus: 0, bufferSize: 1024, format: source) { [weak self] buffer, _ in
            let capacity = AVAudioFrameCount(ceil(Double(buffer.frameLength) * 16_000 / source.sampleRate) + 32)
            guard let converted = AVAudioPCMBuffer(pcmFormat: destination, frameCapacity: capacity) else {
                feed.invalidate()
                Task { @MainActor [weak self] in self?.loseAudio(id: id) }
                return
            }
            var supplied = false
            var error: NSError?
            let status = converter.convert(to: converted, error: &error) { _, inputStatus in
                if supplied { inputStatus.pointee = .noDataNow; return nil }
                supplied = true
                inputStatus.pointee = .haveData
                return buffer
            }
            if status != .error, error == nil, let samples = converted.int16ChannelData?[0], converted.frameLength > 0 {
                let bytes = Data(bytes: samples, count: Int(converted.frameLength) * MemoryLayout<Int16>.size)
                guard feed.yield(bytes) else {
                    Task { @MainActor [weak self] in self?.loseAudio(id: id) }
                    return
                }
                let level = stride(from: 0, to: Int(converted.frameLength), by: 32).reduce(0.0) {
                    $0 + abs(Double(samples[$1]) / 32768)
                } / Double(max(1, Int(converted.frameLength) / 32))
                Task { @MainActor [weak self] in self?.onLevel?(min(1, level * 8)) }
            } else if status == .error || error != nil || converted.frameLength > 0 {
                feed.invalidate()
                Task { @MainActor [weak self] in self?.loseAudio(id: id) }
            }
        }
        do { try audio.start() }
        catch { input.removeTap(onBus: 0); throw error }
        engine = audio
    }

    private func consume(_ event: SpeechSessionEvent, id: UUID) {
        guard generation == id, audioFeed?.isIntact == true else { return }
        switch event {
        case .provider(let payload): onProviderEvent?(payload)
        case .turnBegan(let turnID): onTurnBegan?(turnID)
        case .text(let text, let final, let turnID): onText?(text, final, turnID)
        case .eager(let text, let turnID): onEager?(text, turnID)
        case .resumed: onResumed?()
        }
    }

    private func loseAudio(id: UUID) {
        guard generation == id else { return }
        onInputLost?()
        stop(message: "Audio was interrupted. Stopped the affected request; start listening again and repeat it.")
    }

    func stop(message: String = "Ready") {
        generation = UUID()
        if !usageReported, let usage = providerSession?.usage {
            usageReported = true
            onUsage?(usage)
        }
        audioFeed?.finish()
        audioFeed = nil
        engine?.inputNode.removeTap(onBus: 0)
        engine?.stop()
        engine = nil
        diagnosticProducer?.cancel()
        diagnosticProducer = nil
        sender?.cancel()
        receiver?.cancel()
        sender = nil
        receiver = nil
        socket?.cancel(with: .goingAway, reason: nil)
        socket = nil
        session?.invalidateAndCancel()
        session = nil
        providerSession = nil
        isListening = false
        onLevel?(0)
        onStatus?(message)
    }
}

/// A bounded transport must report loss before any later transcript is accepted.
/// The audio callback and socket consumer share continuity, not mutable voice UI state.
final class AudioFeed: @unchecked Sendable {
    let stream: AsyncStream<Data>
    private let continuation: AsyncStream<Data>.Continuation
    private let lock = NSLock()
    private var intact = true

    init(capacity: Int) {
        let pair = AsyncStream<Data>.makeStream(bufferingPolicy: .bufferingNewest(capacity))
        stream = pair.stream
        continuation = pair.continuation
    }

    var isIntact: Bool {
        lock.lock(); defer { lock.unlock() }
        return intact
    }

    func yield(_ data: Data) -> Bool {
        lock.lock(); defer { lock.unlock() }
        guard intact else { return false }
        if case .enqueued = continuation.yield(data) { return true }
        intact = false
        continuation.finish()
        return false
    }

    func invalidate() {
        lock.lock(); defer { lock.unlock() }
        intact = false
        continuation.finish()
    }

    func finish() { continuation.finish() }
}

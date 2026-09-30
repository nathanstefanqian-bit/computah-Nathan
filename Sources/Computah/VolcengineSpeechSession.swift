import ComputahSpeech
import Foundation

final class VolcengineSpeechSession: SpeechProviderSession {
    let request: URLRequest
    var usage: SpeechUsage? {
        let seconds = reportedAudioSeconds > 0 ? reportedAudioSeconds : Double(sentAudioBytes) / 32_000
        guard seconds > 0 else { return nil }
        return SpeechUsage(
            provider: .volcengine, audioSeconds: seconds,
            estimatedCostCNY: seconds / 3_600,
            providerReportedDuration: reportedAudioSeconds > 0)
    }

    private let requestID = UUID().uuidString
    private var pendingAudio = Data()
    private var sentAudioBytes = 0
    private var reportedAudioSeconds = 0.0
    private var lastSequence = 0
    private var beganTurns = Set<String>()
    private var finalizedUtterances = Set<String>()
    private var prefetchTracker = VolcenginePrefetchTracker()
    private let packetBytes = 16_000 * 2 / 5

    init(endpoint: URL, key: String, resourceID: String) {
        var request = URLRequest(url: endpoint)
        request.setValue(key, forHTTPHeaderField: "X-Api-Key")
        request.setValue(resourceID, forHTTPHeaderField: "X-Api-Resource-Id")
        request.setValue(requestID, forHTTPHeaderField: "X-Api-Request-Id")
        request.setValue("-1", forHTTPHeaderField: "X-Api-Sequence")
        request.setValue(UUID().uuidString, forHTTPHeaderField: "X-Api-Connect-Id")
        self.request = request
    }

    func openingMessages() throws -> [URLSessionWebSocketTask.Message] {
        let payload: [String: Any] = [
            "user": ["uid": UUID().uuidString],
            "audio": [
                "format": "pcm", "codec": "raw", "rate": 16_000,
                "bits": 16, "channel": 1,
            ],
            "request": [
                "model_name": "bigmodel",
                "enable_nonstream": true,
                "enable_itn": true,
                "enable_punc": true,
                "enable_ddc": true,
                "show_utterances": true,
                "end_window_size": 800,
            ],
        ]
        let json = try JSONSerialization.data(withJSONObject: payload)
        return [.data(try VolcengineASRProtocol.fullRequest(json: json))]
    }

    func audioMessages(_ pcm: Data) throws -> [URLSessionWebSocketTask.Message] {
        pendingAudio.append(pcm)
        var messages: [URLSessionWebSocketTask.Message] = []
        while pendingAudio.count >= packetBytes {
            let chunk = pendingAudio.prefix(packetBytes)
            pendingAudio.removeFirst(packetBytes)
            sentAudioBytes += chunk.count
            messages.append(.data(try VolcengineASRProtocol.audio(Data(chunk))))
        }
        return messages
    }

    func closingMessages() throws -> [URLSessionWebSocketTask.Message] {
        var messages: [URLSessionWebSocketTask.Message] = []
        if !pendingAudio.isEmpty {
            sentAudioBytes += pendingAudio.count
            messages.append(.data(try VolcengineASRProtocol.audio(pendingAudio)))
            pendingAudio.removeAll(keepingCapacity: false)
        }
        messages.append(.data(try VolcengineASRProtocol.audio(Data(), final: true)))
        return messages
    }

    func consume(_ message: URLSessionWebSocketTask.Message) throws -> [SpeechSessionEvent] {
        guard case .data(let data) = message else { throw SpeechSessionError.unexpectedMessage }
        let frame = try VolcengineASRProtocol.parseServerFrame(data)
        if let sequence = frame.sequence {
            let ordinal = abs(Int(sequence))
            guard ordinal > lastSequence else { throw SpeechSessionError.outOfOrderResponse }
            lastSequence = ordinal
        }
        if frame.messageType == VolcengineASRProtocol.errorResponse {
            let detail = String(data: frame.payload, encoding: .utf8) ?? "Unknown provider error"
            throw SpeechSessionError.providerRejected(
                "Volcengine rejected the speech stream (\(frame.errorCode ?? 0)): \(detail)")
        }
        guard frame.messageType == VolcengineASRProtocol.fullServerResponse,
              let payload = try JSONSerialization.jsonObject(with: frame.payload) as? [String: Any]
        else { throw SpeechSessionError.malformedResponse }

        let code = integer(payload["code"] ?? payload["status_code"]) ?? 0
        guard [0, 1_000, 20_000_000].contains(code) else {
            let detail = payload["message"] as? String ?? payload["error"] as? String ?? "Unknown provider error"
            throw SpeechSessionError.providerRejected("Volcengine ASR error \(code): \(detail)")
        }
        var events: [SpeechSessionEvent] = [.provider(payload)]
        let decoded = VolcengineTranscriptDecoder.decode(payload, finalFrame: frame.isFinal)
        reportedAudioSeconds = max(reportedAudioSeconds, decoded.audioMilliseconds / 1_000)
        for transcript in decoded.transcripts {
            let turnID = "\(requestID):\(transcript.turnKey)"
            if transcript.final,
               !finalizedUtterances.insert(transcript.deduplicationKey).inserted {
                continue
            }
            begin(turnID, events: &events)
            events.append(.text(
                transcript.text, final: transcript.final, turnID: turnID))
            for transition in prefetchTracker.transitions(
                turnID: turnID, text: transcript.text,
                final: transcript.final, prefetch: decoded.prefetch
            ) {
                switch transition {
                case .cancel:
                    events.append(.resumed)
                case .prepare(let text):
                    events.append(.eager(text, turnID: turnID))
                }
            }
        }
        return events
    }

    private func begin(_ turnID: String, events: inout [SpeechSessionEvent]) {
        if beganTurns.insert(turnID).inserted { events.append(.turnBegan(turnID)) }
    }

    private func integer(_ value: Any?) -> Int? {
        if let number = value as? NSNumber { return number.intValue }
        if let string = value as? String { return Int(string) }
        return nil
    }
}

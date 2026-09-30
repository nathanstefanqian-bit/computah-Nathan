import ComputahCore
import ComputahSpeech
import Foundation

private func check(_ condition: @autoclosure () -> Bool, _ message: String) {
    guard condition() else {
        fputs("FAIL: \(message)\n", stderr)
        exit(1)
    }
}

private func appendUInt32(_ value: UInt32, to data: inout Data) {
    data.append(contentsOf: [
        UInt8((value >> 24) & 0xFF), UInt8((value >> 16) & 0xFF),
        UInt8((value >> 8) & 0xFF), UInt8(value & 0xFF),
    ])
}

do {
    let defaultProvider = try JevProviderConfiguration.resolve(nil)
    check(defaultProvider == .typeSafe, "default provider")
    let openRouter = try JevProviderConfiguration.resolve("openrouter")
    check(openRouter.endpoint.absoluteString == "https://openrouter.ai/api/alpha/decisions", "OpenRouter endpoint")
    check(openRouter.model == "typesafe/jev-1.13", "OpenRouter model")
    check(openRouter.credentialName == "OPENROUTER_API_KEY", "OpenRouter credential")

    do {
        _ = try JevProviderConfiguration.resolve("unknown")
        check(false, "unsupported provider must fail")
    } catch {}

    let actual = JevCosts()
    actual.setEnabled(true)
    let actualTicket = actual.beginRequest()
    check(actualTicket != nil, "actual cost ticket")
    actual.received(
        actualTicket, model: openRouter.model,
        inputTokens: 392, reportedCostUSD: 0.0000161)
    check(actual.snapshot.requests == 1, "actual request count")
    check(actual.snapshot.inputTokens == 392, "actual input tokens")
    check(abs(actual.snapshot.reportedUSD - 0.0000161) < 0.000000001, "provider-reported cost")
    check(actual.snapshot.estimatedUSD == 0, "actual cost must not be double counted")

    for model in ["jev-1.13.0", "typesafe/jev-1.13"] {
        let fallback = JevCosts()
        fallback.setEnabled(true)
        let ticket = fallback.beginRequest()
        fallback.received(ticket, model: model, inputTokens: 1_000_000, reportedCostUSD: nil)
        check(abs(fallback.snapshot.estimatedUSD - 0.042) < 0.000000001, "fallback price for \(model)")
    }

    let budget = JevRequestBudget(limit: 3)
    try budget.admit()
    try budget.admit()
    try budget.admit()
    do {
        try budget.admit()
        check(false, "fourth request must be rejected")
    } catch {}
    check(budget.used == 3, "request budget count")

    let defaultSpeech = try SpeechProviderConfiguration.resolve(nil)
    check(defaultSpeech == .deepgram, "default speech provider")
    check(defaultSpeech.provider.recognitionLabel == "Deepgram Speech Recognition", "Deepgram label")
    let volc = try SpeechProviderConfiguration.resolve("volcengine")
    check(volc.provider == .volcengine, "Volcengine speech provider")
    check(volc.provider.recognitionLabel == "Volcengine Speech Recognition", "Volcengine label")
    check(volc.credentialName == "VOLCENGINE_SPEECH_API_KEY", "Volcengine credential")
    check(volc.resourceID == "volc.seedasr.sauc.duration", "Volcengine resource")
    check(SpeechDiagnosticLimit.maximumPCMBytes == 960_000, "30-second speech diagnostic limit")
    do {
        _ = try SpeechProviderConfiguration.resolve("unknown")
        check(false, "unsupported speech provider must fail")
    } catch {}

    let payload = try JSONSerialization.data(withJSONObject: [
        "code": 20_000_000,
        "result": ["utterances": [["text": "你好", "definite": true]]],
    ])
    var compressedFrame = try VolcengineASRProtocol.fullRequest(json: payload)
    compressedFrame[1] = 0x92
    let parsedCompressed = try VolcengineASRProtocol.parseServerFrame(compressedFrame)
    check(parsedCompressed.messageType == VolcengineASRProtocol.fullServerResponse, "compressed response type")
    check(parsedCompressed.isFinal, "final response flag")
    check(parsedCompressed.payload == payload, "gzip response payload")

    var sequencedFrame = Data(compressedFrame.prefix(4))
    sequencedFrame[1] = 0x91
    sequencedFrame.append(contentsOf: [0, 0, 0, 7])
    sequencedFrame.append(compressedFrame.dropFirst(4))
    let parsedSequence = try VolcengineASRProtocol.parseServerFrame(sequencedFrame)
    check(parsedSequence.sequence == 7, "response sequence")

    var plainFrame = Data([0x11, 0x90, 0x10, 0])
    appendUInt32(UInt32(payload.count), to: &plainFrame)
    plainFrame.append(payload)
    let parsedPlain = try VolcengineASRProtocol.parseServerFrame(plainFrame)
    check(parsedPlain.payload == payload, "plain response payload")

    var malformed = plainFrame
    malformed.removeLast()
    do {
        _ = try VolcengineASRProtocol.parseServerFrame(malformed)
        check(false, "malformed response must fail")
    } catch {}

    let interim = VolcengineTranscriptDecoder.decode([
        "result": ["utterances": [
            ["text": "打开备忘录", "start_time": 120, "end_time": 900, "definite": false],
            ["text": "   ", "start_time": 900, "end_time": 1_000, "definite": true],
        ]],
    ], finalFrame: false)
    check(interim.transcripts.count == 1, "empty transcripts must be rejected")
    check(interim.transcripts[0].final == false, "interim transcript")
    check(interim.audioMilliseconds == 1_000, "utterance duration")

    let definite = VolcengineTranscriptDecoder.decode([
        "result": ["utterances": [
            ["text": "打开备忘录", "start_time": 120, "end_time": 900, "definite": true],
        ]],
    ], finalFrame: false)
    check(definite.transcripts.first?.final == true, "definite second-pass transcript")

    let finalFallback = VolcengineTranscriptDecoder.decode([
        "result": ["text": "写入今天的计划"],
    ], finalFrame: true)
    check(finalFallback.transcripts.first?.final == true, "final-frame fallback transcript")

    let projectRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    let promptData = try Data(contentsOf: projectRoot.appendingPathComponent(
        "Sources/ComputahCore/Prompts/language.json"))
    let promptDocument = try JSONSerialization.jsonObject(with: promptData) as! [String: Any]
    let prompts = promptDocument["prompts"] as! [String: String]
    check(
        prompts["format"]?.contains("unspecified content does not supply a literal value") == true,
        "vague text must not become invented literal content")
    check(
        prompts["action"]?.contains("choose its text-entry action directly") == true,
        "explicit text should select the offered editor")
    check(
        prompts["operation_pressClick"]?.contains("already selected container") == true,
        "selected containers must not replace available text entry")
} catch {
    fputs("FAIL: \(error.localizedDescription)\n", stderr)
    exit(1)
}

print("ComputahCore checks passed")

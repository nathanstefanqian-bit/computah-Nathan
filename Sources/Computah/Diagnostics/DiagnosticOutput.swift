import ComputahCore
import Foundation

enum DiagnosticOutcome: String, Encodable {
    case completed, unconfirmed, failed, timedOut
    var exitCode: Int32 {
        switch self {
        case .completed: return 0
        case .unconfirmed: return 2
        case .failed: return 1
        case .timedOut: return 124
        }
    }
}

/// One report boundary for every headless diagnostic. A failed write is a failed run.
enum DiagnosticOutput {
    static func write<Report: Encodable>(
        _ report: Report, outcome: DiagnosticOutcome,
        error: String? = nil, additional: [String: Any] = [:], to destination: URL?
    ) throws -> Data {
        let encoder = JSONEncoder()
        guard var body = try JSONSerialization.jsonObject(with: encoder.encode(report)) as? [String: Any] else {
            throw AXFailure.unavailable("Diagnostic report must be an object.")
        }
        body.merge(additional) { _, extra in extra }
        body["diagnosticOutcome"] = outcome.rawValue
        body["diagnosticError"] = error
        let data = try JSONSerialization.data(
            withJSONObject: SensitiveText.json(body), options: [.prettyPrinted, .sortedKeys])
        if let destination { try PrivateFile.write(data, to: destination) }
        return data
    }
}

extension App {
    func finishDiagnostic<Report: Encodable>(
        _ report: Report, outcome: DiagnosticOutcome, error: String? = nil, additional: [String: Any] = [:]
    ) -> Never {
        coordinator.onStatus = nil
        coordinator.onResult = nil
        voice.onStatus = nil
        coordinator.shutdown()
        voice.stop()
        jevCosts.flush()
        speechCosts.flush()
        var code = outcome.exitCode
        do {
            var metadata: [String: Any] = [
                "jevRequestLimit": LaunchOptions.current.isLiveDiagnostic ? LaunchOptions.liveJevRequestLimit : 0,
                "maxEstimatedJevCostUSD": LaunchOptions.current.isLiveDiagnostic
                    ? Double(LaunchOptions.liveJevRequestLimit) * 32_000 * JevCosts.inputUSDPerMillion / 1_000_000
                    : 0,
            ]
            metadata.merge(additional) { _, extra in extra }
            let data = try DiagnosticOutput.write(
                report, outcome: outcome, error: error, additional: metadata,
                to: LaunchOptions.current.value("--report").map { URL(fileURLWithPath: $0) })
            print(String(decoding: data, as: UTF8.self))
        } catch {
            code = DiagnosticOutcome.failed.exitCode
            fputs("Diagnostic report failed: \(SensitiveText.redact(error.localizedDescription))\n", stderr)
        }
        fflush(stdout)
        fflush(stderr)
        exit(code)
    }

    func failDiagnostic(_ error: Error) -> Never {
        finishDiagnostic([String: String](), outcome: .failed, error: error.localizedDescription)
    }
}

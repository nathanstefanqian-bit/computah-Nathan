import Combine
import ComputahCore
import ComputahSpeech
import Foundation

struct SpeechCostTotal: Codable, Equatable {
    var since = Date()
    var sessions = 0
    var audioSeconds = 0.0
    var estimatedCNY = 0.0
    var providerReportedSessions = 0
}

@MainActor final class SpeechCostStore: ObservableObject {
    @Published private(set) var total: SpeechCostTotal
    @Published private(set) var storageError: String?
    private let file: URL
    private let writer = DispatchQueue(label: "computah.speech-costs", qos: .utility)
    private var canSave = true

    init(file: URL) {
        self.file = file
        var restored = SpeechCostTotal()
        var failure: String?
        if FileManager.default.fileExists(atPath: file.path) {
            do { restored = try JSONDecoder().decode(SpeechCostTotal.self, from: Data(contentsOf: file)) }
            catch { failure = "Saved speech cost totals could not be read. Reset to start a new total." }
        }
        total = restored
        storageError = failure
        canSave = failure == nil
    }

    func record(_ usage: SpeechUsage) {
        guard usage.provider == .volcengine, usage.audioSeconds.isFinite,
              usage.audioSeconds > 0, usage.estimatedCostCNY.isFinite,
              usage.estimatedCostCNY >= 0 else { return }
        total.sessions += 1
        total.audioSeconds += usage.audioSeconds
        total.estimatedCNY += usage.estimatedCostCNY
        if usage.providerReportedDuration { total.providerReportedSessions += 1 }
        save()
    }

    func reset() {
        total = SpeechCostTotal()
        canSave = true
        storageError = nil
        save()
    }

    private func save() {
        guard canSave else { return }
        do {
            let data = try JSONEncoder().encode(total)
            let destination = file
            writer.async { [weak self] in
                do { try PrivateFile.write(data, to: destination) }
                catch {
                    Task { @MainActor [weak self] in
                        self?.storageError = "Speech cost totals could not be saved."
                    }
                }
            }
        } catch { storageError = "Speech cost totals could not be saved." }
    }

    func flush() { writer.sync {} }
}

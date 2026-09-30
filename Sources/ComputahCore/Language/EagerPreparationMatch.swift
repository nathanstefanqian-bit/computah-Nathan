import Foundation

/// Speculative plans may cross finalization only when recognition added no new meaning.
public enum EagerPreparationMatch {
    public static func canReuse(prepared: String, final: String) -> Bool {
        if prepared == final { return true }
        guard !prepared.isEmpty, final.hasPrefix(prepared) else { return false }
        let suffix = final.dropFirst(prepared.count)
        guard !suffix.isEmpty else { return false }
        let allowed = CharacterSet.whitespacesAndNewlines.union(.punctuationCharacters)
        return suffix.unicodeScalars.allSatisfy(allowed.contains)
    }
}

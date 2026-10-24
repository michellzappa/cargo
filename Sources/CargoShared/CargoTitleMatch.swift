import Foundation

/// Title matching shared by the macOS resident and iOS companion.
///
/// Matching compares whole words, never raw substrings. A raw `contains` let a
/// short title such as "Pi" match "Spider-Man" and "episode", so every such
/// transfer showed the same poster.
enum CargoTitleMatch {
    /// Lowercases, replaces punctuation with spaces, and collapses whitespace.
    static func normalize(_ value: String) -> String {
        value
            .lowercased()
            .replacingOccurrences(of: "[^a-z0-9]+", with: " ", options: .regularExpression)
            .split(separator: " ")
            .joined(separator: " ")
    }

    /// True when one title equals the other or appears in it as a whole-word run.
    static func matches(_ lhs: String, _ rhs: String) -> Bool {
        contains(lhs, title: rhs) || contains(rhs, title: lhs)
    }

    /// True when `title` appears in `haystack` as a whole-word run.
    static func contains(_ haystack: String, title: String) -> Bool {
        let needle = normalize(title)
        guard !needle.isEmpty else { return false }
        return " \(normalize(haystack)) ".contains(" \(needle) ")
    }
}

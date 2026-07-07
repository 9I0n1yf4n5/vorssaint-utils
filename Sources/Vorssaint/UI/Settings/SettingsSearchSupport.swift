// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// Pure filtering for the Settings sidebar search field, so the matching
/// rules (case, accents, word prefixes) are covered by the unit harness.
enum SettingsSearchSupport {
    /// Case-, diacritic- and width-insensitive containment: "métr" finds
    /// "Metrics", "moni" finds "Monitor". A blank query matches everything.
    /// Keywords let a page match by what lives inside it ("lid" finds
    /// Energy, "quick panel" finds Quick tools), not just by its name.
    static func matches(query: String, title: String, keywords: [String] = []) -> Bool {
        let folded = fold(query)
        guard !folded.isEmpty else { return true }
        if fold(title).contains(folded) { return true }
        return keywords.contains { fold($0).contains(folded) }
    }

    /// Keeps only the sections that still have items for the query, so an
    /// empty section never renders just its header.
    static func filteredIndices(query: String,
                                sections: [[String]]) -> [[Int]] {
        sections.map { titles in
            titles.indices.filter { matches(query: query, title: titles[$0]) }
        }
    }

    private static func fold(_ value: String) -> String {
        value
            .folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive],
                     locale: .current)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

import Foundation

/// The recipient's address window on page 1 (redaction v2 plan §1, L2).
///
/// A letter prints the reader's name and address in a fixed place -- the
/// envelope's window -- so the block is found by position rather than by
/// guessing at what a name looks like:
///
/// - **Rectified pages** (document camera, or perspective-corrected): the
///   lines inside the standard window rectangles, chosen by the page's
///   aspect ratio and the country -- A4 left and right windows per NEN/DIN
///   5008, the UK DL and C5 positions, the US #10 window.
/// - **Not rectified** (a photo from the library): no rectangle means
///   anything there, so only the cluster's shape is used.
///
/// Either way the answer is one cluster of 2–7 left-aligned lines whose last
/// or second-to-last line has the country's postcode shape, with a small
/// return-address line above it left out. It becomes one window claim: the
/// engine masks it as one `[ADDRESS_n]`, the name inside it included.
public enum AddressWindow {

    /// A rectangle on the page in millimetres from the left and from the
    /// top, the way the standards give them.
    struct Rectangle {
        var left: Double
        var right: Double
        var top: Double
        var bottom: Double
    }

    /// A4, 210 × 297 mm. Generous: positions vary by a few millimetres
    /// between senders and a scan is never exactly square to the paper.
    static let a4Left = Rectangle(left: 12, right: 112, top: 22, bottom: 105)
    static let a4Right = Rectangle(left: 98, right: 198, top: 22, bottom: 105)
    /// UK: the DL window (left) and the C5 window (right) on A4.
    static let ukDL = Rectangle(left: 12, right: 118, top: 30, bottom: 105)
    static let ukC5 = Rectangle(left: 92, right: 200, top: 30, bottom: 105)
    /// US Letter, 215.9 × 279.4 mm: the #10 envelope's window, about
    /// 0.875–4.375 in from the left and 2.0–3.125 in from the top.
    static let us10 = Rectangle(left: 12, right: 125, top: 35, bottom: 95)

    /// The window claim for page 1, or nil when no cluster qualifies.
    public static func find(in text: String, layout: LetterLayout, countryHint: String? = nil) -> KnownClaim? {
        guard let page = layout.pages.first, !page.lines.isEmpty else { return nil }
        let country = countryHint?.uppercased()
        let ratio = (page.heightMM ?? 297) / (page.widthMM ?? 210)
        let usLetter = abs(ratio - 279.4 / 215.9) < abs(ratio - 297.0 / 210.0) || (country == "US" && page.heightMM == nil)
        let widthMM = page.widthMM ?? (usLetter ? 215.9 : 210)
        let heightMM = page.heightMM ?? (usLetter ? 279.4 : 297)

        let candidates: [[LayoutLine]]
        if page.rectified {
            let rectangles: [Rectangle] = usLetter ? [us10] : country == "GB" ? [ukDL, ukC5] : [a4Left, a4Right]
            candidates = rectangles.map { rectangle in
                page.lines.filter { line in
                    let x = line.box.midX * widthMM
                    let fromTop = (1 - line.box.midY) * heightMM
                    return x >= rectangle.left && x <= rectangle.right && fromTop >= rectangle.top && fromTop <= rectangle.bottom
                }
            }
        } else {
            candidates = [page.lines.filter { $0.box.midY > 0.5 }]
        }

        var best: (score: Int, lines: [LayoutLine])?
        for lines in candidates {
            for cluster in clusters(of: lines) {
                guard let block = qualified(cluster, country: country) else { continue }
                let value = score(block, among: page.lines, rectified: page.rectified)
                if value > (best?.score ?? Int.min) { best = (value, block) }
            }
        }
        // Without rectangles the shape must also look like a recipient: a
        // sender's letterhead has the same shape.
        guard let best, page.rectified || best.score > 0 else { return nil }

        let ranges: [Range<String.Index>] = best.lines.compactMap { line in
            guard line.characterOffset >= 0, line.characterOffset + line.text.count <= text.count else { return nil }
            let start = text.index(text.startIndex, offsetBy: line.characterOffset)
            let end = text.index(start, offsetBy: line.text.count)
            guard text[start..<end] == line.text else { return nil }
            return start..<end
        }
        guard ranges.count == best.lines.count else { return nil }
        return KnownClaim(kind: .address, ranges: ranges, source: .window)
    }

    // MARK: - Clusters

    /// Left-aligned runs of lines, each directly below the last, top to bottom.
    static func clusters(of lines: [LayoutLine]) -> [[LayoutLine]] {
        let sorted = lines.sorted { $0.box.maxY > $1.box.maxY }
        let heights = sorted.map(\.box.height).sorted()
        let typical = heights.isEmpty ? 0.012 : heights[heights.count / 2]
        var clusters: [[LayoutLine]] = []
        for line in sorted {
            if let index = clusters.lastIndex(where: { cluster in
                guard let last = cluster.last else { return false }
                let gap = last.box.minY - line.box.maxY
                // A blank line (a gap of a line or more) ends a block.
                return abs(last.box.minX - line.box.minX) <= 0.03 && gap >= -typical * 0.5 && gap <= typical * 0.9
            }) {
                clusters[index].append(line)
            } else {
                clusters.append([line])
            }
        }
        return clusters
    }

    /// The cluster without a return-address line, when it has the shape of
    /// an address: 2–7 lines, a postcode on the last or second-to-last.
    static func qualified(_ cluster: [LayoutLine], country: String?) -> [LayoutLine]? {
        var lines = cluster
        if let first = lines.first, lines.count >= 2 {
            let others = lines.dropFirst().map(\.box.height).sorted()
            let median = others[others.count / 2]
            if first.box.height < median * 0.8 || isReturnAddress(first.text) {
                lines.removeFirst()
            }
        }
        guard (2...7).contains(lines.count) else { return nil }
        let tail = lines.suffix(2)
        guard tail.contains(where: { hasPostcode($0.text, country: country) }) else { return nil }
        // Nothing after the postcode line but a country name.
        if let index = lines.lastIndex(where: { hasPostcode($0.text, country: country) }), index < lines.count - 1 {
            let after = lines[(index + 1)...]
            guard after.count == 1, after.first.map({ $0.text.count <= 25 && !$0.text.contains(where: \.isNumber) }) == true else { return nil }
        }
        return lines
    }

    /// Higher for a block that reads like a person's address; lower for one
    /// that reads like a sender's.
    static func score(_ lines: [LayoutLine], among all: [LayoutLine], rectified: Bool) -> Int {
        var value = rectified ? 1 : 0
        let first = lines.first?.text ?? ""
        if looksLikeRecipient(first) { value += 3 }
        if lines.contains(where: { isOfficeAddress($0.text) }) { value -= 3 }
        // Not the topmost block on the page: the sender's letterhead is.
        let top = all.map(\.box.maxY).max() ?? 1
        if let blockTop = lines.first?.box.maxY, blockTop < top - 0.02 { value += 1 }
        return value
    }

    private static let recipientOpeners: Set<String> = [
        "dhr", "de heer", "mw", "mevr", "mevrouw", "fam", "familie", "t.a.v", "tav", "aan", "c/o", "p/a",
        "herr", "herrn", "frau", "familie", "z. hd", "an",
        "m", "mme", "mlle", "monsieur", "madame",
        "mr", "mrs", "ms", "miss", "dr", "fao", "attn",
        "sr", "sra", "srta", "d", "dña", "don", "doña",
        "pan", "pani", "państwo",
        "sayın", "sn",
    ]

    static func looksLikeRecipient(_ line: String) -> Bool {
        let lower = line.lowercased().trimmingCharacters(in: .whitespaces)
        let firstWord = lower.split(whereSeparator: { $0 == " " }).first.map { $0.trimmingCharacters(in: CharacterSet(charactersIn: ".:,")) } ?? ""
        if recipientOpeners.contains(firstWord) { return true }
        for opener in recipientOpeners where opener.contains(" ") && lower.hasPrefix(opener) { return true }
        // Initials and a surname: "A. Yilmaz", "R.A. van der Meulen".
        return line.range(of: #"^\p{Lu}\.(?:[ ]?\p{Lu}\.)*[ ]+\p{L}"#, options: .regularExpression) != nil
    }

    private static func isReturnAddress(_ line: String) -> Bool {
        let lower = line.lowercased()
        return ["retouradres", "retour:", "absender", "rücksendung", "expéditeur", "return to", "if undelivered", "remite"]
            .contains { lower.contains($0) }
    }

    private static func isOfficeAddress(_ line: String) -> Bool {
        line.range(of: #"(?i)\b(?:postbus|postfach|po box|p\.o\. box|apartado|skrytka|cs \d|bp \d|antwoordnummer)\b"#, options: .regularExpression) != nil
    }

    // MARK: - Postcodes

    static func hasPostcode(_ line: String, country: String?) -> Bool {
        let patterns: [String: String] = [
            "NL": #"\b\d{4}[ ]{0,2}[A-Z]{2}\b"#,
            "DE": #"\b\d{5}\b"#, "FR": #"\b\d{5}\b"#, "ES": #"\b\d{5}\b"#, "TR": #"\b\d{5}\b"#,
            "PL": #"\b\d{2}-\d{3}\b"#,
            "GB": #"\b[A-Z]{1,2}\d[A-Z\d]?[ ]?\d[A-Z]{2}\b"#,
            "US": #"\b\d{5}(?:-\d{4})?\b"#,
        ]
        let chosen = country.flatMap { patterns[$0] }.map { [$0] } ?? Array(Set(patterns.values))
        return chosen.contains { line.range(of: $0, options: [.regularExpression, .caseInsensitive]) != nil }
    }
}

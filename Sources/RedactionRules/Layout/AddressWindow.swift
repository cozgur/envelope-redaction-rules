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

    /// Which window, or the shape alone on a page that is not rectified.
    public enum Kind: String, Sendable, Hashable {
        case a4Left = "a4-left"
        case a4Right = "a4-right"
        case ukDL = "uk-dl"
        case ukC5 = "uk-c5"
        case us10 = "us-10"
        case shape
    }

    /// What was found: the claim, which window, and the lines' boxes -- for
    /// a debug screen that shows where, never what.
    public struct Detection: Sendable {
        public var claim: KnownClaim
        public var kind: Kind
        public var boxes: [LayoutBox]
    }

    /// The window claim for page 1, or nil when no cluster qualifies.
    public static func find(in text: String, layout: LetterLayout, countryHint: String? = nil) -> KnownClaim? {
        detect(in: text, layout: layout, countryHint: countryHint)?.claim
    }

    /// The window, with its kind and boxes, or nil.
    public static func detect(in text: String, layout: LetterLayout, countryHint: String? = nil) -> Detection? {
        diagnose(in: text, layout: layout, countryHint: countryHint).detection
    }

    /// Why the window was found or not, with no text in it (owner, 6 Oct
    /// 2026: the DEBUG L2 check shows the reason on a real letter).
    public struct Diagnosis: Sendable {
        /// Why a candidate cluster was not the window.
        public enum Rejection: String, Sendable, Error {
            case accepted
            /// It qualified, and another candidate scored higher.
            case notBest = "not-best"
            /// Outside every window rectangle (rectified pages only).
            case outsideRectangles = "outside-rectangles"
            case tooFewLines = "too-few-lines"
            case tooManyLines = "too-many-lines"
            /// No postcode on its last or second-to-last line.
            case noPostcode = "no-postcode"
            /// More than a country name after the postcode line.
            case linesAfterPostcode = "lines-after-postcode"
            /// It reads like a sender, or nothing says it is a recipient.
            case lowScore = "low-score"
            /// Its lines are not where the text says they are.
            case notInText = "not-in-text"
        }

        public struct Candidate: Sendable {
            /// In the image's coordinates, for drawing.
            public var boxes: [LayoutBox]
            /// The rectangle it lies in, or `.shape` on a page read as a photo;
            /// nil when it lies in none.
            public var kind: Kind?
            public var postcodeLine: Bool
            public var personLine: Bool
            public var poBox: Bool
            public var organisation: Bool
            public var notTopmost: Bool
            /// The recipient score, when it got that far.
            public var score: Int?
            public var rejection: Rejection
            /// Each line's character-class signature, in reading order
            /// (``AddressWindow/signature(of:)``): no text.
            public var lineSignatures: [String] = []
            /// Whether each line has the postcode's shape.
            public var linePostcode: [Bool] = []
        }

        /// The page as the capture marked it.
        public var rectifiedAsGiven: Bool
        /// The page as read: rectified only with known page bounds.
        public var rectified: Bool
        /// Where the paper is in the image, when known.
        public var pageBounds: LayoutBox?
        public var candidates: [Candidate]
        public var detection: Detection?
    }

    public static func diagnose(in text: String, layout: LetterLayout, countryHint: String? = nil) -> Diagnosis {
        guard let page = layout.pages.first, !page.lines.isEmpty else {
            return Diagnosis(rectifiedAsGiven: layout.pages.first?.rectified ?? false, rectified: false,
                             pageBounds: layout.pages.first?.pageBounds, candidates: [], detection: nil)
        }
        let country = countryHint?.uppercased()
        // The window rectangles are measured on the paper: a rectified page
        // whose paper is not located in the image is read as a photo.
        let bounds = page.pageBounds
        let rectified = page.rectified && bounds != nil
        let frame = bounds ?? LayoutBox(x: 0, y: 0, width: 1, height: 1)
        let paperWidth = page.widthMM.map { $0 * frame.width }
        let paperHeight = page.heightMM.map { $0 * frame.height }
        let ratio = (paperHeight ?? 297) / (paperWidth ?? 210)
        let usLetter = abs(ratio - 279.4 / 215.9) < abs(ratio - 297.0 / 210.0) || (country == "US" && page.heightMM == nil)
        let widthMM = usLetter ? 215.9 : 210.0
        let heightMM = usLetter ? 279.4 : 297.0

        // Each line in the paper's coordinates; the original kept for drawing.
        var original: [Int: LayoutBox] = [:]
        let lines: [LayoutLine] = page.lines.map { line in
            var moved = line
            moved.box = LayoutBox(
                x: (line.box.x - frame.x) / frame.width, y: (line.box.y - frame.y) / frame.height,
                width: line.box.width / frame.width, height: line.box.height / frame.height
            )
            original[line.characterOffset] = line.box
            return moved
        }
        func imageBoxes(_ cluster: [LayoutLine]) -> [LayoutBox] {
            cluster.map { original[$0.characterOffset] ?? $0.box }
        }

        let rectangles: [(Rectangle, Kind)] = usLetter ? [(us10, .us10)]
            : country == "GB" ? [(ukDL, .ukDL), (ukC5, .ukC5)] : [(a4Left, .a4Left), (a4Right, .a4Right)]
        func inside(_ line: LayoutLine, _ rectangle: Rectangle) -> Bool {
            let x = line.box.midX * widthMM
            let fromTop = (1 - line.box.midY) * heightMM
            return x >= rectangle.left && x <= rectangle.right && fromTop >= rectangle.top && fromTop <= rectangle.bottom
        }

        var groups: [(lines: [LayoutLine], kind: Kind?)] = []
        if rectified {
            for (rectangle, kind) in rectangles {
                groups.append((lines.filter { inside($0, rectangle) }, kind))
            }
            // Everything outside every rectangle, so the screen can show it.
            groups.append((lines.filter { line in !rectangles.contains { inside(line, $0.0) } }, nil))
        } else {
            groups = [(lines.filter { $0.box.midY > 0.5 }, .shape)]
        }

        let top = lines.map(\.box.maxY).max() ?? 1
        var candidates: [Diagnosis.Candidate] = []
        var best: (score: Int, lines: [LayoutLine], kind: Kind, index: Int)?
        for (group, kind) in groups {
            for cluster in clusters(of: group) {
                var candidate = Diagnosis.Candidate(
                    boxes: imageBoxes(cluster), kind: kind,
                    postcodeLine: cluster.suffix(2).contains { hasPostcode($0.text, country: country) },
                    personLine: cluster.prefix(3).contains { looksLikeRecipient($0.text) },
                    poBox: cluster.contains { isOfficeAddress($0.text) },
                    organisation: cluster.first.map { looksLikeOrganisation($0.text) } ?? false,
                    notTopmost: (cluster.first?.box.maxY ?? top) < top - 0.02,
                    score: nil, rejection: .accepted
                )
                guard let kind else {
                    candidate.rejection = .outsideRectangles
                    candidates.append(candidate)
                    continue
                }
                switch qualification(cluster, country: country) {
                case .failure(let reason):
                    candidate.rejection = reason
                case .success(let block):
                    let value = score(block, among: lines, rectified: rectified)
                    candidate.score = value
                    candidate.boxes = imageBoxes(block)
                    if value <= 0 {
                        candidate.rejection = .lowScore
                    } else if value > (best?.score ?? Int.min) {
                        if let previous = best { candidates[previous.index].rejection = .notBest }
                        best = (value, block, kind, candidates.count)
                    } else {
                        candidate.rejection = .notBest
                    }
                }
                candidates.append(candidate)
            }
        }
        func diagnosis(_ detection: Detection?) -> Diagnosis {
            Diagnosis(rectifiedAsGiven: page.rectified, rectified: rectified, pageBounds: bounds,
                      candidates: candidates, detection: detection)
        }
        // The block must also read like a recipient, rectangle or not: a
        // sender's letterhead has the same shape, and a right-hand letterhead
        // sits in the right window's rectangle.
        guard let chosen = best else { return diagnosis(nil) }

        // A leading line that is not a person and that the letter prints
        // again outside the window is the sender's own name (nl-pension of
        // the layout variants: "Sociale Verzekeringsbank" on the row above
        // the window, and again in the body). A recipient company is printed
        // once, on the envelope.
        var block = chosen.lines
        while block.count > 2, let first = block.first, !looksLikeRecipient(first.text),
              occurrences(of: first.text, in: text) > 1 {
            block.removeFirst()
        }
        let ranges: [Range<String.Index>] = block.compactMap { line in
            guard line.characterOffset >= 0, line.characterOffset + line.text.count <= text.count else { return nil }
            let start = text.index(text.startIndex, offsetBy: line.characterOffset)
            let end = text.index(start, offsetBy: line.text.count)
            guard text[start..<end] == line.text else { return nil }
            return start..<end
        }
        guard ranges.count == block.count else {
            candidates[chosen.index].rejection = .notInText
            return diagnosis(nil)
        }
        return diagnosis(Detection(
            claim: KnownClaim(kind: .address, ranges: ranges, source: .window),
            kind: chosen.kind, boxes: imageBoxes(block)
        ))
    }

    private static func occurrences(of line: String, in text: String) -> Int {
        let needle = line.trimmingCharacters(in: .whitespaces)
        guard !needle.isEmpty else { return 0 }
        return text.components(separatedBy: needle).count - 1
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
        if case .success(let lines) = qualification(cluster, country: country) { return lines }
        return nil
    }

    static func qualification(_ cluster: [LayoutLine], country: String?) -> Result<[LayoutLine], Diagnosis.Rejection> {
        var lines = cluster
        // A return-address line anywhere: it and everything above it are the
        // sender's (a letterhead stacked right above the window).
        if let index = lines.lastIndex(where: { isReturnAddress($0.text) }) {
            lines.removeFirst(index + 1)
        }
        if let first = lines.first, lines.count >= 2 {
            let others = lines.dropFirst().map(\.box.height).sorted()
            let median = others[others.count / 2]
            if first.box.height < median * 0.8 || isReturnAddress(first.text) {
                lines.removeFirst()
            }
        }
        if lines.count < 2 { return .failure(.tooFewLines) }
        if lines.count > 7 { return .failure(.tooManyLines) }
        let tail = lines.suffix(2)
        guard tail.contains(where: { hasPostcode($0.text, country: country) }) else { return .failure(.noPostcode) }
        // Nothing after the postcode line but a country name.
        if let index = lines.lastIndex(where: { hasPostcode($0.text, country: country) }), index < lines.count - 1 {
            let after = lines[(index + 1)...]
            guard after.count == 1, after.first.map({ $0.text.count <= 25 && !$0.text.contains(where: \.isNumber) }) == true
            else { return .failure(.linesAfterPostcode) }
        }
        return .success(lines)
    }

    /// Higher for a block that reads like a person's address; lower for one
    /// that reads like a sender's.
    static func score(_ lines: [LayoutLine], among all: [LayoutLine], rectified: Bool) -> Int {
        var value = 0
        // A person among the first lines: the name, or "FAO Mr …", "z. Hd.
        // Frau …", "T.a.v. mevrouw …" under a company's name.
        let opener = lines.prefix(3).contains { looksLikeRecipient($0.text) }
        if opener { value += 3 }
        if lines.contains(where: { isOfficeAddress($0.text) }) { value -= 3 }
        if !opener, let first = lines.first?.text, looksLikeOrganisation(first) { value -= 2 }
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
        if line.range(of: #"^\p{Lu}\.(?:[ ]?\p{Lu}\.)*[ ]+\p{L}"#, options: .regularExpression) != nil { return true }
        // Initials without dots, in any script, then a capitalised surname:
        // "Ö Yılmaz", "J Jansen", "AB de Vries" (owner, 6 Oct 2026: an RDW
        // letter printed the reader's dotless initial).
        return line.range(of: #"^\p{Lu}{1,3}[ ]+(?:(?:van|de|der|den|von|la|le|du|da|di|del)[ ]+)*\p{Lu}\p{Ll}[\p{L}'’-]+[ ]*$"#, options: .regularExpression) != nil
    }

    /// A first line that names an organisation: a sender's letterhead opens
    /// so.
    static func looksLikeOrganisation(_ line: String) -> Bool {
        line.range(of: #"(?i)\b(?:b\.v\.|n\.v\.|v\.o\.f\.|gmbh|ag|ltd|limited|plc|inc|llc|sarl|sas|s\.a\.|s\.l\.|sp\. z o\.o\.|a\.ş\.|gemeente|belastingdienst|rechtbank|court|council|tribunal|gericht|finanzamt|stadt|ayuntamiento|agencia|urząd|belediye|university|universiteit|universität|bank|verzekering|insurance|versicherung|krankenkasse|caisse|ministerie|ministry|service|department|dienst|office)\b"#, options: .regularExpression) != nil
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

    /// A line as character classes (owner, 6 Oct 2026): D a digit, A an
    /// upper-case letter, a a lower-case one -- diacritics included -- _ a
    /// space, punctuation as itself. What a DEBUG screen may show of a line.
    public static func signature(of line: String) -> String {
        ""
    }

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

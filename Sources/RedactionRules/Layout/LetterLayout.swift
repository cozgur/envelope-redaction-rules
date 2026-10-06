import Foundation

/// Where a letter's lines sit on its pages, as OCR reports them (redaction v2,
/// L2).
///
/// The app builds this from Vision's observations; the recall harness reads
/// it from an independent set's `layouts`. Foundation only: a box is four
/// numbers, so the geometry can live here, beside the rules, and be measured
/// with them.
public struct LetterLayout: Sendable, Hashable, Codable {
    public var pages: [LayoutPage]

    public init(pages: [LayoutPage]) {
        self.pages = pages
    }
}

/// One page.
public struct LayoutPage: Sendable, Hashable, Codable {
    /// In the order OCR read them.
    public var lines: [LayoutLine]
    /// The page's size, when known (A4 is 210 × 297). Only the ratio is used,
    /// to tell A4 from US Letter.
    public var widthMM: Double?
    public var heightMM: Double?
    /// Whether the page was straightened -- captured by the document camera
    /// or perspective-corrected. Only then do the fixed window rectangles
    /// mean anything; a photo from the library is not rectified.
    public var rectified: Bool
    /// Where the paper is inside the image, normalised like a line's box
    /// (owner, 6 Oct 2026: a document-camera crop is not always tight -- a
    /// hand, the table, a fold). The window rectangles are measured on the
    /// paper, so a rectified page with no known bounds is treated as a photo.
    /// The page's size fields are the image's.
    public var pageBounds: LayoutBox?

    public init(lines: [LayoutLine], widthMM: Double? = nil, heightMM: Double? = nil, rectified: Bool, pageBounds: LayoutBox? = nil) {
        self.lines = lines
        self.widthMM = widthMM
        self.heightMM = heightMM
        self.rectified = rectified
        self.pageBounds = pageBounds
    }
}

/// One OCR line: its text, its box, and where it starts in the letter's text.
public struct LayoutLine: Sendable, Hashable, Codable {
    public var text: String
    public var box: LayoutBox
    /// In characters, into the text handed to the engine.
    public var characterOffset: Int

    public init(text: String, box: LayoutBox, characterOffset: Int) {
        self.text = text
        self.box = box
        self.characterOffset = characterOffset
    }
}

/// Normalised to the page (0–1), origin at the lower left -- Vision's
/// convention.
public struct LayoutBox: Sendable, Hashable, Codable {
    public var x: Double
    public var y: Double
    public var width: Double
    public var height: Double

    public init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }

    public var minX: Double { x }
    public var maxX: Double { x + width }
    /// The bottom edge.
    public var minY: Double { y }
    /// The top edge.
    public var maxY: Double { y + height }
    public var midX: Double { x + width / 2 }
    public var midY: Double { y + height / 2 }
}

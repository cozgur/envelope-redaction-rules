import Foundation
import RedactionRules

/// A letter laid out on page 1 the way real ones are, for tests and audits
/// of the address window (L2).
///
/// Positions are the standards' -- NEN/DIN 5008 windows on A4, the UK DL and
/// C5 windows, the US #10 window on Letter -- with a letterhead at the top
/// and the body below. Boxes are normalised, origin at the lower left, and
/// the lines come out in the order OCR reads a page: row by row, left to
/// right, so two columns in the same rows interleave.
public enum SyntheticLayout {

    public enum Kind: String, CaseIterable, Sendable {
        case a4LeftWindow = "a4-left-window"
        case a4RightWindow = "a4-right-window"
        /// The recipient block in the same rows as the sender's column.
        case a4SameRow = "a4-same-row"
        /// A left window with a small return-address line above the block.
        case a4ReturnLine = "a4-return-line"
        case ukDL = "uk-dl"
        case ukC5 = "uk-c5"
        case us10 = "us-10"
        /// A phone photo of the left-window page: rotated, shrunk, shifted,
        /// and not straightened.
        case photoSkewed = "photo-skewed"
    }

    public struct Letter: Sendable {
        public var sender: [String]
        public var recipient: [String]
        public var returnLine: String?
        public var body: [String]

        public init(sender: [String], recipient: [String], returnLine: String? = nil, body: [String]) {
            self.sender = sender
            self.recipient = recipient
            self.returnLine = returnLine
            self.body = body
        }
    }

    /// One positioned line, in millimetres from the left and from the top.
    private struct Placed {
        var text: String
        var left: Double
        var top: Double
        var height: Double
    }

    public static func make(_ letter: Letter, kind: Kind) -> (text: String, layout: LetterLayout) {
        let us = kind == .us10
        let width = us ? 215.9 : 210.0
        let height = us ? 279.4 : 297.0
        let leading = 4.4
        let size = 3.2
        var placed: [Placed] = []

        let senderLeft = 20.0
        var senderTop = 12.0
        var recipientLeft = 22.0
        var recipientTop = 50.0
        switch kind {
        case .a4LeftWindow, .a4ReturnLine, .ukDL, .photoSkewed: break
        case .a4RightWindow: recipientLeft = 120
        case .a4SameRow: recipientLeft = 120; senderTop = recipientTop
        case .ukC5: recipientLeft = 112
        case .us10: recipientLeft = 25; recipientTop = 55
        }
        for (index, line) in letter.sender.enumerated() {
            placed.append(Placed(text: line, left: senderLeft, top: senderTop + Double(index) * leading, height: size))
        }
        if kind == .a4ReturnLine, let returnLine = letter.returnLine {
            placed.append(Placed(text: returnLine, left: recipientLeft, top: recipientTop - 5, height: 2.0))
        }
        for (index, line) in letter.recipient.enumerated() {
            placed.append(Placed(text: line, left: recipientLeft, top: recipientTop + Double(index) * leading, height: size))
        }
        for (index, line) in letter.body.enumerated() {
            placed.append(Placed(text: line, left: 20, top: 110 + Double(index) * leading, height: size))
        }

        // OCR order: by row, then left to right.
        placed.sort { abs($0.top - $1.top) < 1 ? $0.left < $1.left : $0.top < $1.top }

        var lines: [LayoutLine] = []
        var offset = 0
        for one in placed {
            var box = LayoutBox(
                x: one.left / width,
                y: 1 - (one.top + one.height) / height,
                width: min(Double(one.text.count) * 1.8, width - one.left - 5) / width,
                height: one.height / height
            )
            if kind == .photoSkewed { box = skewed(box) }
            lines.append(LayoutLine(text: one.text, box: box, characterOffset: offset))
            offset += one.text.count + 1
        }
        let text = placed.map(\.text).joined(separator: "\n")
        // The synthetic image is the page itself: tight bounds when rectified.
        let page = LayoutPage(lines: lines, widthMM: width, heightMM: height, rectified: kind != .photoSkewed,
                              pageBounds: kind != .photoSkewed ? LayoutBox(x: 0, y: 0, width: 1, height: 1) : nil)
        return (text, LetterLayout(pages: [page]))
    }

    /// The box as a phone photo sees it: rotated 2.5° about the page's
    /// centre, shrunk to 85% and shifted; its axis-aligned bounds.
    private static func skewed(_ box: LayoutBox) -> LayoutBox {
        let angle = 2.5 * Double.pi / 180
        let corners = [(box.minX, box.minY), (box.maxX, box.minY), (box.minX, box.maxY), (box.maxX, box.maxY)].map { x, y -> (Double, Double) in
            let dx = x - 0.5, dy = y - 0.5
            let rx = dx * cos(angle) - dy * sin(angle)
            let ry = dx * sin(angle) + dy * cos(angle)
            return (0.5 + rx * 0.85 + 0.04, 0.5 + ry * 0.85 - 0.03)
        }
        let xs = corners.map(\.0), ys = corners.map(\.1)
        return LayoutBox(x: xs.min()!, y: ys.min()!, width: xs.max()! - xs.min()!, height: ys.max()! - ys.min()!)
    }
}

import Foundation

/// One detector of a single kind of personal data.
///
/// A rule reports where it found something and nothing else. Deciding what
/// survives an overlap, what a placeholder is called and what must never be
/// touched all belong to the engine, so a rule stays small enough to test on
/// its own.
public protocol RedactionRule: Sendable {
    var kind: PIIKind { get }

    /// Every range this rule claims, in any order. Overlaps with other rules
    /// are expected and resolved by the engine.
    func matches(in text: String) -> [Range<String.Index>]
}

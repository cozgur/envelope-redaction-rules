import Foundation
import RedactionRules
import Testing

/// The claims the README makes about this package, checked here rather than in
/// the app that consumes it.
///
/// The app used to scan these sources, back when the package lived inside it.
/// It is a dependency now, and a stranger who clones this repository runs
/// `swift test` and nothing else -- so the guarantee has to hold from inside.
@Suite("Package hygiene")
struct PackageHygieneTests {

    /// This file is at `Tests/RedactionRulesTests/`, so the package root is
    /// two directories above it. `#filePath` is the compiler's own record of
    /// the checkout, which a resource bundle could not tell us.
    private static var sourceRoot: URL {
        URL(filePath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appending(path: "Sources")
    }

    private static func swiftFiles() throws -> [URL] {
        let enumerator = FileManager.default.enumerator(at: sourceRoot, includingPropertiesForKeys: nil)
        var files: [URL] = []
        while let url = enumerator?.nextObject() as? URL {
            guard url.pathExtension == "swift" else { continue }
            files.append(url)
        }
        return files.sorted { $0.path < $1.path }
    }

    @Test("Nothing but Foundation is imported")
    func foundationOnly() throws {
        var found: Set<String> = []
        for file in try Self.swiftFiles() {
            for line in try String(contentsOf: file, encoding: .utf8).components(separatedBy: .newlines) {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                guard trimmed.hasPrefix("import ") else { continue }
                found.insert(String(trimmed.dropFirst("import ".count)))
            }
        }
        #expect(found == ["Foundation"], "Imports: \(found.sorted().joined(separator: ", "))")
    }

    @Test("Nothing here can make a network request")
    func noNetworking() throws {
        // The whole point of the package is that it runs before anything is
        // sent. A symbol that could send is a contradiction of the README,
        // and the README is the reason anyone trusts the app.
        let forbidden = [
            #"\bURLSession\b"#, #"\bURLRequest\b"#, #"\bNWConnection\b"#,
            #"\bNSURLConnection\b"#, #"\bdataTask\b"#, #"\buploadTask\b"#,
            #"^import Network$"#, #"^import CFNetwork$"#,
        ]

        var offences: [String] = []
        for pattern in forbidden {
            let regex = try NSRegularExpression(pattern: pattern, options: [.anchorsMatchLines])
            for file in try Self.swiftFiles() {
                let source = try String(contentsOf: file, encoding: .utf8)
                let range = NSRange(source.startIndex..., in: source)
                guard regex.firstMatch(in: source, range: range) != nil else { continue }
                offences.append("\(file.lastPathComponent): \(pattern)")
            }
        }
        let report = offences.joined(separator: "\n")
        #expect(offences.isEmpty, "\(report)")
    }

    @Test("Every kind has a distinct placeholder token")
    func placeholderTokensAreDistinct() {
        // A duplicate token would make two kinds indistinguishable in the
        // redacted text, which is the only form the proxy ever sees.
        let tokens = PIIKind.allCases.map(\.placeholderToken)
        #expect(Set(tokens).count == tokens.count)
    }
}

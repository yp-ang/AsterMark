import Foundation

/// File names for exports, e.g. `{name}_{recipe}` or `Smith-{seq:3}-{w}x{h}`.
///
/// Tokens: `{name}` source file name without extension · `{seq}` / `{seq:N}` position in the export,
/// zero-padded to N digits · `{recipe}` recipe name · `{date}` / `{date:FORMAT}` capture date
/// (falls back to today) · `{w}` / `{h}` output pixels.
public struct NamingTemplate: Sendable, Hashable {
    public let template: String

    public init(_ template: String) {
        self.template = template
    }

    public struct Values: Sendable {
        public var name: String
        public var sequence: Int
        public var recipe: String
        public var date: Date
        public var width: Int
        public var height: Int

        public init(name: String, sequence: Int, recipe: String, date: Date, width: Int, height: Int) {
            self.name = name
            self.sequence = sequence
            self.recipe = recipe
            self.date = date
            self.width = width
            self.height = height
        }
    }

    /// Renders the base file name (no extension). Path separators and other unsafe characters become "-".
    public func render(_ values: Values) -> String {
        var result = ""
        var index = template.startIndex
        while index < template.endIndex {
            if template[index] == "{", let close = template[index...].firstIndex(of: "}") {
                let token = String(template[template.index(after: index)..<close])
                result += expand(token, values) ?? "{\(token)}"
                index = template.index(after: close)
            } else {
                result.append(template[index])
                index = template.index(after: index)
            }
        }
        let cleaned = Self.sanitized(result)
        return cleaned.isEmpty ? Self.sanitized(values.name) : cleaned
    }

    /// Problems to show under the template field; empty when the template is fine.
    public var problems: [String] {
        var problems: [String] = []
        if template.trimmingCharacters(in: .whitespaces).isEmpty { problems.append("Enter a file name pattern.") }
        if template.contains(where: { "/:\\".contains($0) }) { problems.append("File names can't contain / : or \\.") }
        let tokens = template.split(separator: "{").dropFirst().compactMap { $0.split(separator: "}").first.map(String.init) }
        for token in tokens where expand(token, Values(name: "x", sequence: 1, recipe: "r", date: Date(), width: 1, height: 1)) == nil {
            problems.append("Unknown token {\(token)}.")
        }
        if !template.contains("{name}") && !template.contains("{seq") {
            problems.append("Include {name} or {seq} so every photo gets its own file name.")
        }
        return problems
    }

    private func expand(_ token: String, _ v: Values) -> String? {
        let parts = token.split(separator: ":", maxSplits: 1).map(String.init)
        switch parts.first {
        case "name": return v.name
        case "recipe": return v.recipe
        case "w": return String(v.width)
        case "h": return String(v.height)
        case "seq":
            let digits = parts.count > 1 ? Int(parts[1]) ?? 1 : 1
            let number = String(v.sequence)
            return String(repeating: "0", count: max(digits - number.count, 0)) + number
        case "date":
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.dateFormat = parts.count > 1 ? parts[1] : "yyyyMMdd"
            return formatter.string(from: v.date)
        default:
            return nil
        }
    }

    public static func sanitized(_ name: String) -> String {
        let unsafe = CharacterSet(charactersIn: "/:\\\0").union(.controlCharacters)
        let parts = name.components(separatedBy: unsafe)
        return parts.joined(separator: "-")
            .trimmingCharacters(in: .whitespaces)
            .trimmingCharacters(in: CharacterSet(charactersIn: "."))
    }
}

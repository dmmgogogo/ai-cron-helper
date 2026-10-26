import Foundation

enum TOMLValue: Equatable {
    case string(String)
    case int(Int64)
    case bool(Bool)
    case strings([String])
    case other

    var string: String? {
        if case .string(let s) = self { return s }
        return nil
    }

    var strings: [String]? {
        if case .strings(let a) = self { return a }
        return nil
    }
}

/// 只够读 Codex automation.toml 的极简 TOML 解析：顶层 `key = value`，
/// 支持基本字符串（含转义）、字面量字符串、整数、布尔、单行字符串数组；
/// 遇到 `[table]` 头就停止，多行字符串会被完整跳过。
enum TOMLLite {
    /// skipKeys 里的键不解析也不保留（用来跳过 prompt 正文）
    static func parseTopLevel(_ text: String, skipKeys: Set<String> = []) -> [String: TOMLValue] {
        var result: [String: TOMLValue] = [:]
        let lines = text.components(separatedBy: .newlines)
        var i = 0
        while i < lines.count {
            let trimmed = lines[i].trimmingCharacters(in: .whitespaces)
            i += 1
            if trimmed.isEmpty || trimmed.hasPrefix("#") { continue }
            if trimmed.hasPrefix("[") { break }
            guard let eq = trimmed.firstIndex(of: "=") else { continue }
            var key = trimmed[..<eq].trimmingCharacters(in: .whitespaces)
            if key.count >= 2, key.hasPrefix("\""), key.hasSuffix("\"") {
                key = String(key.dropFirst().dropLast())
            }
            let value = trimmed[trimmed.index(after: eq)...].trimmingCharacters(in: .whitespaces)

            if let delim = ["\"\"\"", "'''"].first(where: { value.hasPrefix($0) }) {
                // 多行字符串：一直读到收尾分隔符
                var body = String(value.dropFirst(3))
                while !body.contains(delim), i < lines.count {
                    body += "\n" + lines[i]
                    i += 1
                }
                if !skipKeys.contains(key), let end = body.range(of: delim) {
                    result[key] = .string(String(body[..<end.lowerBound]))
                }
                continue
            }
            if skipKeys.contains(key) { continue }
            result[key] = parseValue(value)
        }
        return result
    }

    static func parseValue(_ v: String) -> TOMLValue {
        if v.hasPrefix("\"") {
            return scanBasicString(v, from: v.startIndex).map { .string($0.value) } ?? .other
        }
        if v.hasPrefix("'") {
            let body = v.dropFirst()
            guard let end = body.firstIndex(of: "'") else { return .other }
            return .string(String(body[..<end]))
        }
        if v.hasPrefix("[") {
            return parseStringArray(v).map { .strings($0) } ?? .other
        }
        let bare = v.split(separator: "#", maxSplits: 1).first
            .map { $0.trimmingCharacters(in: .whitespaces) } ?? ""
        if bare == "true" { return .bool(true) }
        if bare == "false" { return .bool(false) }
        if let n = Int64(bare.replacingOccurrences(of: "_", with: "")) { return .int(n) }
        return .other
    }

    /// s[start] 必须是 `"`；返回解码后的内容和收尾引号之后的位置
    static func scanBasicString(_ s: String, from start: String.Index) -> (value: String, end: String.Index)? {
        var out = ""
        var i = s.index(after: start)
        while i < s.endIndex {
            let ch = s[i]
            if ch == "\"" { return (out, s.index(after: i)) }
            guard ch == "\\" else {
                out.append(ch)
                i = s.index(after: i)
                continue
            }
            let n = s.index(after: i)
            guard n < s.endIndex else { return nil }
            switch s[n] {
            case "n": out.append("\n")
            case "t": out.append("\t")
            case "r": out.append("\r")
            case "b": out.append("\u{8}")
            case "f": out.append("\u{C}")
            case "\"": out.append("\"")
            case "\\": out.append("\\")
            case "u", "U":
                let len = s[n] == "u" ? 4 : 8
                let hexStart = s.index(after: n)
                guard let hexEnd = s.index(hexStart, offsetBy: len, limitedBy: s.endIndex),
                      let code = UInt32(s[hexStart..<hexEnd], radix: 16),
                      let scalar = Unicode.Scalar(code) else { return nil }
                out.unicodeScalars.append(scalar)
                i = hexEnd
                continue
            default:
                out.append(s[n])
            }
            i = s.index(after: n)
        }
        return nil
    }

    /// 单行字符串数组；遇到非字符串元素或跨行数组返回 nil
    static func parseStringArray(_ v: String) -> [String]? {
        var out: [String] = []
        var i = v.index(after: v.startIndex)
        while i < v.endIndex {
            let ch = v[i]
            switch ch {
            case "]":
                return out
            case "\"":
                guard let r = scanBasicString(v, from: i) else { return nil }
                out.append(r.value)
                i = r.end
            case "'":
                let after = v.index(after: i)
                guard let end = v[after...].firstIndex(of: "'") else { return nil }
                out.append(String(v[after..<end]))
                i = v.index(after: end)
            case ",", " ", "\t":
                i = v.index(after: i)
            default:
                return nil
            }
        }
        return nil
    }
}

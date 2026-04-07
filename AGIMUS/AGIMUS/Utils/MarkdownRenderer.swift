// 轻量 Markdown → NSAttributedString 渲染器（仅依赖 Foundation/UIKit）
import UIKit

final class MarkdownRenderer {
    static let shared = MarkdownRenderer()
    private init() {}

    // Fonts
    let bodyFont   = UIFont.systemFont(ofSize: 15)
    let boldFont   = UIFont.boldSystemFont(ofSize: 15)
    let italicFont = UIFont.italicSystemFont(ofSize: 15)
    let h1Font     = UIFont.boldSystemFont(ofSize: 22)
    let h2Font     = UIFont.boldSystemFont(ofSize: 19)
    let h3Font     = UIFont.boldSystemFont(ofSize: 16)
    let codeFont   = UIFont.monospacedBody(size: 13)

    // Colors
    let textColor  = UIColor.agTextBot
    let codeTextColor = UIColor.agCodeText
    let codeBGColor   = UIColor.agCodeBG

    // ----------------------------------------------------------------
    // MARK: - Public
    // ----------------------------------------------------------------

    func render(_ raw: String, textColor: UIColor? = nil) -> NSAttributedString {
        let color = textColor ?? self.textColor
        let result = NSMutableAttributedString()
        let lines = raw.components(separatedBy: "\n")

        var i = 0
        while i < lines.count {
            let line = lines[i]

            // --- Fenced code block ---
            if line.hasPrefix("```") {
                var codeLines: [String] = []
                i += 1
                while i < lines.count && !lines[i].hasPrefix("```") {
                    codeLines.append(lines[i])
                    i += 1
                }
                // skip closing ```
                if i < lines.count { i += 1 }
                result.append(renderCodeBlock(codeLines.joined(separator: "\n")))
                result.append(newline())
                continue
            }

            // --- Heading ---
            if line.hasPrefix("### ") {
                result.append(renderHeading(String(line.dropFirst(4)), font: h3Font, color: color))
            } else if line.hasPrefix("## ") {
                result.append(renderHeading(String(line.dropFirst(3)), font: h2Font, color: color))
            } else if line.hasPrefix("# ") {
                result.append(renderHeading(String(line.dropFirst(2)), font: h1Font, color: color))
            } else {
                // Normal line with inline formatting
                result.append(renderInline(line, baseColor: color))
            }
            result.append(newline())
            i += 1
        }

        // Trim trailing newlines
        let str = result.mutableString
        while str.hasSuffix("\n\n") {
            str.deleteCharacters(in: NSRange(location: str.length - 1, length: 1))
        }
        return result
    }

    // ----------------------------------------------------------------
    // MARK: - Private helpers
    // ----------------------------------------------------------------

    private func newline() -> NSAttributedString {
        NSAttributedString(string: "\n", attributes: [.font: bodyFont])
    }

    private func renderHeading(_ text: String, font: UIFont, color: UIColor) -> NSAttributedString {
        NSAttributedString(string: text, attributes: [.font: font, .foregroundColor: color])
    }

    private func renderCodeBlock(_ code: String) -> NSAttributedString {
        let text = code.isEmpty ? " " : code
        let para = NSMutableParagraphStyle()
        para.firstLineHeadIndent = 8
        para.headIndent = 8
        para.tailIndent = -8
        return NSAttributedString(string: text, attributes: [
            .font: codeFont,
            .foregroundColor: codeTextColor,
            .backgroundColor: codeBGColor,
            .paragraphStyle: para
        ])
    }

    /// Handles **bold**, *italic*, `code`, and plain text inline.
    private func renderInline(_ line: String, baseColor: UIColor) -> NSAttributedString {
        let result = NSMutableAttributedString()
        var remaining = line[line.startIndex...]

        while !remaining.isEmpty {
            // Inline code: `...`
            if remaining.hasPrefix("`"),
               let end = remaining.dropFirst().firstIndex(of: "`") {
                let inner = remaining[remaining.index(after: remaining.startIndex)..<end]
                result.append(NSAttributedString(string: String(inner), attributes: [
                    .font: codeFont,
                    .foregroundColor: codeTextColor,
                    .backgroundColor: codeBGColor
                ]))
                remaining = remaining[remaining.index(after: end)...]
                continue
            }

            // Bold: **...**
            if remaining.hasPrefix("**"),
               let range = remaining.dropFirst(2).range(of: "**") {
                let inner = remaining[remaining.index(remaining.startIndex, offsetBy: 2)..<range.lowerBound]
                result.append(NSAttributedString(string: String(inner), attributes: [
                    .font: boldFont, .foregroundColor: baseColor
                ]))
                remaining = remaining[range.upperBound...]
                continue
            }

            // Italic: *...*
            if remaining.hasPrefix("*"),
               let range = remaining.dropFirst(1).range(of: "*") {
                let inner = remaining[remaining.index(after: remaining.startIndex)..<range.lowerBound]
                result.append(NSAttributedString(string: String(inner), attributes: [
                    .font: italicFont, .foregroundColor: baseColor
                ]))
                remaining = remaining[range.upperBound...]
                continue
            }

            // Consume one character as plain text
            let ch = String(remaining.removeFirst())
            result.append(NSAttributedString(string: ch, attributes: [
                .font: bodyFont, .foregroundColor: baseColor
            ]))
        }
        return result
    }
}

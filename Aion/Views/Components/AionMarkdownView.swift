import SwiftUI
import UIKit

/// Lightweight native Markdown & fenced code block renderer with one-tap copy.
struct AionMarkdownView: View {
    let text: String

    private enum Block: Identifiable {
        case prose(id: Int, content: String)
        case code(id: Int, language: String, content: String)

        var id: Int {
            switch self {
            case .prose(let id, _), .code(let id, _, _): return id
            }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(parseBlocks(text)) { block in
                switch block {
                case .prose(_, let prose):
                    if let attributed = try? AttributedString(
                        markdown: prose,
                        options: AttributedString.MarkdownParsingOptions(
                            interpretedSyntax: .inlineOnlyPreservingWhitespace
                        )
                    ) {
                        Text(attributed)
                            .font(.system(size: 16.5, weight: .regular))
                            .foregroundStyle(AionTheme.inkPrimary)
                            .lineSpacing(4)
                            .textSelection(.enabled)
                    } else {
                        Text(prose)
                            .font(.system(size: 16.5))
                            .foregroundStyle(AionTheme.inkPrimary)
                            .lineSpacing(4)
                            .textSelection(.enabled)
                    }

                case .code(_, let language, let code):
                    CodeSnippetCard(language: language, code: code)
                }
            }
        }
    }

    private func parseBlocks(_ raw: String) -> [Block] {
        var result: [Block] = []
        let lines = raw.components(separatedBy: "\n")
        var currentProse: [String] = []
        var currentCode: [String] = []
        var inCode = false
        var codeLang = ""
        var nextID = 0

        func flushProse() {
            let joined = currentProse.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
            if !joined.isEmpty {
                result.append(.prose(id: nextID, content: joined))
                nextID += 1
            }
            currentProse.removeAll()
        }

        func flushCode() {
            let joined = currentCode.joined(separator: "\n")
            result.append(.code(id: nextID, language: codeLang.isEmpty ? "code" : codeLang, content: joined))
            nextID += 1
            currentCode.removeAll()
            codeLang = ""
        }

        for line in lines {
            if line.trimmingCharacters(in: .whitespaces).hasPrefix("```") {
                if inCode {
                    flushCode()
                    inCode = false
                } else {
                    flushProse()
                    codeLang = String(line.trimmingCharacters(in: .whitespaces).dropFirst(3))
                    inCode = true
                }
            } else if inCode {
                currentCode.append(line)
            } else {
                currentProse.append(line)
            }
        }

        if inCode {
            flushCode()
        } else {
            flushProse()
        }
        return result
    }
}

private struct CodeSnippetCard: View {
    let language: String
    let code: String
    @State private var copied = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(language.uppercased())
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundStyle(AionTheme.inkSecondary)

                Spacer()

                Button {
                    UIPasteboard.general.string = code
                    AionHaptics.success()
                    withAnimation { copied = true }
                    Task {
                        try? await Task.sleep(for: .seconds(1.8))
                        withAnimation { copied = false }
                    }
                } label: {
                    Label(copied ? "Copied" : "Copy", systemImage: copied ? "checkmark" : "doc.on.doc")
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundStyle(copied ? AionTheme.forest : AionTheme.inkSecondary)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .background(AionTheme.surfaceSecondary.opacity(0.65))

            ScrollView(.horizontal, showsIndicators: false) {
                Text(code)
                    .font(.system(size: 13.5, design: .monospaced))
                    .foregroundStyle(AionTheme.inkPrimary)
                    .padding(14)
                    .textSelection(.enabled)
            }
        }
        .background(AionTheme.codeBackground, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(AionTheme.border, lineWidth: 0.85)
        )
    }
}

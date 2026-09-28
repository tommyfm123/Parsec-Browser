import SwiftUI

enum MarkdownBlock {
    case heading(String)
    case bullet(String)
    case numbered(marker: String, text: String)
    case table([[String]])
    case code(String)
    case paragraph(String)

    private static let fence = "```"
    private static let bulletMarkers = ["- ", "* ", "• "]
    private static let numberedPattern = #/^(\d+[.)])\s+(.*)$/#

    static func parse(_ markdown: String) -> [MarkdownBlock] {
        var blocks: [MarkdownBlock] = []
        var paragraph: [String] = []
        var tableRows: [[String]] = []
        var codeLines: [String]?

        func flushParagraph() {
            guard !paragraph.isEmpty else { return }
            blocks.append(.paragraph(paragraph.joined(separator: "\n")))
            paragraph.removeAll()
        }

        func flushTable() {
            guard !tableRows.isEmpty else { return }
            blocks.append(.table(tableRows))
            tableRows.removeAll()
        }

        for rawLine in markdown.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix(fence) {
                if let lines = codeLines {
                    blocks.append(.code(lines.joined(separator: "\n")))
                    codeLines = nil
                } else {
                    flushParagraph()
                    flushTable()
                    codeLines = []
                }
                continue
            }
            if codeLines != nil {
                codeLines?.append(rawLine)
                continue
            }
            if line.hasPrefix("|") {
                flushParagraph()
                if !isSeparatorRow(line) { tableRows.append(cells(of: line)) }
                continue
            }
            flushTable()
            if line.isEmpty {
                flushParagraph()
            } else if line.hasPrefix("#") {
                flushParagraph()
                blocks.append(.heading(line.drop { $0 == "#" }.trimmingCharacters(in: .whitespaces)))
            } else if let marker = bulletMarkers.first(where: line.hasPrefix) {
                flushParagraph()
                blocks.append(.bullet(String(line.dropFirst(marker.count))))
            } else if let match = line.wholeMatch(of: numberedPattern) {
                flushParagraph()
                blocks.append(.numbered(marker: String(match.output.1), text: String(match.output.2)))
            } else {
                paragraph.append(line)
            }
        }
        if let codeLines { blocks.append(.code(codeLines.joined(separator: "\n"))) }
        flushParagraph()
        flushTable()
        return blocks
    }

    private static func isSeparatorRow(_ line: String) -> Bool {
        line.allSatisfy { "|-: ".contains($0) }
    }

    private static func cells(of line: String) -> [String] {
        line.trimmingCharacters(in: CharacterSet(charactersIn: "| "))
            .components(separatedBy: "|")
            .map { $0.trimmingCharacters(in: .whitespaces) }
    }
}

struct MarkdownText: View {
    let text: String
    var fontSize: CGFloat = 13

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(MarkdownBlock.parse(text).enumerated()), id: \.offset) { _, block in
                blockView(block)
            }
        }
        .font(.system(size: fontSize))
        .lineSpacing(fontSize * 0.28)
        .textSelection(.enabled)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func blockView(_ block: MarkdownBlock) -> some View {
        switch block {
        case .heading(let title):
            Text(Self.inline(title)).font(.system(size: fontSize + 2, weight: .semibold)).padding(.top, 4)
        case .bullet(let item):
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("•").foregroundStyle(.secondary)
                Text(Self.inline(item))
            }
        case .numbered(let marker, let item):
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(marker).foregroundStyle(.secondary).monospacedDigit()
                Text(Self.inline(item))
            }
        case .table(let rows):
            MarkdownTable(rows: rows)
        case .code(let code):
            Text(code)
                .font(.system(size: 11.5, design: .monospaced))
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.primary.opacity(0.05)))
        case .paragraph(let paragraph):
            Text(Self.inline(paragraph))
        }
    }

    static func inline(_ text: String) -> AttributedString {
        let options = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        return (try? AttributedString(markdown: text, options: options)) ?? AttributedString(text)
    }
}

struct MarkdownTable: View {
    let rows: [[String]]

    var body: some View {
        ScrollView(.horizontal) {
            Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 7) {
                ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
                    GridRow {
                        ForEach(Array(row.enumerated()), id: \.offset) { _, cell in
                            Text(MarkdownText.inline(cell))
                                .font(.system(size: 11.5, weight: index == 0 ? .semibold : .regular))
                                .frame(maxWidth: 180, alignment: .leading)
                        }
                    }
                    if index == 0 { Divider().gridCellUnsizedAxes(.horizontal) }
                }
            }
            .padding(10)
        }
        .scrollIndicators(.never)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.primary.opacity(0.03)))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Color.primary.opacity(0.08)))
    }
}

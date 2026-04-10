import SwiftUI
import SwiftMath
import Markdown

private typealias AppImage = SwiftUI.Image
private typealias AppLink = SwiftUI.Link
private typealias AppText = SwiftUI.Text

struct AIMarkdownContentView: View {
    let text: String
    let style: AIMarkdownStyle

    private var blocks: [AIMarkdownBlock] {
        AIMarkdownASTParser.blocks(from: text)
    }

    var body: some View {
        blocksView(blocks)
            .lineLimit(nil)
            .fixedSize(horizontal: false, vertical: true)
            .tint(style.tintColor)
    }

    private func blocksView(_ blocks: [AIMarkdownBlock], spacing: CGFloat = 10) -> AnyView {
        AnyView(
            VStack(alignment: .leading, spacing: spacing) {
                ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                    blockView(block)
                }
            }
        )
    }

    private func blockView(_ block: AIMarkdownBlock) -> AnyView {
        switch block {
        case .heading(let level, let content):
            return AnyView(
                markdownText(content, pointSize: style.headingPointSize(for: level))
                    .font(style.headingFont(for: level))
                    .foregroundStyle(style.textColor)
                    .multilineTextAlignment(style.paragraphTextAlignment)
                    .lineSpacing(4)
            )

        case .horizontalRule:
            return AnyView(
                RoundedRectangle(cornerRadius: 999, style: .continuous)
                    .fill(style.textColor.opacity(0.22))
                    .frame(height: 1.5)
                    .frame(minWidth: 32, maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 4)
            )

        case .paragraph(let content):
            return AnyView(paragraphView(content))

        case .unorderedList(let items):
            return AnyView(
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                        listItemView(item, marker: listMarker(for: item, orderedIndex: nil))
                    }
                }
            )

        case .orderedList(let startIndex, let items):
            return AnyView(
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                        listItemView(item, marker: listMarker(for: item, orderedIndex: startIndex + index))
                    }
                }
            )

        case .quote(let contentBlocks):
            return AnyView(
                HStack(alignment: .top, spacing: 10) {
                    RoundedRectangle(cornerRadius: 999, style: .continuous)
                        .fill(style.quoteTintColor.opacity(0.7))
                        .frame(width: 3)

                    blocksView(contentBlocks, spacing: 6)
                }
            )

        case .displayMath(let latex):
            return AnyView(displayMathView(latex))

        case .image(let image):
            return AnyView(imageBlockView(image))

        case .table(let table):
            return AnyView(tableView(table))

        case .code(let language, let code):
            return AnyView(
                VStack(alignment: .leading, spacing: 8) {
                    if let language, !language.isEmpty {
                        AppText(language.uppercased())
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(style.textColor.opacity(0.7))
                    }

                    ScrollView(.horizontal, showsIndicators: false) {
                        AppText(verbatim: code)
                            .font(style.codeFont)
                            .foregroundStyle(style.codeTextColor)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(
                    style.codeBackgroundColor,
                    in: RoundedRectangle(cornerRadius: 14, style: .continuous)
                )
            )

        case .directive(let name, let argumentText, let contentBlocks):
            return AnyView(
                directiveView(
                    name: name,
                    argumentText: argumentText,
                    contentBlocks: contentBlocks
                )
            )

        case .container(let contentBlocks):
            return AnyView(blocksView(contentBlocks, spacing: 6))

        case .html(let rawHTML):
            return AnyView(styledVerbatimText(rawHTML))
        }
    }

    private func listItemView(_ item: AIMarkdownListItem, marker: String) -> AnyView {
        AnyView(
            HStack(alignment: .top, spacing: 8) {
                AppText(marker)
                    .font(style.baseFont.weight(.semibold))
                    .foregroundStyle(style.textColor)

                blocksView(item.blocks, spacing: 6)
            }
        )
    }

    private func listMarker(for item: AIMarkdownListItem, orderedIndex: Int?) -> String {
        if let checkbox = item.checkbox {
            switch checkbox {
            case .checked:
                return "[x]"
            case .unchecked:
                return "[ ]"
            }
        }

        if let orderedIndex {
            return "\(orderedIndex)."
        }

        return "\u{2022}"
    }

    @ViewBuilder
    private func paragraphView(_ content: String) -> some View {
        let lines = content.components(separatedBy: "\n")

        if lines.count == 1 {
            if let latex = isolatedMath(in: content) {
                displayMathView(latex)
            } else {
                styledParagraphText(content)
            }
        } else {
            VStack(alignment: .leading, spacing: 4) {
                ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                    styledParagraphText(line)
                }
            }
        }
    }

    private func styledParagraphText(_ content: String) -> some View {
        markdownText(content, pointSize: style.basePointSize)
            .font(style.baseFont)
            .foregroundStyle(style.textColor)
            .multilineTextAlignment(style.paragraphTextAlignment)
            .lineSpacing(4)
    }

    private func styledVerbatimText(_ content: String) -> some View {
        AppText(verbatim: content)
            .font(style.baseFont)
            .foregroundStyle(style.textColor)
            .multilineTextAlignment(style.paragraphTextAlignment)
            .lineSpacing(4)
    }

    private func isolatedMath(in content: String) -> String? {
        let segments = AIMarkdownInlineSegment.segments(from: content)
        guard segments.count == 1,
              case .math(let latex, _) = segments[0] else {
            return nil
        }

        return latex
    }

    @ViewBuilder
    private func displayMathView(_ latex: String) -> some View {
        if let renderedMath = AIMathRenderer.render(
            latex: latex,
            fontSize: style.displayMathPointSize,
            textColor: MTColor(style.textColor),
            labelMode: .display
        ) {
            ScrollView(.horizontal, showsIndicators: false) {
                AppImage(uiImage: renderedMath.image)
                    .interpolation(.high)
                    .antialiased(true)
                    .accessibilityLabel(AppText(latex))
            }
            .scrollBounceBehavior(.basedOnSize, axes: .horizontal)
            .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            styledVerbatimText(latex)
        }
    }

    private func imageBlockView(_ image: AIMarkdownImage) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if let url = image.url {
                AppLink(destination: url) {
                    markdownImagePreview(for: image)
                }
                .buttonStyle(.plain)
            } else {
                markdownImagePreview(for: image)
            }

            if let caption = image.caption {
                AppText(caption)
                    .font(.caption)
                    .foregroundStyle(style.textColor.opacity(0.72))
                    .multilineTextAlignment(.leading)
            }
        }
        .frame(maxWidth: 320, alignment: .leading)
    }

    @ViewBuilder
    private func markdownImagePreview(for image: AIMarkdownImage) -> some View {
        if let url = image.url {
            AsyncImage(url: url, transaction: Transaction(animation: .easeInOut(duration: 0.2))) { phase in
                switch phase {
                case .empty:
                    imagePlaceholderView(label: image.placeholderTitle, showsProgress: true)
                case .success(let loadedImage):
                    loadedImage
                        .resizable()
                        .scaledToFit()
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                case .failure:
                    imagePlaceholderView(label: image.placeholderTitle, showsProgress: false)
                @unknown default:
                    imagePlaceholderView(label: image.placeholderTitle, showsProgress: false)
                }
            }
        } else {
            imagePlaceholderView(label: image.placeholderTitle, showsProgress: false)
        }
    }

    private func imagePlaceholderView(label: String, showsProgress: Bool) -> some View {
        VStack(spacing: 10) {
            if showsProgress {
                ProgressView()
            } else {
                AppImage(systemName: "photo")
                    .font(.title3.weight(.medium))
                    .foregroundStyle(style.textColor.opacity(0.72))
            }

            AppText(label)
                .font(.caption)
                .foregroundStyle(style.textColor.opacity(0.8))
                .multilineTextAlignment(.center)
                .lineLimit(3)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 180)
        .padding(.horizontal, 12)
        .background(
            style.codeBackgroundColor,
            in: RoundedRectangle(cornerRadius: 16, style: .continuous)
        )
    }

    private func tableView(_ table: AIMarkdownTable) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            Grid(alignment: .leading, horizontalSpacing: 0, verticalSpacing: 0) {
                if !table.headers.isEmpty {
                    GridRow {
                        ForEach(Array(table.normalizedHeaders.enumerated()), id: \.offset) { index, header in
                            tableCellView(
                                content: header,
                                alignment: table.alignment(at: index),
                                isHeader: true
                            )
                        }
                    }

                    if !table.normalizedRows.isEmpty {
                        Divider()
                            .gridCellColumns(max(table.columnCount, 1))
                    }
                }

                ForEach(Array(table.normalizedRows.enumerated()), id: \.offset) { rowIndex, row in
                    GridRow {
                        ForEach(Array(row.enumerated()), id: \.offset) { columnIndex, cellContent in
                            tableCellView(
                                content: cellContent,
                                alignment: table.alignment(at: columnIndex),
                                isHeader: false
                            )
                        }
                    }

                    if rowIndex < table.normalizedRows.count - 1 {
                        Divider()
                            .gridCellColumns(max(table.columnCount, 1))
                    }
                }
            }
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(style.codeBackgroundColor.opacity(0.82))
            )
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(style.textColor.opacity(0.08), lineWidth: 1)
            }
        }
        .scrollBounceBehavior(.basedOnSize, axes: .horizontal)
    }

    private func tableCellView(
        content: String,
        alignment: AIMarkdownTableAlignment,
        isHeader: Bool
    ) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            if content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                AppText(" ")
                    .font(isHeader ? style.baseFont.weight(.semibold) : style.baseFont)
                    .frame(maxWidth: .infinity, alignment: tableCellFrameAlignment(for: alignment))
            } else {
                markdownText(content, pointSize: style.basePointSize)
                    .font(isHeader ? style.baseFont.weight(.semibold) : style.baseFont)
                    .foregroundStyle(style.textColor)
                    .multilineTextAlignment(tableCellTextAlignment(for: alignment))
                    .lineSpacing(4)
                    .frame(maxWidth: .infinity, alignment: tableCellFrameAlignment(for: alignment))
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(minWidth: 92, alignment: tableCellFrameAlignment(for: alignment))
        .background(
            isHeader
                ? style.codeBackgroundColor.opacity(0.96)
                : Color.clear
        )
    }

    private func tableCellFrameAlignment(for alignment: AIMarkdownTableAlignment) -> Alignment {
        switch alignment {
        case .leading:
            return .leading
        case .center:
            return .center
        case .trailing:
            return .trailing
        }
    }

    private func tableCellTextAlignment(for alignment: AIMarkdownTableAlignment) -> TextAlignment {
        switch alignment {
        case .leading:
            return .leading
        case .center:
            return .center
        case .trailing:
            return .trailing
        }
    }

    private func directiveView(
        name: String,
        argumentText: String?,
        contentBlocks: [AIMarkdownBlock]
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                AppText("@\(name)")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(style.tintColor)

                if let argumentText, !argumentText.isEmpty {
                    AppText(verbatim: "(\(argumentText))")
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundStyle(style.textColor.opacity(0.72))
                }
            }

            if !contentBlocks.isEmpty {
                blocksView(contentBlocks, spacing: 6)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            style.codeBackgroundColor.opacity(0.74),
            in: RoundedRectangle(cornerRadius: 14, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(style.tintColor.opacity(0.14), lineWidth: 1)
        }
    }

    private func markdownText(_ content: String, pointSize: CGFloat) -> AppText {
        let segments = AIMarkdownInlineSegment.segments(from: content)
        guard segments.contains(where: \.containsMath) else {
            return plainMarkdownText(content)
        }

        guard let firstSegment = segments.first else {
            return AppText("")
        }

        return segments.dropFirst().reduce(segmentText(firstSegment, pointSize: pointSize)) { partialResult, segment in
            AppText("\(partialResult)\(segmentText(segment, pointSize: pointSize))")
        }
    }

    private func segmentText(_ segment: AIMarkdownInlineSegment, pointSize: CGFloat) -> AppText {
        switch segment {
        case .text(let content):
            return plainMarkdownText(content)

        case .math(let latex, let source):
            guard let renderedMath = AIMathRenderer.render(
                latex: latex,
                fontSize: pointSize,
                textColor: MTColor(style.textColor),
                labelMode: .text
            ) else {
                return AppText(verbatim: source)
            }

            return AppText(AppImage(uiImage: renderedMath.image))
        }
    }

    private func plainMarkdownText(_ content: String) -> AppText {
        guard let attributed = style.attributedString(for: content) else {
            return AppText(verbatim: content)
        }

        return AppText(attributed)
    }
}

struct AIMarkdownStyle {
    let baseFont: Font
    let baseTextStyle: UIFont.TextStyle
    let textColor: Color
    let tintColor: Color
    let codeTextColor: Color
    let codeBackgroundColor: Color
    let quoteTintColor: Color
    let paragraphTextAlignment: TextAlignment
    let codeFont: Font
    let codeTextStyle: UIFont.TextStyle

    static let assistantBubble = AIMarkdownStyle(
        baseFont: .body,
        baseTextStyle: .body,
        textColor: .primary,
        tintColor: .accentColor,
        codeTextColor: .primary,
        codeBackgroundColor: Color(uiColor: .secondarySystemGroupedBackground),
        quoteTintColor: .orange,
        paragraphTextAlignment: .leading,
        codeFont: .system(.footnote, design: .monospaced),
        codeTextStyle: .footnote
    )

    static let userBubble = AIMarkdownStyle(
        baseFont: .body,
        baseTextStyle: .body,
        textColor: .white,
        tintColor: .white,
        codeTextColor: .white,
        codeBackgroundColor: .white.opacity(0.14),
        quoteTintColor: .white,
        paragraphTextAlignment: .leading,
        codeFont: .system(.footnote, design: .monospaced),
        codeTextStyle: .footnote
    )

    static let reasoning = AIMarkdownStyle(
        baseFont: .footnote,
        baseTextStyle: .footnote,
        textColor: .secondary,
        tintColor: .accentColor,
        codeTextColor: .primary,
        codeBackgroundColor: Color(uiColor: .tertiarySystemGroupedBackground),
        quoteTintColor: .secondary,
        paragraphTextAlignment: .leading,
        codeFont: .system(.caption, design: .monospaced),
        codeTextStyle: .caption1
    )

    var basePointSize: CGFloat {
        UIFont.preferredFont(forTextStyle: baseTextStyle).pointSize
    }

    var displayMathPointSize: CGFloat {
        basePointSize + 2
    }

    func headingFont(for level: Int) -> Font {
        switch level {
        case 1:
            return .title3.weight(.semibold)
        case 2:
            return .headline.weight(.semibold)
        case 3:
            return .subheadline.weight(.semibold)
        default:
            return baseFont.weight(.semibold)
        }
    }

    func headingPointSize(for level: Int) -> CGFloat {
        switch level {
        case 1:
            return UIFont.preferredFont(forTextStyle: .title3).pointSize
        case 2:
            return UIFont.preferredFont(forTextStyle: .headline).pointSize
        case 3:
            return UIFont.preferredFont(forTextStyle: .subheadline).pointSize
        default:
            return basePointSize
        }
    }

    func attributedString(for content: String) -> AttributedString? {
        try? AttributedString(
            markdown: content,
            options: AttributedString.MarkdownParsingOptions(
                interpretedSyntax: .inlineOnlyPreservingWhitespace,
                failurePolicy: .returnPartiallyParsedIfPossible
            )
        )
    }
}

private struct AIMathRenderResult {
    let image: UIImage
}

private enum AIMathRenderer {
    static func render(
        latex: String,
        fontSize: CGFloat,
        textColor: MTColor,
        labelMode: MTMathUILabelMode
    ) -> AIMathRenderResult? {
        var mathImage = MathImage(
            latex: latex,
            fontSize: fontSize,
            textColor: textColor,
            labelMode: labelMode,
            textAlignment: .left
        )
        let (error, image, _) = mathImage.asImage()

        guard error == nil, let image else {
            return nil
        }

        return AIMathRenderResult(image: image)
    }
}

private enum AIMarkdownInlineSegment: Equatable {
    case text(String)
    case math(latex: String, source: String)

    var containsMath: Bool {
        switch self {
        case .text:
            return false
        case .math:
            return true
        }
    }

    static func segments(from rawText: String) -> [AIMarkdownInlineSegment] {
        var segments: [AIMarkdownInlineSegment] = []
        var currentText = ""
        var index = rawText.startIndex
        var isInsideCodeSpan = false

        func appendCurrentText() {
            guard !currentText.isEmpty else {
                return
            }

            segments.append(.text(currentText))
            currentText = ""
        }

        while index < rawText.endIndex {
            let remainingText = rawText[index...]

            if remainingText.hasPrefix("`") {
                isInsideCodeSpan.toggle()
                currentText.append("`")
                index = rawText.index(after: index)
                continue
            }

            if !isInsideCodeSpan,
               remainingText.hasPrefix("\\("),
               !isEscaped(rawText, at: index),
               let start = rawText.index(index, offsetBy: 2, limitedBy: rawText.endIndex),
               let closingRange = unescapedRange(of: "\\)", in: rawText, from: start) {
                let latex = String(rawText[start..<closingRange.lowerBound])
                let trimmedLatex = latex.trimmingCharacters(in: .whitespacesAndNewlines)

                if !trimmedLatex.isEmpty {
                    appendCurrentText()
                    segments.append(
                        .math(
                            latex: trimmedLatex,
                            source: String(rawText[index..<closingRange.upperBound])
                        )
                    )
                    index = closingRange.upperBound
                    continue
                }
            }

            if !isInsideCodeSpan,
               remainingText.hasPrefix("$$"),
               !isEscaped(rawText, at: index) {
                let latexStart = rawText.index(index, offsetBy: 2)
                if latexStart < rawText.endIndex,
                   let closingRange = unescapedRange(of: "$$", in: rawText, from: latexStart) {
                    let latex = String(rawText[latexStart..<closingRange.lowerBound])
                    let trimmedLatex = latex.trimmingCharacters(in: .whitespacesAndNewlines)

                    if !trimmedLatex.isEmpty {
                        appendCurrentText()
                        segments.append(
                            .math(
                                latex: trimmedLatex,
                                source: String(rawText[index..<closingRange.upperBound])
                            )
                        )
                        index = closingRange.upperBound
                        continue
                    }
                }
            }

            if !isInsideCodeSpan,
               rawText[index] == "$",
               isValidInlineDollarOpeningDelimiter(in: rawText, at: index),
               let closingIndex = nextInlineDollarClosingDelimiter(in: rawText, from: rawText.index(after: index)) {
                let latexStart = rawText.index(after: index)
                let latex = String(rawText[latexStart..<closingIndex])
                let trimmedLatex = latex.trimmingCharacters(in: .whitespacesAndNewlines)

                if !trimmedLatex.isEmpty {
                    appendCurrentText()
                    segments.append(
                        .math(
                            latex: trimmedLatex,
                            source: String(rawText[index...closingIndex])
                        )
                    )
                    index = rawText.index(after: closingIndex)
                    continue
                }
            }

            currentText.append(rawText[index])
            index = rawText.index(after: index)
        }

        appendCurrentText()
        return segments
    }

    private static func nextInlineDollarClosingDelimiter(in text: String, from start: String.Index) -> String.Index? {
        var currentIndex = start

        while currentIndex < text.endIndex {
            if text[currentIndex] == "$",
               isValidInlineDollarClosingDelimiter(in: text, at: currentIndex) {
                return currentIndex
            }

            currentIndex = text.index(after: currentIndex)
        }

        return nil
    }

    private static func isValidInlineDollarOpeningDelimiter(in text: String, at index: String.Index) -> Bool {
        guard text[index] == "$",
              !isEscaped(text, at: index) else {
            return false
        }

        let nextIndex = text.index(after: index)
        if nextIndex < text.endIndex {
            let nextCharacter = text[nextIndex]
            if nextCharacter == "$" || nextCharacter.isWhitespace {
                return false
            }
        }

        if index > text.startIndex {
            let previousCharacter = text[text.index(before: index)]
            if previousCharacter.isNumber || previousCharacter == "$" {
                return false
            }
        }

        return true
    }

    private static func isValidInlineDollarClosingDelimiter(in text: String, at index: String.Index) -> Bool {
        guard text[index] == "$",
              !isEscaped(text, at: index),
              index > text.startIndex else {
            return false
        }

        let previousCharacter = text[text.index(before: index)]
        if previousCharacter == "$" || previousCharacter.isWhitespace {
            return false
        }

        let nextIndex = text.index(after: index)
        if nextIndex < text.endIndex {
            let nextCharacter = text[nextIndex]
            if nextCharacter.isNumber || nextCharacter == "$" {
                return false
            }
        }

        return true
    }

    private static func unescapedRange(
        of delimiter: String,
        in text: String,
        from start: String.Index
    ) -> Range<String.Index>? {
        var searchStart = start

        while searchStart < text.endIndex,
              let range = text.range(of: delimiter, range: searchStart..<text.endIndex) {
            if !isEscaped(text, at: range.lowerBound) {
                return range
            }

            searchStart = range.upperBound
        }

        return nil
    }

    private static func isEscaped(_ text: String, at index: String.Index) -> Bool {
        var slashCount = 0
        var currentIndex = index

        while currentIndex > text.startIndex {
            currentIndex = text.index(before: currentIndex)
            guard text[currentIndex] == "\\" else {
                break
            }

            slashCount += 1
        }

        return slashCount.isMultiple(of: 2) == false
    }
}

private struct AIMarkdownImage {
    let source: String?
    let title: String?
    let altText: String

    var url: URL? {
        guard let source,
              let url = URL(string: source),
              let scheme = url.scheme,
              !scheme.isEmpty else {
            return nil
        }

        return url
    }

    var caption: String? {
        if let title = normalized(title) {
            return title
        }

        return normalized(altText)
    }

    var placeholderTitle: String {
        if let caption {
            return caption
        }

        if let sourceName = normalized(sourceDisplayName) {
            return sourceName
        }

        return "图片"
    }

    private var sourceDisplayName: String? {
        guard let source else {
            return nil
        }

        if let url = URL(string: source),
           let lastPathComponent = normalized(url.lastPathComponent) {
            return lastPathComponent
        }

        return source
    }

    private func normalized(_ value: String?) -> String? {
        guard let trimmedValue = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmedValue.isEmpty else {
            return nil
        }

        return trimmedValue
    }
}

private enum AIMarkdownTableAlignment {
    case leading
    case center
    case trailing
}

private struct AIMarkdownTable {
    let headers: [String]
    let rows: [[String]]
    let alignments: [AIMarkdownTableAlignment]

    var columnCount: Int {
        max(
            headers.count,
            max(rows.map(\.count).max() ?? 0, alignments.count)
        )
    }

    var normalizedHeaders: [String] {
        padded(headers)
    }

    var normalizedRows: [[String]] {
        rows.map(padded)
    }

    func alignment(at index: Int) -> AIMarkdownTableAlignment {
        guard index < alignments.count else {
            return .leading
        }

        return alignments[index]
    }

    private func padded(_ cells: [String]) -> [String] {
        guard cells.count < columnCount else {
            return cells
        }

        return cells + Array(repeating: "", count: columnCount - cells.count)
    }
}

private struct AIMarkdownListItem {
    let checkbox: Checkbox?
    let blocks: [AIMarkdownBlock]
}

private indirect enum AIMarkdownBlock {
    case heading(level: Int, content: String)
    case horizontalRule
    case paragraph(String)
    case unorderedList([AIMarkdownListItem])
    case orderedList(startIndex: Int, [AIMarkdownListItem])
    case quote([AIMarkdownBlock])
    case displayMath(String)
    case image(AIMarkdownImage)
    case table(AIMarkdownTable)
    case code(language: String?, code: String)
    case directive(name: String, argumentText: String?, content: [AIMarkdownBlock])
    case container([AIMarkdownBlock])
    case html(String)
}

private enum AIMarkdownASTParser {
    static func blocks(from rawText: String) -> [AIMarkdownBlock] {
        AIMarkdownFragment.fragments(from: rawText).flatMap { fragment in
            switch fragment {
            case .markdown(let source):
                return blocks(
                    from: Document(
                        parsing: source,
                        options: [.parseBlockDirectives, .parseSymbolLinks]
                    )
                )
            case .displayMath(let latex):
                return [.displayMath(latex)]
            }
        }
    }

    private static func blocks(from document: Document) -> [AIMarkdownBlock] {
        Array(document.blockChildren).compactMap { block(from: $0) }
    }

    private static func block(from markup: any BlockMarkup) -> AIMarkdownBlock? {
        switch markup {
        case let heading as Heading:
            return .heading(
                level: heading.level,
                content: inlineMarkdown(from: heading.inlineChildren)
            )

        case _ as ThematicBreak:
            return .horizontalRule

        case let paragraph as Paragraph:
            if let image = standaloneImage(from: paragraph.inlineChildren) {
                return .image(image)
            }

            return .paragraph(inlineMarkdown(from: paragraph.inlineChildren))

        case let unorderedList as UnorderedList:
            return .unorderedList(
                Array(unorderedList.listItems).map { listItem(from: $0) }
            )

        case let orderedList as OrderedList:
            return .orderedList(
                startIndex: Int(orderedList.startIndex),
                Array(orderedList.listItems).map { listItem(from: $0) }
            )

        case let quote as BlockQuote:
            return .quote(childBlocks(from: quote))

        case let table as Markdown.Table:
            return .table(tableBlock(from: table))

        case let codeBlock as CodeBlock:
            return .code(language: codeBlock.language, code: codeBlock.code)

        case let directive as BlockDirective:
            return .directive(
                name: directive.name,
                argumentText: directiveArgumentText(from: directive.argumentText),
                content: childBlocks(from: directive)
            )

        case let customBlock as CustomBlock:
            return .container(childBlocks(from: customBlock))

        case let htmlBlock as HTMLBlock:
            return .html(htmlBlock.rawHTML)

        default:
            return nil
        }
    }

    private static func listItem(from item: ListItem) -> AIMarkdownListItem {
        let childBlocks = Array(item.blockChildren).compactMap { block(from: $0) }

        return AIMarkdownListItem(
            checkbox: item.checkbox,
            blocks: childBlocks.isEmpty ? [.paragraph("")] : childBlocks
        )
    }

    private static func inlineMarkdown<Items: Sequence>(from items: Items) -> String
    where Items.Element == any InlineMarkup {
        items.map { inlineMarkdown(from: $0) }.joined()
    }

    private static func inlineMarkdown(from markup: any InlineMarkup) -> String {
        switch markup {
        case let text as Markdown.Text:
            return text.string

        case _ as SoftBreak, _ as LineBreak:
            return "\n"

        case let inlineCode as InlineCode:
            return "`\(inlineCode.code)`"

        case let emphasis as Emphasis:
            return "*\(inlineMarkdown(from: emphasis.inlineChildren))*"

        case let strong as Strong:
            return "**\(inlineMarkdown(from: strong.inlineChildren))**"

        case let strikethrough as Strikethrough:
            return "~~\(inlineMarkdown(from: strikethrough.inlineChildren))~~"

        case let link as Markdown.Link:
            let titleSuffix = link.title.map { " \"\($0)\"" } ?? ""
            return "[\(inlineMarkdown(from: link.inlineChildren))](\(link.destination ?? "")\(titleSuffix))"

        case let image as Markdown.Image:
            let titleSuffix = image.title.map { " \"\($0)\"" } ?? ""
            return "![\(inlineMarkdown(from: image.inlineChildren))](\(image.source ?? "")\(titleSuffix))"

        case let symbolLink as SymbolLink:
            return "``\(symbolLink.destination ?? "")``"

        case let inlineAttributes as InlineAttributes:
            return "^[\(inlineMarkdown(from: inlineAttributes.inlineChildren))](\(inlineAttributes.attributes))"

        case let inlineHTML as InlineHTML:
            return inlineHTML.rawHTML

        default:
            return markup.format()
        }
    }

    private static func childBlocks(from markup: any Markup) -> [AIMarkdownBlock] {
        Array(markup.children).compactMap { child in
            guard let blockChild = child as? any BlockMarkup else {
                return nil
            }

            return block(from: blockChild)
        }
    }

    private static func standaloneImage<Items: Sequence>(from items: Items) -> AIMarkdownImage?
    where Items.Element == any InlineMarkup {
        var discoveredImage: AIMarkdownImage?

        for item in items {
            switch item {
            case let text as Markdown.Text:
                if !text.string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    return nil
                }

            case _ as SoftBreak, _ as LineBreak:
                continue

            case let image as Markdown.Image:
                guard discoveredImage == nil else {
                    return nil
                }

                discoveredImage = AIMarkdownImage(
                    source: image.source,
                    title: image.title,
                    altText: inlineMarkdown(from: image.inlineChildren)
                )

            default:
                return nil
            }
        }

        return discoveredImage
    }

    private static func tableBlock(from table: Markdown.Table) -> AIMarkdownTable {
        let children = Array(table.children)
        let headerCells: [String]
        if let header = children.first as? Markdown.Table.Head {
            headerCells = tableCells(from: header)
        } else {
            headerCells = []
        }

        let bodyRows: [[String]]
        if let body = children.dropFirst().first as? Markdown.Table.Body {
            bodyRows = Array(body.children).compactMap { $0 as? Markdown.Table.Row }.map { row in
                tableCells(from: row)
            }
        } else {
            bodyRows = []
        }

        let alignments = table.columnAlignments.map(tableAlignment(from:))

        return AIMarkdownTable(
            headers: headerCells,
            rows: bodyRows,
            alignments: alignments
        )
    }

    private static func tableCells(from row: any Markup) -> [String] {
        Array(row.children).compactMap { child in
            guard let cell = child as? Markdown.Table.Cell else {
                return nil
            }

            return inlineMarkdown(from: cell.inlineChildren)
        }
    }

    private static func tableAlignment(from alignment: Markdown.Table.ColumnAlignment?) -> AIMarkdownTableAlignment {
        switch alignment {
        case .center:
            return .center
        case .right:
            return .trailing
        case .left, .none:
            return .leading
        }
    }

    private static func directiveArgumentText(from argumentText: DirectiveArgumentText) -> String? {
        let joinedText = argumentText.segments
            .map(\.untrimmedText)
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !joinedText.isEmpty else {
            return nil
        }

        return joinedText
    }
}

private enum AIMarkdownFragment {
    case markdown(String)
    case displayMath(String)

    static func fragments(from rawText: String) -> [AIMarkdownFragment] {
        let normalizedText = rawText
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        let lines = normalizedText.components(separatedBy: "\n")
        var fragments: [AIMarkdownFragment] = []
        var markdownLines: [String] = []
        var index = 0

        func flushMarkdownLines() {
            let markdown = markdownLines.joined(separator: "\n")
            if !markdown.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                fragments.append(.markdown(markdown))
            }
            markdownLines.removeAll(keepingCapacity: true)
        }

        while index < lines.count {
            let line = lines[index]
            let trimmedLine = line.trimmingCharacters(in: .whitespaces)

            if let fence = codeFenceDelimiter(from: trimmedLine) {
                markdownLines.append(line)
                index += 1

                while index < lines.count {
                    let candidate = lines[index]
                    markdownLines.append(candidate)
                    index += 1

                    if candidate.trimmingCharacters(in: .whitespaces).hasPrefix(fence) {
                        break
                    }
                }

                continue
            }

            if let displayMath = displayMathBlock(in: lines, startingAt: index) {
                flushMarkdownLines()
                fragments.append(.displayMath(displayMath.latex))
                index = displayMath.nextIndex
                continue
            }

            markdownLines.append(line)
            index += 1
        }

        flushMarkdownLines()
        return fragments
    }

    private static func codeFenceDelimiter(from line: String) -> String? {
        guard let marker = line.first, marker == "`" || marker == "~" else {
            return nil
        }

        let fenceLength = line.prefix { $0 == marker }.count
        guard fenceLength >= 3 else {
            return nil
        }

        return String(repeating: String(marker), count: fenceLength)
    }

    private static func displayMathBlock(
        in lines: [String],
        startingAt startIndex: Int
    ) -> (latex: String, nextIndex: Int)? {
        let trimmedLine = lines[startIndex].trimmingCharacters(in: .whitespaces)

        if let block = delimitedDisplayMathBlock(
            in: lines,
            startingAt: startIndex,
            trimmedStartLine: trimmedLine,
            openingDelimiter: "$$",
            closingDelimiter: "$$"
        ) {
            return block
        }

        return delimitedDisplayMathBlock(
            in: lines,
            startingAt: startIndex,
            trimmedStartLine: trimmedLine,
            openingDelimiter: "\\[",
            closingDelimiter: "\\]"
        )
    }

    private static func delimitedDisplayMathBlock(
        in lines: [String],
        startingAt startIndex: Int,
        trimmedStartLine: String,
        openingDelimiter: String,
        closingDelimiter: String
    ) -> (latex: String, nextIndex: Int)? {
        guard trimmedStartLine.hasPrefix(openingDelimiter) else {
            return nil
        }

        let openingEndIndex = trimmedStartLine.index(
            trimmedStartLine.startIndex,
            offsetBy: openingDelimiter.count
        )
        let trailingText = String(trimmedStartLine[openingEndIndex...])

        if let closingRange = trailingText.range(of: closingDelimiter) {
            let suffix = trailingText[closingRange.upperBound...].trimmingCharacters(in: .whitespacesAndNewlines)
            guard suffix.isEmpty else {
                return nil
            }

            let latex = trailingText[..<closingRange.lowerBound].trimmingCharacters(in: .whitespacesAndNewlines)
            guard !latex.isEmpty else {
                return nil
            }

            return (String(latex), startIndex + 1)
        }

        var latexLines: [String] = []
        let trimmedTrailingText = trailingText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedTrailingText.isEmpty {
            latexLines.append(trimmedTrailingText)
        }

        var currentIndex = startIndex + 1
        while currentIndex < lines.count {
            let currentLine = lines[currentIndex]
            let trimmedCurrentLine = currentLine.trimmingCharacters(in: .whitespaces)

            if let closingRange = trimmedCurrentLine.range(of: closingDelimiter) {
                let suffix = trimmedCurrentLine[closingRange.upperBound...].trimmingCharacters(in: .whitespacesAndNewlines)
                guard suffix.isEmpty else {
                    return nil
                }

                let linePrefix = trimmedCurrentLine[..<closingRange.lowerBound].trimmingCharacters(in: .whitespacesAndNewlines)
                if !linePrefix.isEmpty {
                    latexLines.append(String(linePrefix))
                }

                let latex = latexLines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
                guard !latex.isEmpty else {
                    return nil
                }

                return (latex, currentIndex + 1)
            }

            latexLines.append(currentLine)
            currentIndex += 1
        }

        return nil
    }
}

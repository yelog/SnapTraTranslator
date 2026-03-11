import AppKit
import SwiftUI

struct OverlayView: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.colorScheme) private var colorScheme
    @State private var isParagraphHeaderHovered = false
    @State private var isParagraphHeaderDragging = false
    private let wordOverlayWidth: CGFloat = 380
    private let paragraphOverlayWidth: CGFloat = 520
    private let compactSectionMinHeight: CGFloat = 28

    private var overlayWidth: CGFloat {
        if let preferred = model.overlayPreferredWidth {
            return preferred
        }
        switch model.overlayState {
        case .paragraphLoading, .paragraphResult:
            return paragraphOverlayWidth
        default:
            return wordOverlayWidth
        }
    }

    private var showsParagraphOverlayControls: Bool {
        switch model.overlayState {
        case .paragraphLoading, .paragraphResult:
            return true
        default:
            return !model.settings.continuousTranslation
        }
    }

    private var isParagraphOverlayMode: Bool {
        switch model.overlayState {
        case .paragraphLoading, .paragraphResult:
            return true
        default:
            return false
        }
    }

    private var isVisible: Bool {
        if case .idle = model.overlayState { return false }
        return true
    }

    var body: some View {
        ZStack {
            if isVisible {
                overlayContent
            }
        }
    }

    @ViewBuilder
    private var overlayContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            switch model.overlayState {
            case .idle:
                EmptyView()

            case .loading(let word):
                loadingView(word: word)

            case .result(let content):
                resultView(content: content)

            case .paragraphLoading:
                paragraphLoadingView

            case .paragraphResult(let content):
                paragraphResultView(content: content)

            case .error(let message):
                errorView(message: message)

            case .noWord:
                noWordView
            }
        }
        .frame(width: overlayWidth, alignment: .leading)
        .background {
            ZStack {
                // More opaque material so background content doesn't bleed through
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(.regularMaterial)
                // Tint layer to reinforce system appearance over any background
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(colorScheme == .dark
                        ? Color.black.opacity(0.25)
                        : Color.white.opacity(0.25))
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .inset(by: 0.5)
                .stroke(
                    LinearGradient(
                        colors: colorScheme == .dark
                            ? [
                                .white.opacity(0.4),
                                .white.opacity(0.15),
                                .white.opacity(0.08),
                            ]
                            : [
                                .black.opacity(0.08),
                                .black.opacity(0.05),
                                .black.opacity(0.03),
                            ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
        )
        .shadow(color: .black.opacity(colorScheme == .dark ? 0.22 : 0.08), radius: 2, x: 0, y: 1)
        .shadow(color: .black.opacity(colorScheme == .dark ? 0.18 : 0.06), radius: 14, x: 0, y: 8)
        .onChange(of: isParagraphOverlayMode) { _, isParagraphMode in
            if !isParagraphMode {
                resetParagraphHeaderInteractionState()
            }
        }
        .onDisappear {
            resetParagraphHeaderInteractionState()
        }
    }

    // MARK: - Loading View

    @ViewBuilder
    private func loadingView(word: String?) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            if let word {
                Text(word)
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .foregroundStyle(.primary)
                    .tracking(0.2)
            }
            HStack(spacing: 8) {
                ProgressView()
                    .controlSize(.small)
                    .scaleEffect(0.85)
                Text("Translating")
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
                LoadingDotsView()
            }
        }
        .padding(.vertical, 16)
        .padding(.horizontal, 18)
    }

    // MARK: - Result View

    @ViewBuilder
    private func resultView(content: OverlayContent) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header: Word + Phonetic
            headerSection(content: content)

            // Primary Translation
            primaryTranslationSection(content: content)

            // Dictionary sections (one per dictionary source)
            if !content.dictionarySections.isEmpty {
                dictionarySectionsView(sections: content.dictionarySections)
            }
        }
    }

    private var paragraphLoadingView: some View {
        VStack(alignment: .leading, spacing: 0) {
            paragraphTopBar()

            paragraphBodyContainer {
                paragraphStatusCard(
                    title: paragraphOriginalSectionTitle,
                    message: L("Detecting text under cursor"),
                    detail: L("正在执行全屏 OCR 与段落定位"),
                    systemImage: "text.magnifyingglass",
                    showsSpinner: true
                )
            }
        }
    }

    @ViewBuilder
    private func paragraphResultView(content: ParagraphOverlayContent) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            paragraphTopBar()

            paragraphBodyContainer {
                if let originalText = content.originalText,
                   !originalText.isEmpty {
                    paragraphSectionCard(
                        title: paragraphOriginalSectionTitle,
                        copyText: originalText
                    ) {
                        paragraphTextContent(
                            text: originalText,
                            font: .systemFont(ofSize: 15, weight: .medium),
                            textColor: .labelColor,
                            preferredLineHeight: 22
                        )
                    }

                    // Native Translation Section (System Translation)
                    switch content.translationState {
                    case .loading:
                        paragraphSectionCard(
                            title: paragraphTranslationSectionTitle,
                            emphasis: true
                        ) {
                            HStack(spacing: 8) {
                                ProgressView()
                                    .controlSize(.small)
                                Text(L("Translating"))
                                    .font(.system(size: 13, weight: .medium, design: .rounded))
                                    .foregroundStyle(.secondary)
                                LoadingDotsView()
                            }
                        }

                    case .ready(let translatedText):
                        paragraphSectionCard(
                            title: paragraphTranslationSectionTitle,
                            copyText: translatedText,
                            emphasis: true
                        ) {
                            paragraphTextContent(
                                text: translatedText,
                                font: .systemFont(ofSize: 16, weight: .semibold),
                                textColor: .labelColor,
                                preferredLineHeight: 24
                            )
                        }

                    case .failed(let message):
                        paragraphSectionCard(
                            title: paragraphTranslationSectionTitle,
                            emphasis: true
                        ) {
                            paragraphErrorContent(message: message)
                        }
                    }

                    // Third-party Service Results Section
                    if !content.serviceResults.isEmpty {
                        ForEach(content.serviceResults) { result in
                            paragraphServiceResultCard(result: result)
                        }
                    }
                } else if case .failed(let message) = content.translationState {
                    paragraphStatusCard(
                        title: nil,
                        message: message,
                        systemImage: "exclamationmark.circle"
                    )
                }
            }
        }
    }

    @ViewBuilder
    private func paragraphServiceResultCard(result: ServiceTranslationResult) -> some View {
        let title = "\(result.sourceType.displayName)"

        switch result.state {
        case .loading:
            paragraphSectionCard(
                title: title,
                emphasis: false
            ) {
                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                    Text(L("Translating"))
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                    LoadingDotsView()
                }
            }

        case .ready(let translatedText):
            paragraphSectionCard(
                title: title,
                copyText: translatedText,
                emphasis: false
            ) {
                paragraphTextContent(
                    text: translatedText,
                    font: .systemFont(ofSize: 15, weight: .medium),
                    textColor: .labelColor,
                    preferredLineHeight: 22
                )
            }

        case .failed(let message):
            paragraphSectionCard(
                title: title,
                emphasis: false
            ) {
                paragraphErrorContent(message: message)
            }
        }
    }

    @ViewBuilder
    private func paragraphBodyContainer<Content: View>(
        @ViewBuilder content: () -> Content
    ) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                content()
            }
            .padding(.horizontal, 18)
            .padding(.top, 2)
            .padding(.bottom, 16)
        }
        .frame(maxHeight: 360)
    }

    @ViewBuilder
    private func paragraphSectionCard<Content: View>(
        title: String?,
        copyText: String? = nil,
        emphasis: Bool = false,
        @ViewBuilder content: () -> Content
    ) -> some View {
        ParagraphOverlaySectionCard(
            title: title,
            copyText: copyText,
            emphasis: emphasis,
            content: content
        )
    }

    @ViewBuilder
    private func paragraphStatusCard(
        title: String?,
        message: String,
        detail: String? = nil,
        systemImage: String,
        showsSpinner: Bool = false
    ) -> some View {
        paragraphSectionCard(title: title) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .center, spacing: 10) {
                    if showsSpinner {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Image(systemName: systemImage)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.secondary)
                    }

                    Text(message)
                        .font(.system(size: 15, weight: .medium, design: .rounded))
                        .foregroundStyle(.primary)
                }

                if let detail, !detail.isEmpty {
                    Text(detail)
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    @ViewBuilder
    private func paragraphTextContent(
        text: String,
        font: NSFont,
        textColor: NSColor,
        preferredLineHeight: CGFloat
    ) -> some View {
        SelectableTextView(
            text: text,
            font: font,
            textColor: textColor,
            preferredLineHeight: preferredLineHeight
        )
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func paragraphErrorContent(message: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.circle")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)
            Text(message)
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder
    private func paragraphTopBar() -> some View {
        HStack(spacing: 0) {
            Spacer()

            if showsParagraphOverlayControls {
                Button {
                    model.dismissOverlay()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 18, height: 18)
                        .background(
                            Circle()
                                .fill(colorScheme == .dark ? .white.opacity(0.08) : .black.opacity(0.045))
                        )
                        .overlay(
                            Circle()
                                .stroke(colorScheme == .dark ? .white.opacity(0.08) : .black.opacity(0.06), lineWidth: 0.5)
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .frame(height: 18)
        .contentShape(Rectangle())
        .onHover { hovering in
            updateParagraphHeaderHover(hovering)
        }
        .simultaneousGesture(paragraphHeaderDragGesture)
        .padding(.horizontal, 14)
        .padding(.top, 10)
        .padding(.bottom, 6)
    }

    private var paragraphOriginalSectionTitle: String {
        paragraphLanguageSectionTitle(for: "en")
    }

    private var paragraphTranslationSectionTitle: String {
        paragraphLanguageSectionTitle(for: model.settings.targetLanguage)
    }

    private func paragraphLanguageSectionTitle(for languageIdentifier: String) -> String {
        paragraphLanguageDisplayName(for: languageIdentifier)
    }

    private func paragraphLanguageDisplayName(for identifier: String) -> String {
        let normalizedIdentifier = paragraphNormalizedLanguageIdentifier(for: identifier)
        let locale = paragraphDisplayLocale

        if let localizedName = locale.localizedString(forIdentifier: normalizedIdentifier) {
            return localizedName
        }

        if let languageCode = Locale(identifier: normalizedIdentifier).language.languageCode?.identifier,
           let localizedName = locale.localizedString(forLanguageCode: languageCode) {
            return localizedName
        }

        return normalizedIdentifier
    }

    private var paragraphDisplayLocale: Locale {
        if let localeIdentifier = model.settings.appLanguage.localeIdentifier {
            return Locale(identifier: localeIdentifier)
        }

        if let preferredLanguage = Locale.preferredLanguages.first {
            return Locale(identifier: preferredLanguage)
        }

        return .current
    }

    private func paragraphNormalizedLanguageIdentifier(for identifier: String) -> String {
        if identifier.hasPrefix("zh-Hans") {
            return "zh-Hans"
        }

        if identifier.hasPrefix("zh-Hant") {
            return "zh-Hant"
        }

        return identifier
    }

    private var paragraphHeaderDragGesture: some Gesture {
        DragGesture(minimumDistance: 1, coordinateSpace: .global)
            .onChanged { value in
                guard isParagraphOverlayMode else { return }

                if !isParagraphHeaderDragging {
                    isParagraphHeaderDragging = true
                    refreshParagraphHeaderCursor()
                    model.beginParagraphOverlayDrag()
                }

                model.updateParagraphOverlayDrag(translation: value.translation)
            }
            .onEnded { _ in
                guard isParagraphHeaderDragging else { return }
                model.endParagraphOverlayDrag()
                isParagraphHeaderDragging = false
                refreshParagraphHeaderCursor()
            }
    }

    private func updateParagraphHeaderHover(_ hovering: Bool) {
        guard isParagraphOverlayMode else {
            resetParagraphHeaderInteractionState()
            return
        }

        isParagraphHeaderHovered = hovering
        refreshParagraphHeaderCursor()
    }

    private func refreshParagraphHeaderCursor() {
        guard isParagraphOverlayMode else {
            NSCursor.arrow.set()
            return
        }

        if isParagraphHeaderDragging {
            NSCursor.closedHand.set()
        } else if isParagraphHeaderHovered {
            NSCursor.openHand.set()
        } else {
            NSCursor.arrow.set()
        }
    }

    private func resetParagraphHeaderInteractionState() {
        if isParagraphHeaderDragging {
            model.endParagraphOverlayDrag()
        }

        isParagraphHeaderDragging = false
        isParagraphHeaderHovered = false
        NSCursor.arrow.set()
    }

    @ViewBuilder
    private func dictionarySectionsView(sections: [OverlayDictionarySection]) -> some View {
        ForEach(Array(sections.enumerated()), id: \.element.id) { index, section in
            VStack(alignment: .leading, spacing: 0) {
                Divider()
                    .padding(.horizontal, 18)
                    .opacity(0.6)

                // Dictionary source header
                dictionarySourceSectionHeader(sourceType: section.sourceType, isFirst: index == 0)

                dictionarySectionBody(section)
            }
        }
    }

    @ViewBuilder
    private func dictionarySectionBody(_ section: OverlayDictionarySection) -> some View {
        switch section.state {
        case .loading:
            dictionaryStatusRow(
                text: L("Translating"),
                showsSpinner: true
            )
        case .ready(let entry):
            definitionsSection(definitions: entry.definitions, showDividers: false)
        case .empty:
            dictionaryStatusRow(text: L("No result"))
        case .failed(let message):
            dictionaryStatusRow(text: message.isEmpty ? L("Unavailable") : message)
        }
    }

    @ViewBuilder
    private func dictionarySourceSectionHeader(sourceType: DictionarySource.SourceType, isFirst: Bool) -> some View {
        let config = dictionarySourceConfig(for: sourceType)

        HStack(spacing: 6) {
            Image(systemName: config.icon)
                .font(.system(size: 11, weight: .semibold))
            Text(config.title)
                .font(.system(size: 11, weight: .semibold))
        }
        .foregroundStyle(config.color)
        .padding(.horizontal, 18)
        .padding(.top, isFirst ? 10 : 12)
        .padding(.bottom, 6)
    }

    private func dictionarySourceConfig(for sourceType: DictionarySource.SourceType) -> (title: String, icon: String, color: Color) {
        switch sourceType {
        case .ecdict:
            return (
                L("Advanced Dictionary"),
                "book.closed",
                .secondary
            )
        case .system:
            return (
                L("System Dictionary"),
                "book.closed",
                .secondary
            )
        case .google:
            return (
                L("Google Translate"),
                "globe",
                Color(red: 0.10, green: 0.45, blue: 0.95)
            )
        case .bing:
            return (
                L("Bing Dictionary"),
                "text.book.closed",
                Color(red: 0.00, green: 0.65, blue: 0.78)
            )
        case .youdao:
            return (
                L("Youdao Dictionary"),
                "book.closed.fill",
                Color(red: 0.90, green: 0.30, blue: 0.22)
            )
        case .deepl:
            return (
                L("DeepL Translate"),
                "diamond.fill",
                Color(red: 0.05, green: 0.24, blue: 0.63)
            )
        case .freeDict:
            return (
                L("Free Dictionary"),
                "globe",
                Color(red: 0.95, green: 0.60, blue: 0.15)
            )
        }
    }

    @ViewBuilder
    private func dictionaryStatusRow(text: String, showsSpinner: Bool = false) -> some View {
        HStack(spacing: 8) {
            if showsSpinner {
                ProgressView()
                    .controlSize(.small)
                    .scaleEffect(0.8)
            }

            Text(text)
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundStyle(.secondary)

            Spacer()
        }
        .padding(.horizontal, 18)
        .frame(minHeight: compactSectionMinHeight, alignment: .leading)
        .padding(.bottom, 12)
    }

    @ViewBuilder
    private func headerSection(content: OverlayContent) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            // Word title with phonetic, copy button and close button
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(content.word)
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .foregroundStyle(.primary)
                    .tracking(0.3)

                // Phonetic tag placed right after the word
                if let phonetic = content.phonetic, !phonetic.isEmpty {
                    Text(phonetic)
                        .font(.system(size: 11, weight: .regular, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .strokeBorder(.secondary.opacity(0.25), lineWidth: 0.5)
                                .background(
                                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                                        .fill(.secondary.opacity(0.06))
                                )
                        )
                }

                // 非持续模式下显示复制按钮
                if !model.settings.continuousTranslation {
                    CopyButton(text: content.word)
                }

                Spacer()

                // 非持续模式下显示关闭按钮
                if !model.settings.continuousTranslation {
                    Button {
                        model.dismissOverlay()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .frame(width: 20, height: 20)
                            .background(
                                Circle()
                                    .fill(.secondary.opacity(0.1))
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(.horizontal, 18)
        .padding(.top, 16)
        .padding(.bottom, 12)
    }

    @ViewBuilder
    private func primaryTranslationSection(content: OverlayContent) -> some View {
        let targetIsEnglish = model.settings.targetLanguage.hasPrefix("en")
        let shouldHideReadyTranslation = targetIsEnglish && !content.definitions.isEmpty

        VStack(alignment: .leading, spacing: 0) {
            switch content.primaryTranslationState {
            case .loading:
                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                        .scaleEffect(0.85)
                    Text(L("Translating"))
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                    LoadingDotsView()
                    Spacer()
                }
                .padding(.horizontal, 18)
                .padding(.bottom, 16)

            case .ready(let translation, _):
                if !shouldHideReadyTranslation {
                    HStack(spacing: 8) {
                        if !content.definitions.isEmpty {
                            Text(translation)
                                .font(.system(size: 17, weight: .medium, design: .rounded))
                                .foregroundStyle(
                                    LinearGradient(
                                        colors: colorScheme == .dark
                                            ? [
                                                Color(red: 0.2, green: 0.6, blue: 1.0),
                                                Color(red: 0.5, green: 0.5, blue: 0.95),
                                            ]
                                            : [
                                                Color(red: 0.1, green: 0.4, blue: 0.85),
                                                Color(red: 0.35, green: 0.3, blue: 0.8),
                                            ],
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                )
                                .tracking(0.3)

                            if !model.settings.continuousTranslation {
                                CopyButton(text: translation)
                            }
                        } else {
                            Text(translation)
                                .font(.system(size: 24, weight: .bold, design: .rounded))
                                .foregroundStyle(.primary)
                                .tracking(0.2)

                            if !model.settings.continuousTranslation {
                                CopyButton(text: translation)
                            }
                        }

                        Spacer()
                    }
                    .padding(.horizontal, 18)
                    .padding(.bottom, content.definitions.isEmpty ? 16 : 8)
                }

            case .empty:
                EmptyView()

            case .failed(let message):
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.circle")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.secondary)
                    Text(message)
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .padding(.horizontal, 18)
                .padding(.bottom, 16)
            }
        }
        .frame(maxWidth: .infinity, minHeight: shouldHideReadyTranslation ? 8 : compactSectionMinHeight, alignment: .topLeading)
    }

    @ViewBuilder
    private func definitionsSection(definitions: [DictionaryEntry.Definition], showDividers: Bool = true) -> some View {
        let grouped = groupedTranslations(from: definitions)
        if grouped.isEmpty {
            EmptyView()
        } else {
            VStack(alignment: .leading, spacing: 0) {
                if showDividers {
                    Divider()
                        .padding(.horizontal, 18)
                        .opacity(0.6)
                }

                VStack(alignment: .leading, spacing: 14) {
                    ForEach(Array(grouped.enumerated()), id: \.offset) { _, group in
                        definitionGroupRow(partOfSpeech: group.0, field: group.1, translations: group.2)
                    }
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 14)
            }
        }
    }

    @ViewBuilder
    private func definitionGroupRow(partOfSpeech: String, field: String?, translations: [String]) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            HStack(spacing: 4) {
                if !partOfSpeech.isEmpty {
                    Text(displayedPartOfSpeech(for: partOfSpeech))
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(posColor(for: partOfSpeech))
                                .shadow(color: posColor(for: partOfSpeech).opacity(0.3), radius: 2, x: 0, y: 1)
                        )
                }

                if let field, !field.isEmpty {
                    Text(displayedField(for: field))
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(fieldColor(for: field))
                                .shadow(color: fieldColor(for: field).opacity(0.3), radius: 2, x: 0, y: 1)
                        )
                }
            }

            Text(translations.joined(separator: "；"))
                .font(.system(size: 14, weight: .regular, design: .rounded))
                .foregroundStyle(.primary)
                .lineLimit(3)
        }
    }

    private func displayedPartOfSpeech(for pos: String) -> String {
        let lowercased = pos.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        switch lowercased {
        case "n", "noun":
            return "n."
        case "v", "verb":
            return "v."
        case "vt", "transitive verb":
            return "vt."
        case "vi", "intransitive verb":
            return "vi."
        case "adj", "adjective", "a":
            return "adj."
        case "adv", "adverb":
            return "adv."
        case "prep", "preposition":
            return "prep."
        case "conj", "conjunction":
            return "conj."
        case "pron", "pronoun":
            return "pron."
        case "interj", "interjection":
            return "interj."
        default:
            return pos
        }
    }

    private func groupedTranslations(from definitions: [DictionaryEntry.Definition]) -> [(String, String?, [String])] {
        var order: [(String, String?)] = []
        var grouped: [String: [String]] = [:]

        for definition in definitions {
            guard let translation = definition.translation?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !translation.isEmpty else { continue }
            let key = "\(definition.partOfSpeech)|\(definition.field ?? "")"
            if grouped[key] == nil {
                order.append((definition.partOfSpeech, definition.field))
                grouped[key] = []
            }
            if grouped[key]?.contains(translation) == false {
                grouped[key]?.append(translation)
            }
        }

        return order.compactMap { pos, field in
            let key = "\(pos)|\(field ?? "")"
            guard let translations = grouped[key], !translations.isEmpty else { return nil }
            return (pos, field, translations)
        }
    }

    private func posColor(for pos: String) -> Color {
        switch pos.lowercased() {
        case "n.", "n", "noun":
            return Color(red: 0.2, green: 0.6, blue: 1.0)  // Modern blue
        case "v.", "v", "verb":
            return Color(red: 0.2, green: 0.78, blue: 0.35)  // Modern green
        case "vt.", "vt", "transitive verb":
            return Color(red: 0.2, green: 0.78, blue: 0.35)  // Modern green
        case "vi.", "vi", "intransitive verb":
            return Color(red: 0.2, green: 0.78, blue: 0.35)  // Modern green
        case "adj.", "adj", "adjective", "a", "a.":
            return Color(red: 1.0, green: 0.58, blue: 0.0)  // Vibrant orange
        case "adv.", "adv", "adverb":
            return Color(red: 0.69, green: 0.32, blue: 0.87)  // Modern purple
        case "prep.", "prep", "preposition":
            return Color(red: 1.0, green: 0.27, blue: 0.58)  // Modern pink
        case "conj.", "conj", "conjunction":
            return Color(red: 0.2, green: 0.78, blue: 0.87)  // Modern cyan
        case "pron.", "pron", "pronoun":
            return Color(red: 0.2, green: 0.69, blue: 0.64)  // Modern teal
        case "interj.", "interj", "interjection":
            return Color(red: 1.0, green: 0.27, blue: 0.27)  // Modern red
        default:
            return Color(red: 0.56, green: 0.56, blue: 0.58)  // Modern gray
        }
    }

    private func displayedField(for field: String) -> String {
        // Remove brackets and return clean text, e.g., "[医]" -> "医"
        let cleaned = field.trimmingCharacters(in: CharacterSet(charactersIn: "[]"))
        return cleaned
    }

    private func fieldColor(for field: String) -> Color {
        // Extract the field code without brackets
        let code = field.trimmingCharacters(in: CharacterSet(charactersIn: "[]"))
        switch code {
        case "医":
            return Color(red: 0.9, green: 0.3, blue: 0.3)     // Red for medical
        case "法":
            return Color(red: 0.5, green: 0.3, blue: 0.8)     // Purple for legal
        case "经":
            return Color(red: 0.2, green: 0.7, blue: 0.4)     // Green for economic
        case "计":
            return Color(red: 0.1, green: 0.5, blue: 0.9)     // Blue for computer
        case "化":
            return Color(red: 0.9, green: 0.6, blue: 0.1)     // Orange for chemistry
        case "物":
            return Color(red: 0.3, green: 0.6, blue: 0.8)     // Teal for physics
        case "生":
            return Color(red: 0.4, green: 0.7, blue: 0.3)     // Green for biology
        case "数":
            return Color(red: 0.6, green: 0.4, blue: 0.8)     // Violet for mathematics
        default:
            return Color(red: 0.56, green: 0.56, blue: 0.58)  // Gray for others
        }
    }

    // MARK: - Error View

    @ViewBuilder
    private func errorView(message: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(Color(red: 1.0, green: 0.58, blue: 0.0))
            Text(message)
                .font(.system(size: 14, weight: .medium, design: .rounded))
                .foregroundStyle(.primary)
        }
        .padding(.vertical, 16)
        .padding(.horizontal, 18)
    }

    // MARK: - No Word View

    private var noWordView: some View {
        HStack(spacing: 12) {
            Image(systemName: "text.magnifyingglass")
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(.secondary)
            Text("No word detected")
                .font(.system(size: 14, weight: .medium, design: .rounded))
                .foregroundStyle(.primary.opacity(0.8))
        }
        .padding(.vertical, 16)
        .padding(.horizontal, 18)
    }
}

// MARK: - Loading Dots Animation

struct LoadingDotsView: View {
    @State private var animating = false

    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<3, id: \.self) { index in
                Circle()
                    .fill(Color.secondary)
                    .frame(width: 4.5, height: 4.5)
                    .scaleEffect(animating ? 1.0 : 0.5)
                    .opacity(animating ? 0.8 : 0.3)
                    .animation(
                        .easeInOut(duration: 0.6)
                            .repeatForever(autoreverses: true)
                            .delay(Double(index) * 0.2),
                        value: animating
                    )
            }
        }
        .onAppear {
            animating = true
        }
    }
}

// MARK: - Copy Button

struct CopyButton: View {
    let text: String
    @State private var copied = false

    var body: some View {
        Button {
            copyToClipboard(text)
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                copied = true
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                withAnimation(.easeInOut(duration: 0.25)) {
                    copied = false
                }
            }
        } label: {
            Image(systemName: copied ? "checkmark" : "doc.on.doc")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(copied ? Color(red: 0.2, green: 0.78, blue: 0.35) : .secondary)
                .frame(width: 18, height: 18)
                .background(
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .fill(copied ? Color(red: 0.2, green: 0.78, blue: 0.35).opacity(0.12) : Color.secondary.opacity(0.08))
                )
                .scaleEffect(copied ? 1.1 : 1.0)
        }
        .buttonStyle(.plain)
        .help(L("Copy to clipboard"))
    }

    private func copyToClipboard(_ text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }
}

private struct SelectableTextView: NSViewRepresentable {
    let text: String
    let font: NSFont
    let textColor: NSColor
    let preferredLineHeight: CGFloat

    func makeNSView(context: Context) -> NSTextView {
        let textView = NSTextView(frame: .zero)
        textView.isEditable = false
        textView.isSelectable = true
        textView.isRichText = false
        textView.drawsBackground = false
        textView.backgroundColor = .clear
        textView.focusRingType = .none
        textView.textContainerInset = .zero
        textView.isHorizontallyResizable = false
        textView.isVerticallyResizable = true
        textView.autoresizingMask = [.width]
        textView.textContainer?.lineFragmentPadding = 0
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.lineBreakMode = .byWordWrapping
        return textView
    }

    func updateNSView(_ textView: NSTextView, context: Context) {
        textView.textStorage?.setAttributedString(makeAttributedString())

        let currentWidth = max(textView.bounds.width, 1)
        textView.textContainer?.containerSize = CGSize(
            width: currentWidth,
            height: .greatestFiniteMagnitude
        )
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: NSTextView, context: Context) -> CGSize? {
        guard let width = proposal.width, width > 0 else {
            return CGSize(width: 0, height: font.pointSize)
        }

        let rect = makeAttributedString().boundingRect(
            with: CGSize(width: width, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading]
        )

        return CGSize(
            width: width,
            height: max(ceil(rect.height), ceil(font.ascender - font.descender))
        )
    }

    private func makeAttributedString() -> NSAttributedString {
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineBreakMode = .byWordWrapping
        paragraphStyle.minimumLineHeight = preferredLineHeight
        paragraphStyle.maximumLineHeight = preferredLineHeight

        return NSAttributedString(
            string: text,
            attributes: [
                .font: font,
                .foregroundColor: textColor,
                .paragraphStyle: paragraphStyle,
            ]
        )
    }
}

private struct ParagraphOverlaySectionCard<Content: View>: View {
    @Environment(\.colorScheme) private var colorScheme

    let title: String?
    let copyText: String?
    let emphasis: Bool
    let content: Content

    @State private var isHovered = false

    init(
        title: String?,
        copyText: String?,
        emphasis: Bool,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.copyText = copyText
        self.emphasis = emphasis
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                if let title, !title.isEmpty {
                    Text(title)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 8)

                if let copyText, !copyText.isEmpty {
                    ParagraphSectionCopyButton(
                        text: copyText,
                        isVisible: isHovered
                    )
                }
            }

            content
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background {
            RoundedRectangle(cornerRadius: 13, style: .continuous)
                .fill(fillColor)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 13, style: .continuous)
                .stroke(strokeColor, lineWidth: 1)
        }
        .shadow(color: shadowColor, radius: 2, x: 0, y: 1)
        .contentShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
        .onHover { hovering in
            isHovered = hovering
        }
    }

    private var fillColor: Color {
        if colorScheme == .dark {
            return emphasis ? .white.opacity(0.055) : .white.opacity(0.036)
        }

        return emphasis ? .black.opacity(0.025) : .black.opacity(0.016)
    }

    private var strokeColor: Color {
        if colorScheme == .dark {
            return emphasis ? .white.opacity(0.16) : .white.opacity(0.10)
        }

        return emphasis ? .black.opacity(0.10) : .black.opacity(0.06)
    }

    private var shadowColor: Color {
        if colorScheme == .dark {
            return .black.opacity(emphasis ? 0.16 : 0.10)
        }

        return .black.opacity(emphasis ? 0.05 : 0.03)
    }
}

private struct ParagraphSectionCopyButton: View {
    let text: String
    let isVisible: Bool
    @State private var copied = false

    var body: some View {
        Button {
            copyToClipboard(text)
            withAnimation(.spring(response: 0.28, dampingFraction: 0.8)) {
                copied = true
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) {
                withAnimation(.easeInOut(duration: 0.2)) {
                    copied = false
                }
            }
        } label: {
            Image(systemName: copied ? "checkmark" : "doc.on.doc")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(copied ? Color(red: 0.2, green: 0.7, blue: 0.35) : .secondary)
                .frame(width: 16, height: 16)
                .padding(4)
                .background(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(copied ? Color(red: 0.2, green: 0.7, blue: 0.35).opacity(0.12) : Color.secondary.opacity(0.08))
                )
                .opacity(isVisible || copied ? 1 : 0)
        }
        .buttonStyle(.plain)
        .allowsHitTesting(isVisible || copied)
        .animation(.easeInOut(duration: 0.16), value: isVisible)
        .help(copied ? L("Copied") : L("Copy to clipboard"))
    }

    private func copyToClipboard(_ text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }
}

// MARK: - Preview

#Preview {
    OverlayView()
        .environmentObject(AppModel(
            settings: SettingsStore(),
            permissions: PermissionManager()
        ))
        .frame(width: 500, height: 300)
        .background(.gray.opacity(0.3))
}

import AppKit
import SwiftUI
import SwiftData

struct OverlayView: View {
    let paragraphOverlayMaxHeightOverride: CGFloat?
    let paragraphOverlayScrollingEnabledOverride: Bool?

    @EnvironmentObject var model: AppModel
    @Environment(\.colorScheme) private var colorScheme
    @StateObject private var localizationManager = LocalizationManager.shared
    @State private var isParagraphHeaderHovered = false
    @State private var isParagraphHeaderDragging = false
    private let wordOverlayWidth: CGFloat = 380
    private let paragraphOverlayWidth: CGFloat = 520
    private let paragraphHeaderHeight: CGFloat = 34
    private let compactSectionMinHeight: CGFloat = 28
    private let paragraphTextHorizontalPadding: CGFloat = 18

    init(
        paragraphOverlayMaxHeightOverride: CGFloat? = nil,
        paragraphOverlayScrollingEnabledOverride: Bool? = nil
    ) {
        self.paragraphOverlayMaxHeightOverride = paragraphOverlayMaxHeightOverride
        self.paragraphOverlayScrollingEnabledOverride = paragraphOverlayScrollingEnabledOverride
    }

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

    private var showsParagraphOverlayPinButton: Bool {
        isParagraphOverlayMode && !model.isParagraphOverlayPinned
    }

    private var canDragPinnedParagraphOverlay: Bool {
        isParagraphOverlayMode && model.isParagraphOverlayPinned
    }

    private var isVisible: Bool {
        if case .idle = model.overlayState { return false }
        return true
    }

    private var paragraphBodyMaxHeight: CGFloat? {
        guard isParagraphOverlayMode,
              let overlayMaxHeight = paragraphOverlayMaxHeightOverride else {
            return nil
        }
        return max(1, overlayMaxHeight - paragraphHeaderHeight)
    }

    private var paragraphBodyUsesScrollView: Bool {
        paragraphOverlayScrollingEnabledOverride ?? false
    }

    private var showsExtendedDictionaryDetails: Bool {
        !model.settings.targetLanguage.hasPrefix("zh")
    }

    var body: some View {
        Group {
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
                Text(L("Translating"))
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
                VStack(alignment: .leading, spacing: 10) {
                    HStack(alignment: .center, spacing: 10) {
                        ProgressView()
                            .controlSize(.small)

                        Text(L("Detecting text under cursor"))
                            .font(.system(size: 15, weight: .medium, design: .rounded))
                            .foregroundStyle(.primary)
                    }

                    Text(L("正在执行全屏 OCR 与段落定位"))
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, 18)
                .padding(.top, 2)
                .padding(.vertical, 14)
            }
        }
    }

    @ViewBuilder
    private func paragraphResultView(content: ParagraphOverlayContent) -> some View {
        let optimalFontSize: CGFloat = if content.useFixedFontSize {
            content.bodyFontSize
        } else {
            ParagraphFontSizing.optimalFontSize(
                preferredFontSize: content.bodyFontSize,
                originalText: content.originalText,
                containerWidth: overlayWidth,
                horizontalPadding: paragraphTextHorizontalPadding
            )
        }

        VStack(alignment: .leading, spacing: 0) {
            if let originalText = content.originalText,
               !originalText.isEmpty {
                paragraphOriginalTopBar(copyText: originalText)
            } else {
                paragraphTopBar()
            }

            paragraphBodyContainer {
                if let originalText = content.originalText,
                   !originalText.isEmpty {
                    VStack(alignment: .leading, spacing: 0) {
                        paragraphTextContent(
                            text: originalText,
                            font: .systemFont(ofSize: optimalFontSize, weight: .medium),
                            textColor: .labelColor,
                            preferredLineHeight: optimalFontSize * 1.5
                        )
                        .padding(.top, 4)
                        .overlay {
                            paragraphOriginalTextDragOverlay
                        }
                    }
                    .padding(.horizontal, paragraphTextHorizontalPadding)
                    .padding(.bottom, 14)

                    // Divider after original text
                    Divider()
                        .padding(.horizontal, paragraphTextHorizontalPadding)
                        .opacity(0.6)

                    // Native Translation Section (System Translation)
                    switch content.translationState {
                    case .loading:
                        VStack(alignment: .leading, spacing: 0) {
                            HStack(spacing: 8) {
                                ProgressView()
                                    .controlSize(.small)
                                Text(L("Translating"))
                                    .font(.system(size: 13, weight: .medium, design: .rounded))
                                    .foregroundStyle(.secondary)
                                LoadingDotsView()
                            }
                            .padding(.horizontal, paragraphTextHorizontalPadding)
                            .padding(.vertical, 14)
                        }

                    case .ready(let translatedText):
                        VStack(alignment: .leading, spacing: 8) {
                            HStack(alignment: .center, spacing: 8) {
                                Text(paragraphTranslationSectionTitle)
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundStyle(.secondary)

                                CopyButton(text: translatedText)
                            }

                            paragraphTextContent(
                                text: translatedText,
                                font: .systemFont(ofSize: optimalFontSize, weight: .semibold),
                                textColor: .labelColor,
                                preferredLineHeight: optimalFontSize * 1.5
                            )
                        }
                        .padding(.horizontal, paragraphTextHorizontalPadding)
                        .padding(.vertical, 14)

                    case .failed(let message):
                        VStack(alignment: .leading, spacing: 0) {
                            paragraphErrorContent(message: L(message))
                                .padding(.horizontal, paragraphTextHorizontalPadding)
                                .padding(.vertical, 14)
                        }
                    }

                    // Third-party Service Results Section
                    if !content.serviceResults.isEmpty {
                        ForEach(content.serviceResults) { result in
                            Divider()
                                .padding(.horizontal, paragraphTextHorizontalPadding)
                                .opacity(0.6)

                            paragraphServiceResultCard(result: result, fontSize: optimalFontSize)
                        }
                    }
                } else if case .failed(let message) = content.translationState {
                    // Auto-dismiss error view for paragraph translation errors
                    AutoDismissErrorView(message: L(message), onDismiss: { model.dismissOverlay() })
                        .padding(.horizontal, paragraphTextHorizontalPadding)
                        .padding(.vertical, 18)
                }
            }
        }
    }

    @ViewBuilder
    private func paragraphServiceResultCard(result: ServiceTranslationResult, fontSize: CGFloat) -> some View {
        let title = "\(result.sourceType.displayName)"

        switch result.state {
        case .loading:
            VStack(alignment: .leading, spacing: 8) {
                Text(title)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)

                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                    Text(L("Translating"))
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                    LoadingDotsView()
                }
            }
            .padding(.horizontal, paragraphTextHorizontalPadding)
            .padding(.vertical, 14)

        case .ready(let translatedText):
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .center, spacing: 8) {
                    Text(title)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)

                    CopyButton(text: translatedText)
                }

                paragraphTextContent(
                    text: translatedText,
                    font: .systemFont(ofSize: fontSize, weight: .medium),
                    textColor: .labelColor,
                    preferredLineHeight: fontSize * 1.5
                )
            }
            .padding(.horizontal, paragraphTextHorizontalPadding)
            .padding(.vertical, 14)

        case .failed(let message):
            VStack(alignment: .leading, spacing: 8) {
                Text(title)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)

                paragraphErrorContent(message: message)
            }
            .padding(.horizontal, paragraphTextHorizontalPadding)
            .padding(.vertical, 14)
        }
    }

    @ViewBuilder
    private func paragraphBodyContainer<Content: View>(
        @ViewBuilder content: () -> Content
    ) -> some View {
        Group {
            if paragraphBodyUsesScrollView {
                ScrollView {
                    paragraphBodyContent(content: content)
                }
                .frame(maxHeight: paragraphBodyMaxHeight)
            } else {
                paragraphBodyContent(content: content)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    @ViewBuilder
    private func paragraphBodyContent<Content: View>(
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            content()
        }
        .padding(.bottom, 16)
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
    private var paragraphOriginalTextDragOverlay: some View {
        if canDragPinnedParagraphOverlay {
            paragraphPinnedDragHandle
        }
    }

    @ViewBuilder
    private func paragraphTopBar() -> some View {
        HStack(spacing: 0) {
            paragraphHeaderDragArea()

            paragraphOverlayControlButton()
        }
        .frame(height: 18)
        .padding(.horizontal, 14)
        .padding(.top, 10)
        .padding(.bottom, 6)
    }

    @ViewBuilder
    private func paragraphOriginalTopBar(copyText: String) -> some View {
        HStack(alignment: .center, spacing: 8) {
            paragraphHeaderDragArea(
                title: paragraphOriginalSectionTitle,
                fillsWidth: false
            )

            CopyButton(text: copyText)

            paragraphHeaderDragArea()

            paragraphOverlayControlButton()
        }
        .frame(height: 18)
        .padding(.leading, paragraphTextHorizontalPadding)
        .padding(.trailing, 14)
        .padding(.top, 10)
        .padding(.bottom, 6)
    }

    @ViewBuilder
    private func paragraphHeaderDragArea(
        title: String? = nil,
        fillsWidth: Bool = true
    ) -> some View {
        ZStack(alignment: .leading) {
            if canDragPinnedParagraphOverlay {
                paragraphPinnedDragHandle
            } else {
                Color.clear
            }

            if let title, !title.isEmpty {
                Text(title)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .allowsHitTesting(false)
            }
        }
        .frame(
            maxWidth: fillsWidth ? .infinity : nil,
            maxHeight: .infinity,
            alignment: .leading
        )
        .fixedSize(horizontal: !fillsWidth, vertical: false)
        .allowsHitTesting(canDragPinnedParagraphOverlay)
    }

    @ViewBuilder
    private var paragraphPinnedDragHandle: some View {
        if canDragPinnedParagraphOverlay {
            ParagraphOverlayDragHandle(
                isEnabled: canDragPinnedParagraphOverlay,
                onDragBegin: { model.beginParagraphOverlayDrag() },
                onDragEnd: { model.endParagraphOverlayDrag() }
            )
        }
    }

    @ViewBuilder
    private func paragraphOverlayControlButton() -> some View {
        if showsParagraphOverlayControls {
            if showsParagraphOverlayPinButton {
                paragraphOverlayControlButton(
                    systemImage: "pin",
                    helpText: L("Pin"),
                    action: { model.toggleParagraphOverlayPin() }
                )
            } else {
                paragraphOverlayControlButton(
                    systemImage: "xmark",
                    helpText: L("Close"),
                    action: { model.dismissOverlay() }
                )
            }
        }
    }

    private func paragraphOverlayControlButton(
        systemImage: String,
        helpText: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
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
        .help(helpText)
    }

    private var paragraphOriginalSectionTitle: String {
        L("Original")
    }

    private var paragraphTranslationSectionTitle: String {
        SentenceTranslationSource.SourceType.native.displayName
    }

    private var paragraphHeaderDragGesture: some Gesture {
        DragGesture(minimumDistance: 1, coordinateSpace: .global)
            .onChanged { value in
                guard canDragPinnedParagraphOverlay else { return }

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
        guard canDragPinnedParagraphOverlay else {
            resetParagraphHeaderInteractionState()
            return
        }

        isParagraphHeaderHovered = hovering
        refreshParagraphHeaderCursor()
    }

    private func refreshParagraphHeaderCursor() {
        guard canDragPinnedParagraphOverlay else {
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
            definitionsSection(entry: entry, showDividers: false)
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
        case .youdao:
            return (
                L("Youdao Dictionary"),
                "text.book.closed",
                .orange
            )
        case .google:
            return (
                L("Google Dictionary"),
                "globe",
                .blue
            )
        case .freeDictionaryAPI:
            return (
                L("Free Dictionary API"),
                "books.vertical",
                .green
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
        if #available(macOS 15.0, *) {
            let targetIsEnglish = model.settings.targetLanguage.hasPrefix("en")
            let shouldHideReadyTranslation = targetIsEnglish && !content.definitions.isEmpty
            let usesCompactStyle = content.usesCompactPrimaryTranslationStyle

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
                            if usesCompactStyle {
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
                        .padding(.bottom, usesCompactStyle ? 8 : 16)
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
    }

    @ViewBuilder
    private func definitionsSection(entry: DictionaryEntry, showDividers: Bool = true) -> some View {
        let grouped = groupedDefinitionContent(
            from: entry.definitions,
            includeSupplementaryDetails: showsExtendedDictionaryDetails
        )
        if grouped.isEmpty {
            EmptyView()
        } else {
            VStack(alignment: .leading, spacing: 0) {
                if showDividers {
                    Divider()
                        .padding(.horizontal, 18)
                        .opacity(0.6)
                }

                VStack(alignment: .leading, spacing: 16) {
                    ForEach(Array(grouped.enumerated()), id: \.offset) { _, group in
                        definitionGroupRow(group: group)
                    }

                    if showsExtendedDictionaryDetails && entry.hasSynonyms {
                        synonymsRow(entry.synonyms)
                    }
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 14)
            }
        }
    }

    @ViewBuilder
    private func definitionGroupRow(group: DefinitionDisplayGroup) -> some View {
        HStack(alignment: .top, spacing: 10) {
            HStack(spacing: 4) {
                if !group.partOfSpeech.isEmpty {
                    Text(displayedPartOfSpeech(for: group.partOfSpeech))
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(posColor(for: group.partOfSpeech))
                                .shadow(color: posColor(for: group.partOfSpeech).opacity(0.3), radius: 2, x: 0, y: 1)
                        )
                }

                if let field = group.field, !field.isEmpty {
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
            .padding(.top, 1)

            VStack(alignment: .leading, spacing: 6) {
                if !group.translations.isEmpty {
                    Text(group.translations.joined(separator: "；"))
                        .font(.system(size: 14, weight: .regular, design: .rounded))
                        .foregroundStyle(.primary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if !group.meanings.isEmpty {
                    Text(group.meanings.joined(separator: "\n"))
                        .font(.system(size: 12, weight: .regular, design: .rounded))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if !group.examples.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(Array(group.examples.prefix(2)), id: \.self) { example in
                            HStack(alignment: .top, spacing: 6) {
                                Text("•")
                                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                                    .foregroundStyle(.secondary)

                                Text(example)
                                    .font(.system(size: 12, weight: .regular, design: .rounded))
                                    .foregroundStyle(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                    .padding(.top, 2)
                }
            }
        }
    }

    @ViewBuilder
    private func synonymsRow(_ synonyms: [String]) -> some View {
        let displayedSynonyms = Array(synonyms.prefix(8))
        if !displayedSynonyms.isEmpty {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "link")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .padding(.top, 2)

                Text(displayedSynonyms.joined(separator: " · "))
                    .font(.system(size: 12, weight: .regular, design: .rounded))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.top, 2)
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

    private func groupedDefinitionContent(
        from definitions: [DictionaryEntry.Definition],
        includeSupplementaryDetails: Bool
    ) -> [DefinitionDisplayGroup] {
        var order: [(String, String?)] = []
        var grouped: [String: DefinitionAccumulator] = [:]

        for definition in definitions {
            let key = "\(definition.partOfSpeech)|\(definition.field ?? "")"
            if grouped[key] == nil {
                order.append((definition.partOfSpeech, definition.field))
                grouped[key] = DefinitionAccumulator()
            }

            let translation = normalizedDictionaryText(definition.translation)

            if let translation {
                grouped[key]?.translations.appendIfMissing(translation)
            }

            if includeSupplementaryDetails {
                let meaning = normalizedDictionaryText(definition.meaning)
                let examples = definition.examples.compactMap(normalizedDictionaryText)

                if let meaning,
                   meaning.caseInsensitiveCompare(translation ?? "") != .orderedSame {
                    grouped[key]?.meanings.appendIfMissing(meaning)
                }
                for example in examples {
                    grouped[key]?.examples.appendIfMissing(example)
                }
            }
        }

        return order.compactMap { pos, field in
            let key = "\(pos)|\(field ?? "")"
            guard let content = grouped[key],
                  !content.translations.isEmpty || !content.meanings.isEmpty || !content.examples.isEmpty else {
                return nil
            }
            return DefinitionDisplayGroup(
                partOfSpeech: pos,
                field: field,
                translations: content.translations,
                meanings: content.meanings,
                examples: content.examples
            )
        }
    }

    private func normalizedDictionaryText(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
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

    private struct DefinitionDisplayGroup {
        let partOfSpeech: String
        let field: String?
        let translations: [String]
        let meanings: [String]
        let examples: [String]
    }

    private struct DefinitionAccumulator {
        var translations: [String] = []
        var meanings: [String] = []
        var examples: [String] = []
    }

    // MARK: - Error View

    @ViewBuilder
    private func errorView(message: String) -> some View {
        AutoDismissErrorView(message: message, onDismiss: { model.dismissOverlay() })
    }

    // MARK: - No Word View

    private var noWordView: some View {
        HStack(spacing: 12) {
            Image(systemName: "text.magnifyingglass")
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(.secondary)
            Text(L("No word detected"))
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

private extension Array where Element == String {
    mutating func appendIfMissing(_ value: String) {
        if contains(value) == false {
            append(value)
        }
    }
}

enum ParagraphFontSizing {
    static let minFontSize: CGFloat = 10
    static let maxFontSize: CGFloat = 22
    static let baseFontSize: CGFloat = 13
    static let preferredUpscaleFactor: CGFloat = 1.15

    static func optimalFontSize(
        preferredFontSize: CGFloat,
        originalText: String?,
        containerWidth: CGFloat,
        horizontalPadding: CGFloat
    ) -> CGFloat {
        let normalizedPreferredFontSize = normalizedPreferredFontSize(preferredFontSize)
        let targetFontSize = min(normalizedPreferredFontSize * preferredUpscaleFactor, maxFontSize)
        guard let fittingFontSize = fittingFontSizeForOriginalText(
            originalText,
            targetFontSize: targetFontSize,
            containerWidth: containerWidth,
            horizontalPadding: horizontalPadding
        ) else {
            return targetFontSize
        }
        return min(max(fittingFontSize, 1), maxFontSize)
    }

    static func normalizedPreferredFontSize(_ preferredFontSize: CGFloat) -> CGFloat {
        guard preferredFontSize.isFinite, preferredFontSize > 0 else {
            return baseFontSize
        }
        return min(max(preferredFontSize, minFontSize), maxFontSize)
    }

    static func fittingFontSizeForOriginalText(
        _ originalText: String?,
        targetFontSize: CGFloat,
        containerWidth: CGFloat,
        horizontalPadding: CGFloat
    ) -> CGFloat? {
        guard let originalText else {
            return nil
        }

        let trimmedText = originalText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedText.isEmpty else {
            return nil
        }

        let availableWidth = max(1, containerWidth - horizontalPadding * 2)
        let targetFont = NSFont.systemFont(ofSize: targetFontSize, weight: .medium)
        let targetLineWidth = maximumLineWidth(for: trimmedText, font: targetFont)
        guard targetLineWidth > 0 else {
            return targetFontSize
        }

        if targetLineWidth <= availableWidth {
            return targetFontSize
        }

        var lowerBound: CGFloat = 1
        var upperBound = targetFontSize
        var bestFitFontSize = lowerBound

        for _ in 0..<12 {
            let candidateFontSize = (lowerBound + upperBound) / 2
            let candidateFont = NSFont.systemFont(ofSize: candidateFontSize, weight: .medium)
            let candidateWidth = maximumLineWidth(for: trimmedText, font: candidateFont)

            if candidateWidth <= availableWidth {
                bestFitFontSize = candidateFontSize
                lowerBound = candidateFontSize
            } else {
                upperBound = candidateFontSize
            }
        }

        return bestFitFontSize
    }

    static func maximumLineWidth(
        for text: String,
        font: NSFont
    ) -> CGFloat {
        ParagraphTextStructure.fromText(text)
            .blocks
            .map(\.displayText)
            .filter { !$0.isEmpty }
            .map {
                ceil(
                    ($0 as NSString).size(
                        withAttributes: [.font: font]
                    ).width
                )
            }
            .max() ?? 0
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

    func makeNSView(context: Context) -> SelectableTextContainerView {
        let textView = SelectableTextContainerView(frame: .zero)
        textView.update(
            text: text,
            font: font,
            textColor: textColor,
            preferredLineHeight: preferredLineHeight
        )
        return textView
    }

    func updateNSView(_ textView: SelectableTextContainerView, context: Context) {
        textView.update(
            text: text,
            font: font,
            textColor: textColor,
            preferredLineHeight: preferredLineHeight
        )
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: SelectableTextContainerView, context: Context) -> CGSize? {
        guard let width = proposal.width, width > 0 else {
            return CGSize(width: 0, height: font.pointSize)
        }

        return nsView.measuredSize(forWidth: width)
    }
}

private struct ParagraphOverlayDragHandle: NSViewRepresentable {
    let isEnabled: Bool
    let onDragBegin: () -> Void
    let onDragEnd: () -> Void

    func makeNSView(context: Context) -> ParagraphOverlayDragHandleView {
        let view = ParagraphOverlayDragHandleView(frame: .zero)
        view.update(
            isEnabled: isEnabled,
            onDragBegin: onDragBegin,
            onDragEnd: onDragEnd
        )
        return view
    }

    func updateNSView(_ nsView: ParagraphOverlayDragHandleView, context: Context) {
        nsView.update(
            isEnabled: isEnabled,
            onDragBegin: onDragBegin,
            onDragEnd: onDragEnd
        )
    }
}

private final class ParagraphOverlayDragHandleView: NSView {
    private var isEnabled = false
    private var onDragBegin: (() -> Void)?
    private var onDragEnd: (() -> Void)?

    override var isOpaque: Bool { false }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard isEnabled else { return nil }
        return bounds.contains(point) ? self : nil
    }

    override func resetCursorRects() {
        super.resetCursorRects()
        guard isEnabled else { return }
        addCursorRect(bounds, cursor: .openHand)
    }

    override func mouseDown(with event: NSEvent) {
        guard isEnabled, let window else {
            super.mouseDown(with: event)
            return
        }

        onDragBegin?()
        NSCursor.closedHand.push()
        defer {
            NSCursor.pop()
            onDragEnd?()
        }

        window.performDrag(with: event)
    }

    func update(
        isEnabled: Bool,
        onDragBegin: @escaping () -> Void,
        onDragEnd: @escaping () -> Void
    ) {
        let enabledChanged = self.isEnabled != isEnabled
        self.isEnabled = isEnabled
        self.onDragBegin = onDragBegin
        self.onDragEnd = onDragEnd

        if enabledChanged {
            discardCursorRects()
        }
    }
}

private final class SelectableTextContainerView: NSView {
    private let textView: NSTextView
    private var cachedMeasurement: (width: CGFloat, height: CGFloat)?

    override var isFlipped: Bool { true }

    override init(frame frameRect: NSRect) {
        textView = NSTextView(frame: .zero)
        super.init(frame: frameRect)
        configureTextView()
        addSubview(textView)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func update(
        text: String,
        font: NSFont,
        textColor: NSColor,
        preferredLineHeight: CGFloat
    ) {
        textView.font = font
        textView.textColor = textColor
        textView.textStorage?.setAttributedString(
            makeAttributedString(
                text: text,
                font: font,
                textColor: textColor,
                preferredLineHeight: preferredLineHeight
            )
        )
        cachedMeasurement = nil
        invalidateIntrinsicContentSize()
        needsLayout = true
    }

    func measuredSize(forWidth width: CGFloat) -> CGSize {
        let resolvedWidth = max(1, ceil(width))
        let height = measuredHeight(forWidth: resolvedWidth)
        return CGSize(width: resolvedWidth, height: height)
    }

    override var intrinsicContentSize: CGSize {
        let width = bounds.width > 0 ? bounds.width : cachedMeasurement?.width ?? 0
        guard width > 0 else {
            return CGSize(width: NSView.noIntrinsicMetric, height: NSView.noIntrinsicMetric)
        }
        return CGSize(width: NSView.noIntrinsicMetric, height: measuredHeight(forWidth: width))
    }

    override func layout() {
        super.layout()

        let width = bounds.width > 0 ? bounds.width : cachedMeasurement?.width ?? 0
        guard width > 0 else { return }

        let height = measuredHeight(forWidth: width)
        let targetFrame = CGRect(x: 0, y: 0, width: width, height: height)
        if textView.frame != targetFrame {
            textView.frame = targetFrame
        }
    }

    private func measuredHeight(forWidth width: CGFloat) -> CGFloat {
        if let cachedMeasurement,
           abs(cachedMeasurement.width - width) <= 0.5 {
            return cachedMeasurement.height
        }

        guard let textContainer = textView.textContainer,
              let layoutManager = textView.layoutManager else {
            return 0
        }

        let resolvedWidth = max(1, ceil(width))
        textContainer.containerSize = CGSize(
            width: resolvedWidth,
            height: CGFloat.greatestFiniteMagnitude
        )
        if textView.frame.width != resolvedWidth {
            textView.frame = CGRect(x: 0, y: 0, width: resolvedWidth, height: textView.frame.height)
        }

        let glyphRange = layoutManager.glyphRange(for: textContainer)
        layoutManager.ensureLayout(for: textContainer)

        let minimumHeight = ceil((textView.font?.ascender ?? 0) - (textView.font?.descender ?? 0))
        var maxLineFragmentY: CGFloat = 0
        layoutManager.enumerateLineFragments(forGlyphRange: glyphRange) { _, usedRect, _, _, _ in
            maxLineFragmentY = max(maxLineFragmentY, usedRect.maxY)
        }

        if layoutManager.extraLineFragmentTextContainer == textContainer {
            maxLineFragmentY = max(maxLineFragmentY, layoutManager.extraLineFragmentRect.maxY)
        }

        let textHeight = ceil(maxLineFragmentY) + textView.textContainerInset.height * 2
        let resolvedHeight = max(minimumHeight, textHeight)

        cachedMeasurement = (width, resolvedHeight)
        return resolvedHeight
    }

    private func configureTextView() {
        textView.isEditable = false
        textView.isSelectable = true
        textView.isRichText = false
        textView.drawsBackground = false
        textView.backgroundColor = .clear
        textView.focusRingType = .none
        textView.textContainerInset = .zero
        textView.isHorizontallyResizable = false
        textView.isVerticallyResizable = false
        textView.minSize = .zero
        textView.maxSize = CGSize(
            width: CGFloat.greatestFiniteMagnitude,
            height: CGFloat.greatestFiniteMagnitude
        )
        textView.autoresizingMask = []
        textView.textContainer?.lineFragmentPadding = 0
        textView.textContainer?.widthTracksTextView = false
        textView.textContainer?.heightTracksTextView = false
        textView.textContainer?.lineBreakMode = .byWordWrapping
    }

    private func makeAttributedString(
        text: String,
        font: NSFont,
        textColor: NSColor,
        preferredLineHeight: CGFloat
    ) -> NSAttributedString {
        ParagraphTextAttributedStringBuilder.build(
            text: text,
            font: font,
            textColor: textColor,
            preferredLineHeight: preferredLineHeight
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
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try! ModelContainer(for: WordRecord.self, configurations: config)
    return OverlayView()
        .environmentObject(AppModel(
            settings: SettingsStore(),
            permissions: PermissionManager(),
            modelContext: container.mainContext
        ))
        .frame(width: 500, height: 300)
        .background(.gray.opacity(0.3))
}

// MARK: - Auto Dismiss Error View

private struct AutoDismissErrorView: View {
    let message: String
    let onDismiss: () -> Void
    @State private var remainingSeconds: Double = 3.0
    @State private var timer: Timer?

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 12) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(Color(red: 1.0, green: 0.58, blue: 0.0))
                Text(message)
                    .font(.system(size: 14, weight: .medium, design: .rounded))
                    .foregroundStyle(.primary)
                Spacer(minLength: 0)
            }

            HStack(spacing: 6) {
                Image(systemName: "clock")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
                Text(String(format: "%.0fs", max(1, remainingSeconds)))
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
        }
        .padding(.vertical, 14)
        .padding(.horizontal, 18)
        .onAppear {
            startCountdown()
        }
        .onDisappear {
            timer?.invalidate()
        }
    }

    private func startCountdown() {
        timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { _ in
            remainingSeconds -= 0.1
            if remainingSeconds <= 0 {
                timer?.invalidate()
                timer = nil
                onDismiss()
            }
        }
    }
}

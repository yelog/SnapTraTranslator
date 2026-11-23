import AppKit
import SwiftUI
import SwiftData

struct OverlayView: View {
    private let paragraphOverlayMaxSize: CGSize?
    private let isParagraphWordPanel: Bool

    @EnvironmentObject var model: AppModel
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast
    @Environment(\.accessibilityReduceTransparency) private var accessibilityReduceTransparency
    @StateObject private var localizationManager = LocalizationManager.shared
    @State private var isParagraphHeaderDragging = false
    @State private var isParagraphLanguageDirectionHovered = false
    @State private var isParagraphOriginalEditorExpanded = false
    @State private var comparisonUsesCustomHeight = false
    private var showsAllParagraphTranslations: Bool { model.settings.showsAllSentenceTranslations }
    private let wordOverlayWidth: CGFloat = 380
    private let compactSectionMinHeight: CGFloat = 28
    private let paragraphTextHorizontalPadding: CGFloat = 16
    private var paragraphBodyFontSize: CGFloat { model.settings.sentencePopupFontSize }
    private let wordHeaderHorizontalPadding: CGFloat = 18
    private let wordHeaderControlGroupWidth: CGFloat = 132
    private let wordHeaderControlGap: CGFloat = 12

    init(paragraphOverlayMaxSize: CGSize? = nil, isParagraphWordPanel: Bool = false) {
        self.paragraphOverlayMaxSize = paragraphOverlayMaxSize
        self.isParagraphWordPanel = isParagraphWordPanel
    }

    private var displayedState: OverlayState {
        isParagraphWordPanel ? model.paragraphWordContent.map(OverlayState.result) ?? .idle : model.overlayState
    }

    private var overlayWidth: CGFloat {
        if isParagraphWordPanel {
            return min(wordOverlayWidth, paragraphOverlayMaxSize?.width ?? wordOverlayWidth)
        }
        if isParagraphOverlayMode {
            let targetWidth = paragraphOverlayTargetWidth
            guard let availableWidth = paragraphOverlayMaxSize?.width,
                  availableWidth > 0 else {
                return targetWidth
            }
            return min(targetWidth, availableWidth)
        }
        return model.overlayPreferredWidth ?? wordOverlayWidth
    }

    private var heightLimit: CGFloat? {
        guard isParagraphOverlayMode else { return isParagraphWordPanel ? paragraphOverlayMaxSize?.height : nil }
        if showsAllParagraphTranslations, !comparisonUsesCustomHeight, case .paragraphResult(let content) = displayedState,
           !content.isManualTextEntry, content.hasMultipleTranslationSources {
            return paragraphOverlayMaxSize?.height
        }
        guard let preferredHeight = model.settings.sentencePopupSize?.maxHeight else { return paragraphOverlayMaxSize?.height }
        let height = CGFloat(preferredHeight)
        return min(height, paragraphOverlayMaxSize?.height ?? height)
    }

    private var paragraphOverlayTargetWidth: CGFloat {
        let preferredWidth = model.settings.sentencePopupSize?.width
        guard case .paragraphResult(let content) = displayedState else { return preferredWidth ?? 260 }
        if content.isManualTextEntry { return max(300, preferredWidth ?? 380) }

        let priority = model.settings.sentenceTranslationSources.map(\.type)
        let sources = ParagraphReadingSources(content: content, priority: priority)
        let headerFont = NSFont.systemFont(ofSize: 11, weight: .medium)
        var toolbarWidth: CGFloat = 120
        if hasParagraphLanguageDirection(content),
           let source = content.sourceLanguageIdentifier, let target = content.selectedTargetLanguageIdentifier {
            for language in [source, target] {
                let label = paragraphLanguageName(for: language, content: content) as NSString
                toolbarWidth += label.size(withAttributes: [.font: headerFont]).width
            }
            toolbarWidth += 30
        }
        if content.hasMultipleTranslationSources {
            let longestName = sources.results.map {
                (paragraphSourceShortName($0.sourceType) as NSString).size(withAttributes: [.font: headerFont]).width
            }.max() ?? 0
            toolbarWidth += longestName + 22
        }

        if let preferredWidth { return max(ceil(toolbarWidth), preferredWidth) }

        // Providers that stream can publish on every token. Use the original
        // for the entire lookup so only the height changes while reading.
        let original = content.originalText ?? ""
        var texts = [original]
        if !sources.results.contains(where: { $0.sourceType.isLLMProvider }),
           let translation = sources.primary.readableText {
            texts = paragraphOriginalVisibility(for: content).showsOriginalTextRegion ? [original, translation] : [translation]
        }
        let textWidth = texts.map { text in
            ParagraphFontSizing.maximumLineWidth(for: String(text.prefix(512)), font: paragraphBodyFont)
        }.max() ?? 0
        return ceil(min(500, max(200, toolbarWidth, textWidth + 2 * paragraphTextHorizontalPadding + 2)))
    }

    private var paragraphBodyFont: NSFont {
        .systemFont(ofSize: paragraphBodyFontSize, weight: .regular)
    }

    private var paragraphBodyLineHeight: CGFloat {
        paragraphBodyFontSize * 1.5
    }

    private var increasesContrast: Bool {
        colorSchemeContrast == .increased
    }

    private var showsWordOverlayControls: Bool {
        isParagraphWordPanel || !model.settings.continuousTranslation
            || model.isTapKeptOverlayPresented
    }

    private var useSelectableWordText: Bool {
        WordOverlayTextSelectionPolicy.usesSelectableText(
            isWordOverlayMode: isWordOverlayMode,
            showsWordOverlayControls: showsWordOverlayControls
        )
    }

    private var isWordOverlayMode: Bool {
        !isParagraphOverlayMode
    }

    private var isParagraphOverlayMode: Bool {
        switch displayedState {
        case .paragraphLoading, .paragraphResult:
            return true
        default:
            return false
        }
    }

    private var showsParagraphOverlayPinButton: Bool {
        ParagraphOverlayControlPolicy.showsPinButton(
            isParagraphOverlayMode: isParagraphOverlayMode,
            isParagraphOverlayPinned: model.isParagraphOverlayPinned,
            isTapKeptOverlay: model.isTapKeptOverlayPresented
        )
    }

    private var canDragPinnedParagraphOverlay: Bool {
        isParagraphOverlayMode && model.isParagraphOverlayPinned
    }

    private var isVisible: Bool {
        if case .idle = displayedState { return false }
        return true
    }

    private var wordTargetLanguage: String {
        guard case .result(let content) = displayedState else { return model.settings.targetLanguage }
        return content.targetLanguageIdentifier ?? model.settings.targetLanguage
    }

    private var showsExtendedDictionaryDetails: Bool {
        !wordTargetLanguage.hasPrefix("zh")
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
            switch displayedState {
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
        .frame(maxHeight: heightLimit)
        .fixedSize(horizontal: false, vertical: heightLimit != nil)
        .frame(maxHeight: heightLimit, alignment: .topLeading)
        .background {
            if isParagraphOverlayMode {
                paragraphOverlayBackground
            } else {
                wordOverlayBackground
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: overlayCornerRadius, style: .continuous))
        .overlay {
            if isParagraphOverlayMode {
                paragraphOverlayBorder
            } else {
                wordOverlayBorder
            }
        }
        .overlay(alignment: .bottomTrailing) {
            if case .paragraphResult(let content) = displayedState, model.selectedTextReplacementOperationID == nil {
                SentencePopupResizeHandle {
                    if content.hasMultipleTranslationSources && showsAllParagraphTranslations {
                        comparisonUsesCustomHeight = true
                    }
                }
                .padding(3)
            }
        }
        .shadow(
            color: .black.opacity(colorScheme == .dark ? 0.22 : 0.08),
            radius: isParagraphOverlayMode ? 3 : 2,
            x: 0,
            y: 1
        )
        .shadow(
            color: .black.opacity(colorScheme == .dark ? 0.18 : 0.06),
            radius: isParagraphOverlayMode ? 24 : 14,
            x: 0,
            y: isParagraphOverlayMode ? 12 : 8
        )
        .onChange(of: isParagraphOverlayMode) { _, isParagraphMode in
            if !isParagraphMode {
                comparisonUsesCustomHeight = false
                resetParagraphHeaderInteractionState()
                resetParagraphOriginalEditorState()
            }
        }
        .onChange(of: model.activeLookupID) { _, lookupID in
            if lookupID != nil { comparisonUsesCustomHeight = false }
        }
        .onChange(of: model.isParagraphOverlayPinned) { _, isPinned in
            if !isPinned {
                resetParagraphOriginalEditorState()
            }
        }
        .onChange(of: model.settings.hideOriginalTextInSentenceOverlay) { _, hidesOriginalText in
            if hidesOriginalText {
                resetParagraphOriginalEditorState()
            }
        }
        .onDisappear {
            comparisonUsesCustomHeight = false
            resetParagraphHeaderInteractionState()
            resetParagraphOriginalEditorState()
        }
    }

    private var overlayCornerRadius: CGFloat {
        isParagraphOverlayMode ? 18 : 16
    }

    private var wordOverlayBackground: some View {
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

    private var paragraphOverlayBackground: some View {
        let shape = RoundedRectangle(cornerRadius: overlayCornerRadius, style: .continuous)

        return ZStack {
            if accessibilityReduceTransparency {
                shape
                    .fill(Color(nsColor: .windowBackgroundColor))
            } else if increasesContrast {
                shape
                    .fill(.thickMaterial)
            } else {
                shape
                    .fill(.regularMaterial)
            }

            shape
                .fill(colorScheme == .dark
                    ? Color.black.opacity(increasesContrast ? 0.28 : 0.18)
                    : Color.white.opacity(increasesContrast ? 0.30 : 0.20))
        }
    }

    private var wordOverlayBorder: some View {
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
    }

    private var paragraphOverlayBorder: some View {
        RoundedRectangle(cornerRadius: overlayCornerRadius, style: .continuous)
            .strokeBorder(
                LinearGradient(
                    colors: colorScheme == .dark
                        ? [
                            .white.opacity(increasesContrast ? 0.48 : 0.26),
                            .white.opacity(increasesContrast ? 0.24 : 0.12),
                            .white.opacity(increasesContrast ? 0.14 : 0.06),
                        ]
                        : [
                            .black.opacity(increasesContrast ? 0.20 : 0.09),
                            .black.opacity(increasesContrast ? 0.11 : 0.05),
                            .black.opacity(increasesContrast ? 0.08 : 0.03),
                        ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                lineWidth: 1
            )
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
            headerSection(content: content)

            if isParagraphWordPanel {
                ParagraphReadingViewport {
                    wordDefinitions(content: content)
                }
                .id(content.word)
            } else {
                wordDefinitions(content: content)
            }
        }
    }

    @ViewBuilder
    private func wordDefinitions(content: OverlayContent) -> some View {
        primaryTranslationSection(content: content)
        if !content.visibleDictionarySections.isEmpty {
            dictionarySectionsView(sections: content.visibleDictionarySections)
        }
    }

    private var paragraphLoadingView: some View {
        VStack(alignment: .leading, spacing: 0) {
            paragraphLoadingTopBar

            ParagraphReadingViewport {
                Text(L("Detecting text under cursor"))
                    .font(.system(size: paragraphBodyFontSize, weight: .regular))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, paragraphTextHorizontalPadding)
                    .padding(.top, 2)
                    .padding(.bottom, 14)
            }
        }
    }

    @ViewBuilder
    private func paragraphResultView(content: ParagraphOverlayContent) -> some View {
        if content.isManualTextEntry {
            manualTextEntryView(content: content)
        } else {
            paragraphTranslationResultView(content: content)
        }
    }

    private func paragraphOriginalVisibility(for content: ParagraphOverlayContent) -> ParagraphOriginalVisibilityPolicy.Decision {
        ParagraphOriginalVisibilityPolicy.resolve(
            hasOriginalText: !(content.originalText ?? "").isEmpty,
            isParagraphOverlayPinned: model.isParagraphOverlayPinned,
            hidesOriginalTextSetting: model.settings.hideOriginalTextInSentenceOverlay,
            isOriginalEditorExpanded: isParagraphOriginalEditorExpanded,
            isManualInputFallback: content.isManualInputFallback,
            hasTranslationOutput: content.showsNativeTranslation || !content.serviceResults.isEmpty
        )
    }

    @ViewBuilder
    private func paragraphTranslationResultView(content: ParagraphOverlayContent) -> some View {
        let originalText = content.originalText ?? ""
        let originalVisibility = paragraphOriginalVisibility(for: content)
        let showsAutoDismissFailure = originalText.isEmpty && content.serviceResults.isEmpty && !originalVisibility.showsOriginalTextRegion
        let sources = ParagraphReadingSources(content: content, priority: model.settings.sentenceTranslationSources.map(\.type))
        let comparesSources = content.hasMultipleTranslationSources && showsAllParagraphTranslations
        let showsPendingTranslations = paragraphHasPendingTranslations(content)
        let hasTranslationOutputOrFailure = Self.paragraphStateHasDisplayableContent(sources.primary.state)

        VStack(alignment: .leading, spacing: 0) {
            paragraphResultTopBar(
                content: content,
                originalText: originalText,
                originalVisibility: originalVisibility,
                primary: comparesSources ? nil : sources.primary,
                comparisonSource: content.hasMultipleTranslationSources ? sources.primary.sourceType : nil
            )

            ParagraphReadingViewport(isEditing: originalVisibility.usesEditableOriginalText) {
                if showsAutoDismissFailure,
                   case .failed(let message) = content.translationState {
                    // Auto-dismiss error view for paragraph translation errors with no original text.
                    AutoDismissErrorView(message: L(message), onDismiss: { model.dismissOverlay() })
                        .padding(.horizontal, paragraphTextHorizontalPadding)
                        .padding(.vertical, 18)
                } else {
                    VStack(alignment: .leading, spacing: 0) {
                        if originalVisibility.showsOriginalTextRegion {
                            paragraphOriginalSection(
                                text: originalText,
                                usesEditableOriginalText: originalVisibility.usesEditableOriginalText
                            )
                        }

                        VStack(alignment: .leading, spacing: 12) {
                            ForEach(sources.visibleResults(expanded: comparesSources)) { result in
                                paragraphReadingResult(
                                    result,
                                    showsSourceHeader: comparesSources,
                                    isStale: result.sourceType == .native && content.isRetranslating
                                )
                            }
                        }
                        .padding(.horizontal, paragraphTextHorizontalPadding)
                        .padding(.top, originalVisibility.showsOriginalTextRegion ? 0 : 2)

                        if showsPendingTranslations && (comparesSources || sources.primary.readableText == nil || content.isRetranslating) {
                            paragraphWaitingIndicator
                        } else if !hasTranslationOutputOrFailure {
                            paragraphNoTranslationResultView
                        }

                        if model.isWaitingForSelectedTextReplacementModifiers {
                            Text(L("Release shortcut keys to replace."))
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                                .padding(.horizontal, paragraphTextHorizontalPadding)
                                .padding(.vertical, 8)
                        } else if let feedback = model.selectedTextReplacementFeedback {
                            Text(feedback)
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                                .padding(.horizontal, paragraphTextHorizontalPadding)
                                .padding(.vertical, 8)
                        }
                    }
                }
            }
        }
        .onChange(of: comparesSources) { _, _ in
            model.refreshParagraphOverlayLayoutImmediately()
        }
        .onChange(of: comparisonUsesCustomHeight) { _, _ in
            model.refreshParagraphOverlayLayoutImmediately()
        }
        .onChange(of: originalVisibility) { _, _ in
            model.refreshParagraphOverlayLayoutImmediately()
        }
    }

    private func manualTextEntryView(content: ParagraphOverlayContent) -> some View {
        let originalText = content.originalText ?? ""
        let hasOriginalText = !originalText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty

        return VStack(alignment: .leading, spacing: 0) {
            manualTextEntryTopBar(showsDetectionStatus: !hasOriginalText)

            ParagraphReadingViewport {
                manualTextEntryBody(originalText: originalText, hasOriginalText: hasOriginalText)
            }
        }
    }

    private func manualTextEntryBody(originalText: String, hasOriginalText: Bool) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            manualTextEntryEditor(text: originalText)

            HStack(spacing: 6) {
                manualTextEntrySecondaryAction(
                    systemImage: "doc.on.clipboard",
                    title: L("Paste"),
                    action: { model.pasteClipboardIntoParagraphTextEntry() }
                )

                manualTextEntrySecondaryAction(
                    systemImage: "rectangle.dashed",
                    title: L("Select Area"),
                    action: { model.beginManualParagraphRegionSelection() }
                )

                Spacer(minLength: 8)

                manualTextEntryPrimaryAction(isEnabled: hasOriginalText)
            }

            HStack(spacing: 6) {
                Image(systemName: "return")
                    .font(.system(size: 9.5, weight: .semibold))
                    .accessibilityHidden(true)

                Text(L("Return to translate · Shift-Return for line break"))
                    .font(.system(size: 10.5, weight: .medium, design: .rounded))
            }
            .foregroundStyle(.tertiary)
            .padding(.leading, 2)
        }
        .padding(.horizontal, paragraphTextHorizontalPadding)
    }

    private func manualTextEntryTopBar(showsDetectionStatus: Bool) -> some View {
        ZStack(alignment: .leading) {
            paragraphHeaderDragArea()

            HStack(spacing: 10) {
                HStack(spacing: 7) {
                    Image(systemName: "text.cursor")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                        .accessibilityHidden(true)

                    Text(L("Translate Text"))
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .accessibilityAddTraits(.isHeader)
                }
                .lineLimit(1)
                .layoutPriority(1)

                Spacer(minLength: 0)

                if showsDetectionStatus {
                    Text(L("No text detected"))
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                paragraphOverlayControlButton(
                    systemImage: "xmark",
                    helpText: L("Close"),
                    action: { model.dismissOverlay() }
                )
            }
        }
        .frame(height: 24)
        .padding(.horizontal, paragraphTextHorizontalPadding)
        .padding(.vertical, 10)
    }

    private func manualTextEntryEditor(text: String) -> some View {
        EditableParagraphTextView(
            text: text,
            placeholder: L("Type or paste text to translate"),
            font: paragraphBodyFont,
            textColor: .labelColor,
            placeholderColor: .placeholderTextColor,
            preferredLineHeight: paragraphBodyLineHeight,
            minimumHeight: 58,
            onTextChange: { newText in
                if newText != text {
                    model.updateParagraphOriginalText(newText)
                }
            },
            onSubmit: { model.submitParagraphOriginalText() }
        )
        .disabled(model.selectedTextReplacementOperationID != nil)
        .padding(.horizontal, 12)
        .padding(.vertical, 11)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(paragraphEditorFillColor)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(paragraphEditorStrokeColor, lineWidth: 1)
        )
        .shadow(color: paragraphEditorShadowColor, radius: 1.5, x: 0, y: 1)
    }

    private func manualTextEntrySecondaryAction(
        systemImage: String,
        title: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: systemImage)
                    .font(.system(size: 10, weight: .semibold))

                Text(title)
                    .font(.system(size: 11, weight: .medium, design: .rounded))
            }
            .foregroundStyle(.secondary)
            .padding(.horizontal, 9)
            .frame(height: 27)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(manualTextEntryActionFillColor)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .stroke(manualTextEntryActionStrokeColor, lineWidth: 0.75)
            )
            .contentShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(title))
    }

    private func manualTextEntryPrimaryAction(isEnabled: Bool) -> some View {
        Button {
            model.submitParagraphOriginalText()
        } label: {
            HStack(spacing: 6) {
                Text(L("Translate"))
                    .font(.system(size: 11.5, weight: .semibold, design: .rounded))

                Image(systemName: "return")
                    .font(.system(size: 9.5, weight: .semibold))
            }
            .foregroundStyle(isEnabled ? Color.white : Color.secondary)
            .padding(.horizontal, 11)
            .frame(height: 27)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(isEnabled ? Color.accentColor : Color.secondary.opacity(0.08))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .stroke(
                        isEnabled
                            ? Color.white.opacity(0.14)
                            : manualTextEntryActionStrokeColor,
                        lineWidth: 0.75
                    )
            )
            .contentShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .accessibilityLabel(Text(L("Translate")))
    }

    private var manualTextEntryActionFillColor: Color {
        if colorScheme == .dark {
            return Color.white.opacity(increasesContrast ? 0.12 : 0.07)
        }
        return Color.black.opacity(increasesContrast ? 0.09 : 0.045)
    }

    private var manualTextEntryActionStrokeColor: Color {
        colorScheme == .dark
            ? Color.white.opacity(increasesContrast ? 0.20 : 0.09)
            : Color.black.opacity(increasesContrast ? 0.14 : 0.06)
    }

    @ViewBuilder
    private func paragraphOriginalSection(
        text: String,
        usesEditableOriginalText: Bool
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Text(paragraphOriginalSectionTitle)
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundStyle(.tertiary)

                if !text.isEmpty {
                    CopyButton(text: text)
                }

                Spacer(minLength: 0)
            }

            paragraphOriginalTextView(
                text: text,
                usesEditableOriginalText: usesEditableOriginalText
            )
        }
        .padding(.horizontal, paragraphTextHorizontalPadding)
        .padding(.top, 2)
        .padding(.bottom, 12)
    }

    @ViewBuilder
    private func paragraphOriginalTextView(
        text: String,
        usesEditableOriginalText: Bool
    ) -> some View {
        if usesEditableOriginalText {
            editableParagraphOriginalTextView(text: text)
        } else {
            if !text.isEmpty {
                paragraphTextContent(
                    text: text,
                    textColor: .secondaryLabelColor,
                    onWordDoubleClick: paragraphWordLookup(from: .original)
                )
            }
        }
    }

    private func paragraphHasPendingTranslations(_ content: ParagraphOverlayContent) -> Bool {
        if content.isRetranslating {
            return true
        }
        if case .loading = content.translationState,
           content.showsNativeTranslation || content.serviceResults.isEmpty {
            return true
        }
        return content.serviceResults.contains { $0.state.isLoading }
    }

    private static func paragraphStateHasDisplayableContent(
        _ state: TranslationResultState
    ) -> Bool {
        switch state {
        case .loading:
            return false

        case .ready(let text):
            return !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty

        case .failed:
            return true
        }
    }

    @ViewBuilder
    private func paragraphReadingResult(
        _ result: ServiceTranslationResult,
        showsSourceHeader: Bool,
        isStale: Bool
    ) -> some View {
        if Self.paragraphStateHasDisplayableContent(result.state) {
            VStack(alignment: .leading, spacing: 5) {
                if showsSourceHeader {
                    paragraphMultiSourceHeader(
                        sourceType: result.sourceType,
                        copyText: result.readableText,
                        detailsResult: result
                    )
                }
                switch result.state {
                case .ready(let text):
                    paragraphTextContent(
                        text: text,
                        textColor: isStale ? .secondaryLabelColor : .labelColor,
                        onWordDoubleClick: isStale ? nil : paragraphWordLookup(from: .translation)
                    )
                case .failed(let message):
                    paragraphErrorContent(message: L(message))
                case .loading:
                    EmptyView()
                }
            }
        }
    }

    private func paragraphMultiSourceHeader(
        sourceType: SentenceTranslationSource.SourceType,
        copyText: String?,
        detailsResult: ServiceTranslationResult?
    ) -> some View {
        HStack(alignment: .center, spacing: 5) {
            Text(paragraphSourceShortName(sourceType))
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.tail)

            Spacer(minLength: 8)

            if let copyText, !copyText.isEmpty {
                CopyButton(text: copyText, usesSubtleHeaderStyle: true)

                if model.showsSelectedTextReplacement(using: sourceType) {
                    replaceSelectedTextButton(using: sourceType)
                }
            }

            if let detailsResult {
                paragraphSourceDetailsMenu(result: detailsResult)
            }
        }
    }

    private func paragraphSourceShortName(
        _ sourceType: SentenceTranslationSource.SourceType
    ) -> String {
        switch sourceType {
        case .native:
            return L("System")
        case .google:
            return "Google"
        case .bing:
            return "Bing"
        case .youdao:
            return "Youdao"
        case .openAI:
            return "OpenAI"
        case .anthropic:
            return "Claude"
        case .gemini:
            return "Gemini"
        case .deepSeek:
            return "DeepSeek"
        case .zhipu:
            return L("Zhipu")
        case .ollama:
            return "Ollama"
        case .omlx:
            return "oMLX"
        }
    }

    private func paragraphHasSourceDetails(_ result: ServiceTranslationResult) -> Bool {
        if let modelName = result.modelName?.trimmingCharacters(in: .whitespacesAndNewlines),
           !modelName.isEmpty {
            return true
        }
        return result.duration != nil
    }

    @ViewBuilder
    private func paragraphSourceDetailsMenu(result: ServiceTranslationResult) -> some View {
        if paragraphHasSourceDetails(result) {
            Menu {
                if let modelName = result.modelName?.trimmingCharacters(in: .whitespacesAndNewlines),
                   !modelName.isEmpty {
                    Text("\(L("Model")): \(modelName)")
                }

                if let duration = result.duration {
                    Text("\(L("Translation time")): \(Self.formatTranslationDuration(duration))")
                }
            } label: {
                paragraphMenuIcon
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .help(L("More"))
            .accessibilityLabel(Text(L("More")))
        }
    }

    private var paragraphWaitingIndicator: some View {
        Text(L("Translating"))
            .font(.system(size: 11, weight: .medium, design: .rounded))
            .foregroundStyle(.tertiary)
            .padding(.horizontal, paragraphTextHorizontalPadding)
            .padding(.top, 6)
    }

    private var paragraphNoTranslationResultView: some View {
        Text(L("No translation result"))
            .font(.system(size: 12, weight: .medium, design: .rounded))
            .foregroundStyle(.secondary)
            .padding(.horizontal, paragraphTextHorizontalPadding)
            .padding(.top, 6)
    }

    private func editableParagraphOriginalTextView(text: String) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            EditableParagraphTextView(
                text: text,
                placeholder: L("Type or paste text to translate"),
                font: paragraphBodyFont,
                textColor: .labelColor,
                placeholderColor: .placeholderTextColor,
                preferredLineHeight: paragraphBodyLineHeight,
                minimumHeight: 0,
                onWordDoubleClick: paragraphWordLookup(from: .original),
                onTextChange: { newText in
                    if newText != text {
                        model.updateParagraphOriginalText(newText)
                    }
                },
                onSubmit: { model.submitParagraphOriginalText() }
            )
            .disabled(model.selectedTextReplacementOperationID != nil)
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(paragraphEditorFillColor)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(paragraphEditorStrokeColor, lineWidth: 1)
            )
            .shadow(color: paragraphEditorShadowColor, radius: 1.5, x: 0, y: 1)

            HStack(spacing: 6) {
                Image(systemName: "return")
                    .font(.system(size: 9.5, weight: .semibold))

                Text(L("Return to translate · Shift-Return for line break"))
                    .font(.system(size: 10.5, weight: .medium, design: .rounded))
            }
            .foregroundStyle(.tertiary)
            .padding(.leading, 2)
        }
    }

    private var paragraphEditorFillColor: Color {
        if accessibilityReduceTransparency {
            return Color(nsColor: .textBackgroundColor)
        }

        if colorScheme == .dark {
            return Color.white.opacity(increasesContrast ? 0.075 : 0.05)
        }
        return Color.white.opacity(increasesContrast ? 0.72 : 0.58)
    }

    private var paragraphEditorStrokeColor: Color {
        colorScheme == .dark
            ? Color.white.opacity(increasesContrast ? 0.20 : 0.10)
            : Color.black.opacity(increasesContrast ? 0.14 : 0.055)
    }

    private var paragraphEditorShadowColor: Color {
        colorScheme == .dark ? Color.black.opacity(0.12) : Color.black.opacity(0.025)
    }

    private var paragraphLoadingTopBar: some View {
        ZStack(alignment: .leading) {
            paragraphHeaderDragArea()

            HStack(spacing: 5) {
                Spacer(minLength: 0)

                if showsParagraphOverlayPinButton || !model.isParagraphOverlayPinned {
                    paragraphLoadingMoreMenu
                }

                paragraphPinnedCloseButton
            }
        }
        .frame(height: 24)
        .padding(.horizontal, 16)
        .padding(.top, 10)
        .padding(.bottom, 6)
    }

    private func paragraphResultTopBar(
        content: ParagraphOverlayContent,
        originalText: String,
        originalVisibility: ParagraphOriginalVisibilityPolicy.Decision,
        primary: ServiceTranslationResult?,
        comparisonSource: SentenceTranslationSource.SourceType?
    ) -> some View {
        ZStack(alignment: .leading) {
            paragraphHeaderDragArea()

            HStack(spacing: 4) {
                if hasParagraphLanguageDirection(content) {
                    paragraphLanguageDirectionButton(content: content)
                }

                Spacer(minLength: 8)

                if let comparisonSource {
                    let action = showsAllParagraphTranslations ? L("Show primary translation") : L("Show all translations")
                    Button {
                        comparisonUsesCustomHeight = false
                        model.settings.showsAllSentenceTranslations.toggle()
                    } label: {
                        HStack(spacing: 3) {
                            Text(paragraphSourceShortName(comparisonSource))
                                .font(.system(size: 11, weight: .medium))
                                .lineLimit(1)
                            Image(systemName: showsAllParagraphTranslations ? "chevron.up" : "chevron.down")
                                .font(.system(size: 9, weight: .semibold))
                        }
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 3)
                        .frame(minHeight: 22)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help(action)
                    .accessibilityLabel(Text(action))
                    .accessibilityValue(Text(paragraphSourceShortName(comparisonSource)))
                    .accessibilityIdentifier("sentenceTranslationComparison")
                }

                if let copyText = primary?.readableText {
                    CopyButton(text: copyText, usesSubtleHeaderStyle: true)
                }

                paragraphMoreMenu(
                    originalVisibility: originalVisibility,
                    originalText: originalText,
                    singleSourceResult: primary,
                    replacementSourceType: primary?.sourceType
                )

                paragraphPinnedCloseButton
            }
        }
        .frame(height: 24)
        .padding(.leading, 10)
        .padding(.trailing, 16)
        .padding(.top, 10)
        .padding(.bottom, 6)
    }

    @ViewBuilder
    private func paragraphMoreMenu(
        originalVisibility: ParagraphOriginalVisibilityPolicy.Decision,
        originalText: String,
        singleSourceResult: ServiceTranslationResult?,
        replacementSourceType: SentenceTranslationSource.SourceType?
    ) -> some View {
        let showsDetails = singleSourceResult.map { paragraphHasSourceDetails($0) } ?? false
        let showsOriginalEditorToggle = originalVisibility.showsOriginalEditorToggle
        let showsRegionSelection = isParagraphOverlayMode
        let hasOriginalText = !originalText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let showsReplaceSelectedText = replacementSourceType.map {
            model.showsSelectedTextReplacement(using: $0)
        } ?? false
        let autoReadAloudBinding = Binding<Bool>(
            get: { model.settings.playSentencePronunciation },
            set: { model.settings.playSentencePronunciation = $0 }
        )

        Menu {
            Button {
                model.playOverlayPronunciation(kind: .sentence)
            } label: {
                Label(L("Read Aloud"), systemImage: "speaker.wave.2")
            }
            .disabled(!hasOriginalText)

            Toggle(L("Auto Read Aloud"), isOn: autoReadAloudBinding)

            Divider()

            if showsOriginalEditorToggle {
                Button {
                    model.invalidateSelectedTextReplacement()
                    isParagraphOriginalEditorExpanded.toggle()
                } label: {
                    Label(
                        originalVisibility.usesEditableOriginalText
                            ? L("Hide Original Text")
                            : L("Edit Original Text"),
                        systemImage: originalVisibility.usesEditableOriginalText ? "eye.slash" : "pencil"
                    )
                }
            }

            if showsRegionSelection {
                Button {
                    model.beginManualParagraphRegionSelection()
                } label: {
                    Label(L("Reselect Region"), systemImage: "crop")
                }
            }

            if let replacementSourceType, showsReplaceSelectedText {
                Button {
                    model.replaceSelectedText(using: replacementSourceType)
                } label: {
                    Label(L("Replace Original"), systemImage: "arrow.uturn.backward")
                }
                .disabled(
                    model.selectedTextReplacementOperationID != nil
                        || model.isSelectedTextReplacementConsumed
                )
            }

            if showsParagraphOverlayPinButton {
                Button {
                    model.toggleParagraphOverlayPin()
                } label: {
                    Label(L("Pin"), systemImage: "pin")
                }
            }

            if !model.isParagraphOverlayPinned {
                Button {
                    model.dismissOverlay()
                } label: {
                    Label(L("Close"), systemImage: "xmark")
                }
            }

            if let singleSourceResult, showsDetails {
                Divider()

                if let modelName = singleSourceResult.modelName?.trimmingCharacters(in: .whitespacesAndNewlines),
                   !modelName.isEmpty {
                    Text("\(L("Model")): \(modelName)")
                }

                if let duration = singleSourceResult.duration {
                    Text("\(L("Translation time")): \(Self.formatTranslationDuration(duration))")
                }
            }
        } label: {
            paragraphMenuIcon
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help(L("More"))
        .accessibilityLabel(Text(L("More")))
    }

    private var paragraphMenuIcon: some View {
        ParagraphHeaderIcon(systemImage: "ellipsis")
    }

    private var paragraphLoadingMoreMenu: some View {
        Menu {
            if showsParagraphOverlayPinButton {
                Button {
                    model.toggleParagraphOverlayPin()
                } label: {
                    Label(L("Pin"), systemImage: "pin")
                }
            }

            if !model.isParagraphOverlayPinned {
                Button {
                    model.dismissOverlay()
                } label: {
                    Label(L("Close"), systemImage: "xmark")
                }
            }
        } label: {
            paragraphMenuIcon
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help(L("More"))
        .accessibilityLabel(Text(L("More")))
    }

    private func hasParagraphLanguageDirection(_ content: ParagraphOverlayContent) -> Bool {
        guard let sourceLanguageIdentifier = content.sourceLanguageIdentifier,
              let selectedTargetIdentifier = content.selectedTargetLanguageIdentifier else {
            return false
        }
        return sourceLanguageIdentifier != selectedTargetIdentifier
    }

    @ViewBuilder
    private func paragraphLanguageDirectionButton(
        content: ParagraphOverlayContent
    ) -> some View {
        if let selectedTargetIdentifier = content.selectedTargetLanguageIdentifier,
           let sourceLanguageIdentifier = content.sourceLanguageIdentifier,
           sourceLanguageIdentifier != selectedTargetIdentifier {
            let sourceName = paragraphLanguageName(
                for: sourceLanguageIdentifier,
                content: content
            )
            let targetName = paragraphLanguageName(
                for: selectedTargetIdentifier,
                content: content
            )
            let isToggleAvailable = model.selectedTextReplacementOperationID == nil

            Button {
                model.translateParagraphOriginal(to: sourceLanguageIdentifier)
            } label: {
                HStack(spacing: 5) {
                    Text(sourceName)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.tail)

                    Image(systemName: "arrow.right")
                        .font(.system(size: 8, weight: .semibold))
                        .foregroundStyle(.tertiary)

                    Text(targetName)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .contentShape(Capsule(style: .continuous))
            }
            .buttonStyle(.plain)
            .disabled(!isToggleAvailable)
            .onHover { isHovering in
                isParagraphLanguageDirectionHovered = isHovering && isToggleAvailable
            }
            .background {
                Capsule(style: .continuous)
                    .fill(
                        isParagraphLanguageDirectionHovered
                            ? Color.primary.opacity(increasesContrast ? 0.10 : 0.055)
                            : Color.clear
                    )
            }
            .overlay {
                Capsule(style: .continuous)
                    .stroke(
                        Color.secondary.opacity(
                            isParagraphLanguageDirectionHovered
                                ? (increasesContrast ? 0.32 : 0.14)
                                : 0
                        ),
                        lineWidth: 0.5
                    )
            }
            .accessibilityLabel(Text(L("Toggle translation direction")))
        }
    }

    private func paragraphLanguageName(
        for identifier: String,
        content: ParagraphOverlayContent
    ) -> String {
        let minimalIdentifier = Locale.Language(identifier: identifier).minimalIdentifier
        if let option = content.languageOptions.first(where: {
            Locale.Language(identifier: $0.identifier).minimalIdentifier == minimalIdentifier
        }) {
            return option.displayName
        }

        return AppLanguage(rawValue: identifier)?.displayName
            ?? Locale.current.localizedString(forIdentifier: identifier)
            ?? identifier
    }

    private func replaceSelectedTextButton(using sourceType: SentenceTranslationSource.SourceType) -> some View {
        Button {
            model.replaceSelectedText(using: sourceType)
        } label: {
            if model.selectedTextReplacementOperationID != nil {
                ProgressView()
                    .controlSize(.mini)
                    .frame(width: 18, height: 18)
            } else {
                Image(systemName: "arrow.uturn.backward")
                    .font(.system(size: 10, weight: .semibold))
                    .frame(width: 18, height: 18)
            }
        }
        .buttonStyle(.plain)
        .disabled(model.selectedTextReplacementOperationID != nil || model.isSelectedTextReplacementConsumed)
        .help(model.isWaitingForSelectedTextReplacementModifiers ? L("Release shortcut keys to replace.") : L("Replace Original"))
        .accessibilityLabel(model.isWaitingForSelectedTextReplacementModifiers ? L("Release shortcut keys to replace.") : L("Replace Original"))
    }

    private static func formatTranslationDuration(_ duration: TimeInterval) -> String {
        if duration < 1 {
            let milliseconds = Int((duration * 1000).rounded())
            return "\(milliseconds)ms"
        }
        return String(format: "%.1fs", duration)
    }

    private func paragraphWordLookup(from origin: ParagraphWordOrigin) -> (String, CGPoint) -> Void {
        { word, point in model.lookupParagraphWord(word, from: origin, at: point) }
    }

    private func paragraphTextContent(
        text: String,
        textColor: NSColor,
        onWordDoubleClick: ((String, CGPoint) -> Void)?
    ) -> some View {
        SelectableTextView(
            text: text,
            font: paragraphBodyFont,
            textColor: textColor,
            preferredLineHeight: paragraphBodyLineHeight,
            onWordDoubleClick: onWordDoubleClick
        )
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func wordSelectableText(
        _ text: String,
        font: NSFont,
        textColor: NSColor = .labelColor,
        preferredLineHeight: CGFloat
    ) -> some View {
        if useSelectableWordText {
            SelectableTextView(
                text: text,
                font: font,
                textColor: textColor,
                preferredLineHeight: preferredLineHeight
            )
            .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            Text(text)
        }
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
    private func paragraphHeaderDragArea() -> some View {
        ZStack(alignment: .leading) {
            if canDragPinnedParagraphOverlay {
                paragraphPinnedDragHandle
            } else {
                Color.clear
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
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
    private var paragraphPinnedCloseButton: some View {
        if model.isParagraphOverlayPinned {
            paragraphOverlayControlButton(
                systemImage: "xmark",
                helpText: L("Close"),
                action: { model.dismissOverlay() }
            )
        }
    }

    private func paragraphOverlayControlButton(
        systemImage: String,
        helpText: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            ParagraphHeaderIcon(systemImage: systemImage)
        }
        .buttonStyle(.plain)
        .help(helpText)
        .accessibilityLabel(Text(helpText))
    }

    private func pronunciationControl(kind: OverlayPronunciationKind, hasText: Bool) -> some View {
        let isAutoPlayEnabled = kind == .word
            ? model.settings.playWordPronunciation
            : model.settings.playSentencePronunciation
        let isActive = model.isPronunciationPlaying(kind: kind)
        let isFailed: Bool = {
            guard model.activePronunciationRequest?.kind == kind else { return false }
            if case .failed = model.speechPlaybackState { return true }
            return false
        }()
        let label = kind == .word ? L("Word") : L("Sentence")
        let playbackHelp = isFailed
            ? L("Pronunciation failed - click to retry")
            : (isActive ? L("Playing - click to restart") : L("Play pronunciation"))

        return HStack(spacing: 0) {
            Button {
                model.playOverlayPronunciation(kind: kind)
            } label: {
                Group {
                    if isActive, case .loading = model.speechPlaybackState {
                        ProgressView().controlSize(.small)
                    } else {
                        Image(systemName: isFailed ? "exclamationmark" : (isActive ? "waveform" : "speaker.wave.2"))
                            .font(.system(size: 10, weight: .semibold))
                    }
                }
                .foregroundStyle(isActive || isFailed ? Color.accentColor : .secondary)
                .frame(width: 26, height: 22)
            }
            .buttonStyle(.plain)
            .disabled(!hasText)
            .opacity(hasText ? 1 : 0.4)
            .help(playbackHelp)
            .accessibilityLabel(Text(hasText ? "\(playbackHelp) \(label)" : "No \(label) text to pronounce"))

            Divider().frame(height: 14)

            Button {
                if kind == .word {
                    model.settings.playWordPronunciation.toggle()
                } else {
                    model.settings.playSentencePronunciation.toggle()
                }
            } label: {
                HStack(spacing: 3) {
                    Text(L("Auto"))
                        .font(.system(size: 9, weight: .medium, design: .rounded))
                    Image(systemName: isAutoPlayEnabled ? "circle.fill" : "circle")
                        .font(.system(size: 8, weight: .semibold))
                }
                .foregroundStyle(isAutoPlayEnabled ? Color.accentColor : .secondary)
                .frame(width: 42, height: 22)
            }
            .buttonStyle(.plain)
            .help(isAutoPlayEnabled ? L("Pronunciation: On") : L("Pronunciation: Off"))
            .accessibilityLabel(Text(isAutoPlayEnabled ? L("Pronunciation: On") : L("Pronunciation: Off")))
            .accessibilityValue(Text(isAutoPlayEnabled ? L("On") : L("Off")))
        }
        .padding(.horizontal, 3)
        .background(
            Capsule(style: .continuous)
                .fill(colorScheme == .dark ? .white.opacity(0.08) : .black.opacity(0.045))
        )
        .overlay(
            Capsule(style: .continuous)
                .stroke(colorScheme == .dark ? .white.opacity(0.10) : .black.opacity(0.07), lineWidth: 0.5)
        )
    }

    private var paragraphOriginalSectionTitle: String {
        L("Original")
    }

    private func refreshParagraphHeaderCursor() {
        guard canDragPinnedParagraphOverlay else {
            NSCursor.arrow.set()
            return
        }

        if isParagraphHeaderDragging {
            NSCursor.closedHand.set()
        } else {
            NSCursor.arrow.set()
        }
    }

    private func resetParagraphHeaderInteractionState() {
        if isParagraphHeaderDragging {
            model.endParagraphOverlayDrag()
        }

        isParagraphHeaderDragging = false
        isParagraphLanguageDirectionHovered = false
        NSCursor.arrow.set()
    }

    private func resetParagraphOriginalEditorState() {
        isParagraphOriginalEditorExpanded = false
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
        let metrics = WordOverlayHeaderLayoutPolicy.resolve(
            panelWidth: overlayWidth,
            horizontalPadding: wordHeaderHorizontalPadding,
            controlGroupWidth: showsWordOverlayControls ? wordHeaderControlGroupWidth : 0,
            gapBetweenIdentityAndControls: showsWordOverlayControls ? wordHeaderControlGap : 0
        )

        HStack(alignment: .top, spacing: showsWordOverlayControls ? wordHeaderControlGap : 0) {
            wordIdentityGroup(content: content, metrics: metrics)
                .frame(maxWidth: metrics.identityGroupMaxWidth, alignment: .leading)

            Spacer(minLength: 0)

            if showsWordOverlayControls {
                wordHeaderControlGroup(content: content)
                    .frame(width: wordHeaderControlGroupWidth, alignment: .trailing)
            }
        }
        .padding(.horizontal, wordHeaderHorizontalPadding)
        .padding(.top, 16)
        .padding(.bottom, 12)
    }

    @ViewBuilder
    private func wordIdentityGroup(
        content: OverlayContent,
        metrics: WordOverlayHeaderLayoutPolicy.Metrics
    ) -> some View {
        let displayedPhonetic = WordOverlayHeaderLayoutPolicy.displayedPhonetic(content.phonetic)

        ViewThatFits(in: .horizontal) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                wordInlineTitleText(content.word)

                if let displayedPhonetic {
                    phoneticBadge(
                        displayedPhonetic,
                        resistsHorizontalCompression: !metrics.allowsPhoneticBadgeHorizontalCompression
                    )
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                wordTitleText(content.word, maxWidth: metrics.titleMaxWidth)

                if let displayedPhonetic {
                    phoneticBadge(
                        displayedPhonetic,
                        resistsHorizontalCompression: !metrics.allowsPhoneticBadgeHorizontalCompression
                    )
                }
            }
        }
    }

    private func wordInlineTitleText(_ word: String) -> some View {
        Text(word)
            .font(.system(size: 22, weight: .bold, design: .rounded))
            .foregroundStyle(.primary)
            .tracking(0.3)
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
    }

    private func wordTitleText(_ word: String, maxWidth: CGFloat) -> some View {
        Text(word)
            .font(.system(size: 22, weight: .bold, design: .rounded))
            .foregroundStyle(.primary)
            .tracking(0.3)
            .lineLimit(1)
            .truncationMode(.tail)
            .frame(maxWidth: maxWidth, alignment: .leading)
    }

    private func phoneticBadge(
        _ phonetic: String,
        resistsHorizontalCompression: Bool
    ) -> some View {
        Text(phonetic)
            .font(.system(size: 11, weight: .regular, design: .monospaced))
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .fixedSize(horizontal: resistsHorizontalCompression, vertical: false)
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

    private func wordHeaderControlGroup(content: OverlayContent) -> some View {
        HStack(alignment: .center, spacing: 8) {
            pronunciationControl(
                kind: .word,
                hasText: !content.word.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            )

            CopyButton(text: content.word)

            Button {
                if isParagraphWordPanel {
                    model.dismissParagraphWord()
                } else {
                    model.dismissOverlay()
                }
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
            .help(L("Close"))
            .accessibilityLabel(Text(L("Close")))
        }
    }

    @ViewBuilder
    private func primaryTranslationSection(content: OverlayContent) -> some View {
        if #available(macOS 15.0, *) {
            let targetIsEnglish = wordTargetLanguage.hasPrefix("en")
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
                                if useSelectableWordText {
                                    wordSelectableText(
                                        translation,
                                        font: .systemFont(ofSize: 17, weight: .medium),
                                        textColor: colorScheme == .dark
                                            ? NSColor(red: 0.2, green: 0.6, blue: 1.0, alpha: 1)
                                            : NSColor(red: 0.1, green: 0.4, blue: 0.85, alpha: 1),
                                        preferredLineHeight: 22
                                    )
                                } else {
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
                                }

                                if showsWordOverlayControls {
                                    CopyButton(text: translation)
                                }
                            } else {
                                if useSelectableWordText {
                                    wordSelectableText(
                                        translation,
                                        font: .systemFont(ofSize: 24, weight: .bold),
                                        preferredLineHeight: 30
                                    )
                                } else {
                                    Text(translation)
                                        .font(.system(size: 24, weight: .bold, design: .rounded))
                                        .foregroundStyle(.primary)
                                        .tracking(0.2)
                                }

                                if showsWordOverlayControls {
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
        } else if isParagraphWordPanel, content.visibleDictionarySections.isEmpty,
                  case .failed(let message) = content.primaryTranslationState {
            paragraphErrorContent(message: L(message))
                .padding(.horizontal, wordHeaderHorizontalPadding)
                .padding(.bottom, 16)
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
                    if useSelectableWordText {
                        wordSelectableText(
                            group.translations.joined(separator: "；"),
                            font: .systemFont(ofSize: 14, weight: .regular),
                            preferredLineHeight: 19
                        )
                    } else {
                        Text(group.translations.joined(separator: "；"))
                            .font(.system(size: 14, weight: .regular, design: .rounded))
                            .foregroundStyle(.primary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                if !group.meanings.isEmpty {
                    if useSelectableWordText {
                        wordSelectableText(
                            group.meanings.joined(separator: "\n"),
                            font: .systemFont(ofSize: 12, weight: .regular),
                            textColor: .secondaryLabelColor,
                            preferredLineHeight: 16
                        )
                    } else {
                        Text(group.meanings.joined(separator: "\n"))
                            .font(.system(size: 12, weight: .regular, design: .rounded))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                if !group.examples.isEmpty {
                    if useSelectableWordText {
                        wordSelectableText(
                            group.examples.prefix(2).map { "• \($0)" }.joined(separator: "\n"),
                            font: .systemFont(ofSize: 12, weight: .regular),
                            textColor: .secondaryLabelColor,
                            preferredLineHeight: 16
                        )
                        .padding(.top, 2)
                    } else {
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

                if useSelectableWordText {
                    wordSelectableText(
                        displayedSynonyms.joined(separator: " · "),
                        font: .systemFont(ofSize: 12, weight: .regular),
                        textColor: .secondaryLabelColor,
                        preferredLineHeight: 16
                    )
                } else {
                    Text(displayedSynonyms.joined(separator: " · "))
                        .font(.system(size: 12, weight: .regular, design: .rounded))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
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

            // Show meanings that differ from translations.
            // When target is Chinese and a Chinese translation already exists,
            // suppress the standalone English meaning — the Chinese translation
            // already preserves any embedded English proper nouns (e.g. "苹果公司",
            // "Mac 电脑"). Showing a full English definition alongside adds noise.
            let meaning = normalizedDictionaryText(definition.meaning)
            if let meaning,
               meaning.caseInsensitiveCompare(translation ?? "") != .orderedSame {
                let targetIsChinese = wordTargetLanguage.hasPrefix("zh")
                let translationHasChinese = translation?.range(of: "\\p{Han}", options: .regularExpression) != nil
                if !(targetIsChinese && translationHasChinese) {
                    grouped[key]?.meanings.appendIfMissing(meaning)
                }
            }

            if includeSupplementaryDetails {
                let examples = definition.examples.compactMap(normalizedDictionaryText)
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

struct ParagraphReadingViewport<Content: View>: View {
    private nonisolated enum ScrollSpace {
        case viewport
    }

    @State private var viewportHeight: CGFloat = 0
    @State private var showsMoreContentBelow = false
    private let isEditing: Bool
    private let content: Content

    init(isEditing: Bool = false, @ViewBuilder content: () -> Content) {
        self.isEditing = isEditing
        self.content = content()
    }

    var body: some View {
        if isEditing {
            scrollableContent
        } else {
            ViewThatFits(in: .vertical) {
                readingContent.fixedSize(horizontal: false, vertical: true)
                scrollableContent
            }
        }
    }

    private var readingContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            content
        }
        .padding(.bottom, 16)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var scrollableContent: some View {
        let viewportHeight = self.viewportHeight
        return ScrollView(.vertical) {
            readingContent
                .onGeometryChange(for: Bool.self) { geometry in
                    guard viewportHeight > 0, geometry.size.height > viewportHeight + 1 else { return false }
                    return geometry.frame(in: .named(ScrollSpace.viewport)).maxY > viewportHeight + 1
                } action: { showsMoreContentBelow = $0 }
        }
        .coordinateSpace(name: ScrollSpace.viewport)
        .scrollBounceBehavior(.basedOnSize, axes: .vertical)
        .onGeometryChange(for: CGFloat.self, of: \.size.height) { height in
            self.viewportHeight = height
        }
        .overlay(alignment: .bottom) {
            if showsMoreContentBelow {
                Rectangle()
                    .fill(.regularMaterial)
                    .mask(LinearGradient(colors: [.clear, .black], startPoint: .top, endPoint: .bottom))
                    .frame(height: 14)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
        }
    }
}

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

private extension ServiceTranslationResult {
    var hasFailed: Bool {
        if case .failed = state { return true }
        return false
    }

    var readableText: String? {
        guard case .ready(let text) = state,
              !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        return text
    }
}

struct ParagraphReadingSources {
    let results: [ServiceTranslationResult]
    let primary: ServiceTranslationResult

    func visibleResults(expanded: Bool) -> [ServiceTranslationResult] {
        expanded && !results.isEmpty ? results : [primary]
    }

    init(content: ParagraphOverlayContent, priority: [SentenceTranslationSource.SourceType]) {
        let native = ServiceTranslationResult(
            sourceType: .native,
            modelName: nil,
            state: content.translationState,
            isComplete: !content.isRetranslating && !content.translationState.isLoading
        )
        var results = content.serviceResults
        if content.showsNativeTranslation { results.insert(native, at: 0) }
        self.results = results.sorted {
            (priority.firstIndex(of: $0.sourceType) ?? .max) < (priority.firstIndex(of: $1.sourceType) ?? .max)
        }
        primary = self.results.first { $0.readableText != nil }
            ?? self.results.first(where: \.hasFailed)
            ?? self.results.first
            ?? native
    }
}

enum ParagraphOriginalVisibilityPolicy {
    struct Decision: Equatable {
        let showsOriginalTextRegion: Bool
        let usesEditableOriginalText: Bool
        let showsOriginalEditorToggle: Bool
        let hidesOriginalTextRegion: Bool

        var usesStableTranslationFont: Bool {
            usesEditableOriginalText || hidesOriginalTextRegion
        }
    }

    static func resolve(
        hasOriginalText: Bool,
        isParagraphOverlayPinned: Bool,
        hidesOriginalTextSetting: Bool,
        isOriginalEditorExpanded: Bool,
        isManualInputFallback: Bool = false,
        hasTranslationOutput: Bool = true
    ) -> Decision {
        let shouldHideOriginalText = hidesOriginalTextSetting && hasTranslationOutput
        let canEditOriginalText = isParagraphOverlayPinned
        let showsEditableFallback = canEditOriginalText && !hasOriginalText
        let showsOriginalEditorToggle = canEditOriginalText && shouldHideOriginalText && hasOriginalText && !isManualInputFallback

        let showsOriginalTextRegion: Bool = if shouldHideOriginalText {
            showsEditableFallback || isManualInputFallback || (canEditOriginalText && isOriginalEditorExpanded)
        } else {
            hasOriginalText || canEditOriginalText
        }
        let usesEditableOriginalText = canEditOriginalText && showsOriginalTextRegion

        return Decision(
            showsOriginalTextRegion: showsOriginalTextRegion,
            usesEditableOriginalText: usesEditableOriginalText,
            showsOriginalEditorToggle: showsOriginalEditorToggle,
            hidesOriginalTextRegion: shouldHideOriginalText && !showsOriginalTextRegion
        )
    }
}

enum WordOverlayTextSelectionPolicy {
    static func usesSelectableText(
        isWordOverlayMode: Bool,
        showsWordOverlayControls: Bool
    ) -> Bool {
        isWordOverlayMode && showsWordOverlayControls
    }
}

enum WordOverlayHeaderLayoutPolicy {
    struct Metrics: Equatable {
        let identityGroupMaxWidth: CGFloat
        let titleMaxWidth: CGFloat
        let allowsPhoneticBadgeHorizontalCompression: Bool
    }

    static func resolve(
        panelWidth: CGFloat,
        horizontalPadding: CGFloat,
        controlGroupWidth: CGFloat,
        gapBetweenIdentityAndControls: CGFloat
    ) -> Metrics {
        let contentWidth = max(0, panelWidth - horizontalPadding * 2)
        let reservedControlWidth = max(0, controlGroupWidth) + max(0, gapBetweenIdentityAndControls)
        let identityGroupMaxWidth = max(0, contentWidth - reservedControlWidth)

        return Metrics(
            identityGroupMaxWidth: identityGroupMaxWidth,
            titleMaxWidth: identityGroupMaxWidth,
            allowsPhoneticBadgeHorizontalCompression: false
        )
    }

    static func displayedPhonetic(_ phonetic: String?) -> String? {
        guard let phonetic else { return nil }
        let trimmed = phonetic.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
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

    static func stableFontSize(preferredFontSize: CGFloat) -> CGFloat {
        min(normalizedPreferredFontSize(preferredFontSize) * preferredUpscaleFactor, maxFontSize)
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

extension EnvironmentValues {
    @Entry var translationPasteboard: NSPasteboard = .general
}

struct CopyButton: View {
    @Environment(\.translationPasteboard) private var pasteboard
    let text: String
    var usesSubtleHeaderStyle = false
    @State private var copied = false
    @State private var isHovered = false

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
                        .fill(backgroundColor)
                )
                .contentShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
                .scaleEffect(copied ? 1.1 : 1.0)
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .help(L("Copy to clipboard"))
    }

    private var backgroundColor: Color {
        if copied {
            return Color(red: 0.2, green: 0.78, blue: 0.35).opacity(0.12)
        }
        if usesSubtleHeaderStyle {
            return isHovered ? Color.secondary.opacity(0.10) : Color.clear
        }
        return Color.secondary.opacity(0.08)
    }

    private func copyToClipboard(_ text: String) {
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }
}

private struct ParagraphHeaderIcon: View {
    let systemImage: String

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast
    @State private var isHovered = false

    var body: some View {
        Image(systemName: systemImage)
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(isHovered ? Color.primary : Color.secondary)
            .frame(width: 20, height: 20)
            .background {
                Circle()
                    .fill(isHovered ? hoverFillColor : Color.clear)
            }
            .overlay {
                Circle()
                    .stroke(
                        isHovered ? hoverStrokeColor : Color.clear,
                        lineWidth: 0.5
                    )
            }
            .contentShape(Circle())
            .onHover { isHovered = $0 }
            .accessibilityHidden(true)
    }

    private var hoverFillColor: Color {
        if colorSchemeContrast == .increased {
            return colorScheme == .dark
                ? Color.white.opacity(0.14)
                : Color.black.opacity(0.09)
        }
        return colorScheme == .dark
            ? Color.white.opacity(0.10)
            : Color.black.opacity(0.055)
    }

    private var hoverStrokeColor: Color {
        Color.secondary.opacity(colorSchemeContrast == .increased ? 0.32 : 0.16)
    }
}

private struct SelectableTextView: NSViewRepresentable {
    let text: String
    let font: NSFont
    let textColor: NSColor
    let preferredLineHeight: CGFloat
    var onWordDoubleClick: ((String, CGPoint) -> Void)? = nil

    func makeNSView(context: Context) -> SelectableTextContainerView {
        let textView = SelectableTextContainerView(frame: .zero)
        updateNSView(textView, context: context)
        return textView
    }

    func updateNSView(_ textView: SelectableTextContainerView, context: Context) {
        textView.textView.onWordDoubleClick = onWordDoubleClick
        textView.update(
            text: text,
            font: font,
            textColor: textColor,
            preferredLineHeight: preferredLineHeight
        )
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: SelectableTextContainerView, context: Context) -> CGSize? {
        guard let width = proposal.width, width.isFinite, width > 0 else {
            return CGSize(width: 0, height: font.pointSize)
        }

        return nsView.measuredSize(forWidth: width)
    }
}

private struct EditableParagraphTextView: NSViewRepresentable {
    let text: String
    let placeholder: String
    let font: NSFont
    let textColor: NSColor
    let placeholderColor: NSColor
    let preferredLineHeight: CGFloat
    let minimumHeight: CGFloat
    var onWordDoubleClick: ((String, CGPoint) -> Void)? = nil
    let onTextChange: (String) -> Void
    let onSubmit: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onTextChange: onTextChange, onSubmit: onSubmit)
    }

    func makeNSView(context: Context) -> EditableParagraphTextContainerView {
        let textView = EditableParagraphTextContainerView(frame: .zero)
        updateNSView(textView, context: context)
        return textView
    }

    func updateNSView(_ textView: EditableParagraphTextContainerView, context: Context) {
        textView.textView.onWordDoubleClick = onWordDoubleClick
        context.coordinator.onTextChange = onTextChange
        context.coordinator.onSubmit = onSubmit
        textView.update(
            text: text,
            placeholder: placeholder,
            font: font,
            textColor: textColor,
            placeholderColor: placeholderColor,
            preferredLineHeight: preferredLineHeight,
            minimumHeight: minimumHeight,
            coordinator: context.coordinator
        )
        textView.focusIfNeeded()
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: EditableParagraphTextContainerView, context: Context) -> CGSize? {
        guard let width = proposal.width, width.isFinite, width > 0 else {
            return CGSize(width: 0, height: preferredLineHeight)
        }

        return nsView.measuredSize(forWidth: width)
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var onTextChange: (String) -> Void
        var onSubmit: () -> Void

        init(
            onTextChange: @escaping (String) -> Void,
            onSubmit: @escaping () -> Void
        ) {
            self.onTextChange = onTextChange
            self.onSubmit = onSubmit
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            if let containerView = textView.superview as? EditableParagraphTextContainerView {
                containerView.handleTextDidChange()
            }
            onTextChange(textView.string)
        }

        func textView(_ textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            if commandSelector == #selector(NSResponder.insertNewline(_:)) {
                if NSApp.currentEvent?.modifierFlags.contains(.shift) == true {
                    return false
                }
                onSubmit()
                return true
            }

            return false
        }
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
    let textView = WordLookupTextView(frame: .zero)
    private var cachedMeasurement: (width: CGFloat, height: CGFloat)?

    override var isFlipped: Bool { true }

    override init(frame frameRect: NSRect) {
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
        let attributedText = makeAttributedString(
            text: text,
            font: font,
            textColor: textColor,
            preferredLineHeight: preferredLineHeight
        )
        guard let storage = textView.textStorage, !storage.isEqual(to: attributedText) else { return }
        storage.setAttributedString(attributedText)
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

private final class EditableParagraphTextContainerView: NSView {
    let textView = WordLookupTextView(frame: .zero)
    private let placeholderLabel: NSTextField
    private var cachedMeasurement: (width: CGFloat, height: CGFloat)?
    private var preferredLineHeight: CGFloat = 20
    private var minimumHeight: CGFloat = 0
    private var didRequestInitialFocus = false

    override var isFlipped: Bool { true }

    override init(frame frameRect: NSRect) {
        placeholderLabel = NSTextField(labelWithString: "")
        super.init(frame: frameRect)
        configureTextView()
        configurePlaceholderLabel()
        addSubview(textView)
        addSubview(placeholderLabel)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func update(
        text: String,
        placeholder: String,
        font: NSFont,
        textColor: NSColor,
        placeholderColor: NSColor,
        preferredLineHeight: CGFloat,
        minimumHeight: CGFloat,
        coordinator: EditableParagraphTextView.Coordinator
    ) {
        self.preferredLineHeight = preferredLineHeight
        self.minimumHeight = minimumHeight
        textView.delegate = coordinator
        textView.font = font
        textView.textColor = textColor
        textView.typingAttributes = typingAttributes(
            font: font,
            textColor: textColor,
            preferredLineHeight: preferredLineHeight
        )
        placeholderLabel.stringValue = placeholder
        placeholderLabel.font = font
        placeholderLabel.textColor = placeholderColor

        if textView.string != text {
            textView.textStorage?.setAttributedString(
                makeAttributedString(
                    text: text,
                    font: font,
                    textColor: textColor,
                    preferredLineHeight: preferredLineHeight
                )
            )
        }
        updatePlaceholderVisibility()
        cachedMeasurement = nil
        invalidateIntrinsicContentSize()
        needsLayout = true
    }

    func handleTextDidChange() {
        updatePlaceholderVisibility()
        cachedMeasurement = nil
        invalidateIntrinsicContentSize()
        needsLayout = true
    }

    func focusIfNeeded() {
        guard !didRequestInitialFocus else { return }
        didRequestInitialFocus = true

        DispatchQueue.main.async { [weak self] in
            self?.focusTextView()
        }
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
        textView.frame = CGRect(x: 0, y: 0, width: width, height: height)
        placeholderLabel.frame = CGRect(x: 0, y: 0, width: width, height: preferredLineHeight)
    }

    override func mouseDown(with event: NSEvent) {
        focusTextView()
        textView.mouseDown(with: event)
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        let hitView = super.hitTest(point)
        return hitView === placeholderLabel ? self : hitView
    }

    private func measuredHeight(forWidth width: CGFloat) -> CGFloat {
        if let cachedMeasurement,
           abs(cachedMeasurement.width - width) <= 0.5 {
            return cachedMeasurement.height
        }

        guard let textContainer = textView.textContainer,
              let layoutManager = textView.layoutManager else {
            return preferredLineHeight
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

        var maxLineFragmentY: CGFloat = 0
        layoutManager.enumerateLineFragments(forGlyphRange: glyphRange) { _, usedRect, _, _, _ in
            maxLineFragmentY = max(maxLineFragmentY, usedRect.maxY)
        }

        if layoutManager.extraLineFragmentTextContainer == textContainer {
            maxLineFragmentY = max(maxLineFragmentY, layoutManager.extraLineFragmentRect.maxY)
        }

        let resolvedHeight = max(minimumHeight, max(preferredLineHeight, ceil(maxLineFragmentY)))
        cachedMeasurement = (width, resolvedHeight)
        return resolvedHeight
    }

    private func configureTextView() {
        textView.isEditable = true
        textView.isSelectable = true
        textView.isRichText = false
        textView.allowsUndo = true
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

    private func configurePlaceholderLabel() {
        placeholderLabel.isBezeled = false
        placeholderLabel.drawsBackground = false
        placeholderLabel.isEditable = false
        placeholderLabel.isSelectable = false
        placeholderLabel.lineBreakMode = .byTruncatingTail
        placeholderLabel.maximumNumberOfLines = 1
        placeholderLabel.alphaValue = 0.75
        placeholderLabel.isEnabled = false
    }

    private func focusTextView() {
        guard let window else { return }
        window.makeKey()
        window.makeFirstResponder(textView)
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

    private func typingAttributes(
        font: NSFont,
        textColor: NSColor,
        preferredLineHeight: CGFloat
    ) -> [NSAttributedString.Key: Any] {
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.minimumLineHeight = preferredLineHeight
        paragraphStyle.maximumLineHeight = preferredLineHeight
        paragraphStyle.lineBreakMode = .byWordWrapping

        return [
            .font: font,
            .foregroundColor: textColor,
            .paragraphStyle: paragraphStyle,
        ]
    }

    private func updatePlaceholderVisibility() {
        placeholderLabel.isHidden = !textView.string.isEmpty
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

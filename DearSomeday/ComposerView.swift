//
//  ComposerView.swift
//  DearSomeday
//
//  MVP postcard creation flow:
//   1. Pick 1-6 photos
//   2. Choose a ranked template and adjust photo crops inside slots
//   3. Write the postcard back and choose text styling
//   4. Add optional typed/current location, choose unlock date, seal locally
//

import SwiftUI
import PhotosUI
import UIKit

private struct PostcardCanvasSizePreferenceKey: PreferenceKey {
    static var defaultValue: CGSize = .zero

    static func reduce(value: inout CGSize, nextValue: () -> CGSize) {
        let next = nextValue()
        if next.width > 0, next.height > 0 {
            value = next
        }
    }
}

private struct TemplateCanvasFramePreferenceKey: PreferenceKey {
    static var defaultValue: CGRect = .zero

    static func reduce(value: inout CGRect, nextValue: () -> CGRect) {
        let next = nextValue()
        if !next.isEmpty {
            value = next
        }
    }
}

private struct TemplatePickerAnchorPreferenceKey: PreferenceKey {
    static var defaultValue: CGRect?

    static func reduce(value: inout CGRect?, nextValue: () -> CGRect?) {
        value = nextValue() ?? value
    }
}

private struct StampPickerAnchorPreferenceKey: PreferenceKey {
    static var defaultValue: CGRect?

    static func reduce(value: inout CGRect?, nextValue: () -> CGRect?) {
        value = nextValue() ?? value
    }
}

struct ComposerView: View {

    let services: AppServices

    /// Called on a successful seal, before dismissal — the timeline uses it to
    /// trigger the first-seal notification priming (§7.1).
    var onSealed: (() -> Void)? = nil

    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion

    @State private var step: Step = .photos
    @State private var photos: [CreationPhoto] = []
    @State private var addedIdentifiers: Set<String> = []
    @State private var addedFingerprints: Set<String> = []
    @State private var pickerItems: [PhotosPickerItem] = []
    @State private var isImportingPhotos = false
    @State private var deletingPhotoIDs: Set<UUID> = []

    @State private var selectedTemplate: CardTemplate?
    @State private var assignments: [SlotAssignment] = []
    @State private var selectedSlotID: String?
    @State private var templateCanvasFrame: CGRect = .zero
    @State private var isTemplatePickerPresented = false
    @State private var photoBarriersEnabled = true

    @State private var title = ""
    @State private var backText = ""
    @State private var backFontId = PostcardBackFont.defaultFont.id
    @State private var lockedBackFontSizes: [String: CGFloat] = [
        PostcardBackFont.defaultFont.id: PostcardBackFont.normalPointSize
    ]
    @State private var backCanvasSize: CGSize = .zero
    @State private var messageHasNoMoreRoom = false
    @State private var fontSelectionMessage: String?
    @State private var backTextColorHex = PostcardBackTextColor.defaultColor.hex
    @State private var customBackTextColor = Color(hex: PostcardBackTextColor.defaultColor.hex)
    @State private var selectedStampID: String?
    @State private var isStampPickerPresented = false
    @State private var hasPlacedStamp = false
    @State private var stampMotion: StampMotion = .settled
    @State private var stampOpacity: Double = 1
    @State private var stampAnimationTask: Task<Void, Never>?
    @State private var locationLabel = ""
    @StateObject private var currentLocation = CurrentLocationResolver()
    @State private var chosenDate = ComposerView.defaultUnlockDate()

    @State private var isSealing = false
    @State private var committed = false
    @State private var errorMessage: String?

    @FocusState private var focusedField: Field?

    private enum Field { case title, backText, location }

    private enum StampMotion {
        case settled
        case lifted
        case pressed
    }

    private enum Step: Int, CaseIterable {
        case photos
        case template
        case back
        case logistics

        var title: String {
            switch self {
            case .photos: return "Photos"
            case .template: return "Template"
            case .back: return "Back"
            case .logistics: return "Finish"
            }
        }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                stepHeader
                Divider()
                content
                Divider()
                footer
            }
            .navigationTitle("New Postcard")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .font(Tokens.Font.button)
                        .disabled(isSealing)
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") { focusedField = nil }
                        .font(Tokens.Font.button)
                }
            }
        }
        .appBackground(
            imageName: "PostcardCreationBackground",
            tintOpacity: 0.68
        )
        .coordinateSpace(name: "composerRoot")
        .simultaneousGesture(cropEditingDismissGesture)
        .overlayPreferenceValue(TemplatePickerAnchorPreferenceKey.self) { anchor in
            templatePickerOverlay(anchor: anchor)
        }
        .overlayPreferenceValue(StampPickerAnchorPreferenceKey.self) { anchor in
            stampPickerOverlay(anchor: anchor)
        }
        .interactiveDismissDisabled(isSealing)
        .onChange(of: pickerItems) { _, items in
            Task { await importPicked(items) }
        }
        .onDisappear {
            stampAnimationTask?.cancel()
            if !committed {
                services.creationService.discard(photos)
            }
        }
    }

    // MARK: - Layout

    private var stepHeader: some View {
        HStack(spacing: 8) {
            ForEach(Step.allCases, id: \.self) { item in
                VStack(spacing: 6) {
                    Text("\(item.rawValue + 1)")
                        .font(Tokens.Font.caption.weight(.semibold))
                        .frame(width: 24, height: 24)
                        .background(Circle().fill(item.rawValue <= step.rawValue ? .blue : .gray.opacity(0.25)))
                        .foregroundStyle(Tokens.Color.chromeText)
                    Text(item.title)
                        .font(Tokens.Font.caption2)
                        .foregroundStyle(Tokens.Color.chromeText)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .padding()
    }

    @ViewBuilder
    private var content: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                switch step {
                case .photos:
                    photoSelection
                case .template:
                    templateSelection
                case .back:
                    backEditor
                case .logistics:
                    logistics
                }

                if let errorMessage {
                    Text(errorMessage)
                        .font(Tokens.Font.footnote)
                        .foregroundStyle(Tokens.Color.chromeText)
                }
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .scrollContentBackground(.hidden)
        .background(.clear)
        .scrollDismissesKeyboard(.interactively)
        .scrollDisabled(isEditingPhotoCrop)
    }

    private var footer: some View {
        HStack {
            Button("Back") { goBack() }
                .font(Tokens.Font.button)
                .disabled(step == .photos || isSealing)

            Spacer()

            Button(step == .logistics ? "Seal" : "Next") {
                if step == .logistics {
                    Task { await seal() }
                } else {
                    goNext()
                }
            }
            .font(Tokens.Font.button)
            .buttonStyle(.borderedProminent)
            .tint(Tokens.Color.inkEspresso)
            .foregroundStyle(Tokens.Color.paperCream)
            .disabled(!canContinue || isSealing)
        }
        .padding()
    }

    // MARK: - Step 1: photos

    private var photoSelection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("\(photos.count)/\(ComposerLogic.maxPhotos) photos selected")
                .font(Tokens.Font.headline)

            if photos.isEmpty {
                emptyPhotoPicker
            } else {
                selectedPhotoGrid

                photoPicker {
                    Label("Add more photos", systemImage: "photo.on.rectangle")
                        .font(Tokens.Font.button)
                }
                .buttonStyle(.bordered)
                .disabled(photos.count >= ComposerLogic.maxPhotos)
            }

        }
    }

    private var selectedPhotoGrid: some View {
        LazyVGrid(columns: selectedPhotoColumns, spacing: 12) {
            ForEach(Array(photos.enumerated()), id: \.element.id) { index, photo in
                photoThumb(photo, selectionNumber: index + 1)
                    .aspectRatio(1, contentMode: .fit)
            }
        }
    }

    private var selectedPhotoColumns: [GridItem] {
        Array(
            repeating: GridItem(.flexible(), spacing: 12),
            count: 3
        )
    }

    private var emptyPhotoPicker: some View {
        photoPicker {
            VStack(spacing: 12) {
                Image(systemName: "photo.badge.plus")
                    .font(.system(size: 34, weight: .semibold))
                    .foregroundStyle(.blue)
                Text("No photos selected")
                    .font(Tokens.Font.button.weight(.semibold))
                Text("Tap here to choose up to 6")
                    .font(Tokens.Font.button)
                    .foregroundStyle(Tokens.Color.chromeText)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 190)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(Tokens.Color.paperCream.opacity(0.8))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(.secondary.opacity(0.35), style: StrokeStyle(lineWidth: 1, dash: [7]))
            )
            .contentShape(RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(.plain)
        .disabled(photos.count >= ComposerLogic.maxPhotos)
    }

    private func photoPicker<Label: View>(@ViewBuilder label: () -> Label) -> some View {
        PhotosPicker(
            selection: $pickerItems,
            maxSelectionCount: ComposerLogic.maxPhotos,
            selectionBehavior: .ordered,
            matching: .images,
            label: {
                if isImportingPhotos {
                    HStack(spacing: 8) {
                        ProgressView()
                        Text("Adding photos...")
                            .font(Tokens.Font.button)
                    }
                } else {
                    label()
                }
            }
        )
        .disabled(isImportingPhotos)
    }

    private func photoThumb(_ photo: CreationPhoto, selectionNumber: Int) -> some View {
        GeometryReader { proxy in
            let side = min(proxy.size.width, proxy.size.height)
            let shape = RoundedRectangle(cornerRadius: 8, style: .continuous)

            ZStack(alignment: .topTrailing) {
                Group {
                    if let image = photo.thumbnail {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFill()
                    } else {
                        Rectangle().fill(.gray.opacity(0.3))
                    }
                }
                .frame(width: side, height: side)
                .clipShape(shape)

                shape
                    .stroke(.white, lineWidth: 2)

                Text("\(selectionNumber)")
                    .font(Tokens.Font.caption.weight(.bold))
                    .foregroundStyle(Tokens.Color.chromeText)
                    .frame(width: 24, height: 24)
                    .background(Circle().fill(.blue))
                    .shadow(radius: 2, y: 1)
                    .padding(6)
                    .frame(width: side, height: side, alignment: .topLeading)

                Button {
                    beginRemoving(photo)
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(.white, .black.opacity(0.95))
                        .font(.system(size: 30, weight: .bold))
                }
                .buttonStyle(.plain)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
                .accessibilityLabel("Remove photo")
                .disabled(deletingPhotoIDs.contains(photo.id))
                .frame(width: side, height: side, alignment: .topTrailing)
            }
            .frame(width: side, height: side)
            .background(Color(.secondarySystemBackground))
            .clipShape(shape)
            .scaleEffect(deletingPhotoIDs.contains(photo.id) ? 0.01 : 1)
            .opacity(deletingPhotoIDs.contains(photo.id) ? 0 : 1)
        }
        .aspectRatio(1, contentMode: .fit)
    }

    // MARK: - Step 2: template

    private var templateSelection: some View {
        VStack(alignment: .leading, spacing: 16) {
            let ranked = rankedTemplates
            if ranked.isEmpty {
                Text("Choose photos first.")
                    .foregroundStyle(Tokens.Color.chromeText)
            } else {
                if let selectedTemplate {
                    HStack(spacing: Tokens.Space.sm) {
                        Button {
                            withAnimation(.spring(response: 0.28, dampingFraction: 0.84)) {
                                isTemplatePickerPresented = true
                            }
                        } label: {
                            HStack(spacing: Tokens.Space.sm) {
                                TemplateLayoutPreview(template: selectedTemplate)
                                    .frame(width: 28, height: 35)

                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Template")
                                        .font(Tokens.Font.caption2)
                                        .foregroundStyle(.secondary)
                                    Text(selectedTemplate.name)
                                        .font(Tokens.Font.subheadline.weight(.semibold))
                                        .lineLimit(1)
                                }

                                Spacer(minLength: Tokens.Space.xs)

                                Image(systemName: "chevron.down")
                                    .font(Tokens.Font.caption.weight(.semibold))
                                    .foregroundStyle(.secondary)
                            }
                            .foregroundStyle(Tokens.Color.chromeText)
                            .padding(.horizontal, Tokens.Space.sm)
                            .padding(.vertical, Tokens.Space.xxs)
                            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                            .background(
                                RoundedRectangle(cornerRadius: Tokens.Radius.subtle, style: .continuous)
                                    .fill(Tokens.Color.paperCream.opacity(0.82))
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: Tokens.Radius.subtle, style: .continuous)
                                    .stroke(Tokens.Color.chromeDivider, lineWidth: 1)
                            )
                            .contentShape(RoundedRectangle(cornerRadius: Tokens.Radius.subtle, style: .continuous))
                        }
                        .buttonStyle(.plain)
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel("Choose template, " + selectedTemplate.name + " selected")
                        .accessibilityHint("Opens the template gallery")
                        .background {
                            GeometryReader { proxy in
                                Color.clear.preference(
                                    key: TemplatePickerAnchorPreferenceKey.self,
                                    value: proxy.frame(in: .named("composerRoot"))
                                )
                            }
                        }

                        Button {
                            photoBarriersEnabled.toggle()
                        } label: {
                            Image(systemName: "rectangle.split.2x1")
                                .font(.system(size: 17, weight: .semibold))
                                .frame(width: 44, height: 44)
                                .background(
                                    RoundedRectangle(cornerRadius: Tokens.Radius.subtle, style: .continuous)
                                        .fill(
                                            photoBarriersEnabled
                                                ? Color.blue.opacity(0.14)
                                                : Tokens.Color.paperCream.opacity(0.82)
                                        )
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: Tokens.Radius.subtle, style: .continuous)
                                        .stroke(
                                            photoBarriersEnabled ? Color.blue : Tokens.Color.chromeDivider,
                                            lineWidth: photoBarriersEnabled ? 2 : 1
                                        )
                                )
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(photoBarriersEnabled ? Color.blue : Tokens.Color.chromeText)
                        .accessibilityLabel("Barriers between photos")
                        .accessibilityValue(photoBarriersEnabled ? "On" : "Off")
                    }

                    TemplateCanvasView(
                        template: selectedTemplate,
                        photos: photos,
                        assignments: $assignments,
                        selectedSlotID: $selectedSlotID,
                        showsBarriers: photoBarriersEnabled
                    )
                    .aspectRatio(PostcardCanvasMetrics.aspectRatio, contentMode: .fit)
                    .frame(maxWidth: PostcardCanvasMetrics.maxWidth)
                    .background {
                        GeometryReader { proxy in
                            Color.clear.preference(
                                key: TemplateCanvasFramePreferenceKey.self,
                                value: proxy.frame(in: .named("composerRoot"))
                            )
                        }
                    }
                    .frame(maxWidth: .infinity)

                    if selectedSlotID != nil {
                        Button("Reset Crop") {
                            resetSelectedCrop()
                        }
                        .font(Tokens.Font.button)
                        .buttonStyle(.bordered)
                        .transition(.opacity)
                    }
                }
            }
        }
        .onAppear { ensureTemplateSelection() }
        .onPreferenceChange(TemplateCanvasFramePreferenceKey.self) {
            templateCanvasFrame = $0
        }
    }

    private var isEditingPhotoCrop: Bool {
        step == .template && selectedSlotID != nil
    }

    private var cropEditingDismissGesture: some Gesture {
        SpatialTapGesture(coordinateSpace: .named("composerRoot"))
            .onEnded { value in
                guard isEditingPhotoCrop else { return }
                if !templateCanvasFrame.contains(value.location) {
                    selectedSlotID = nil
                }
            }
    }

    @ViewBuilder
    private func templatePickerOverlay(anchor: CGRect?) -> some View {
        GeometryReader { proxy in
            if isTemplatePickerPresented, step == .template, let sourceFrame = anchor {
                let screenMargin: CGFloat = 12
                let arrowWidth: CGFloat = 20
                let paletteWidth = min(CGFloat(340), max(CGFloat(240), proxy.size.width - screenMargin * 2))
                let minimumX = screenMargin
                let maximumX = max(minimumX, proxy.size.width - paletteWidth - screenMargin)
                let paletteX = min(
                    max(sourceFrame.midX - paletteWidth / 2, minimumX),
                    maximumX
                )
                let arrowX = min(
                    max(sourceFrame.midX - paletteX - arrowWidth / 2, 14),
                    paletteWidth - arrowWidth - 14
                )

                ZStack(alignment: .topLeading) {
                    Color.black.opacity(0.001)
                        .ignoresSafeArea()
                        .contentShape(Rectangle())
                        .onTapGesture {
                            withAnimation(.easeOut(duration: 0.16)) {
                                isTemplatePickerPresented = false
                            }
                        }
                        .accessibilityHidden(true)

                    VStack(alignment: .leading, spacing: 0) {
                        StampPopoverArrow()
                            .fill(.regularMaterial)
                            .frame(width: arrowWidth, height: 11)
                            .padding(.leading, arrowX)

                        TemplatePickerPopover(
                            templates: rankedTemplates,
                            selectedTemplateID: selectedTemplate?.id,
                            width: paletteWidth
                        ) { template in
                            selectTemplate(template)
                            withAnimation(.easeOut(duration: 0.16)) {
                                isTemplatePickerPresented = false
                            }
                        }
                        .background(
                            .regularMaterial,
                            in: RoundedRectangle(cornerRadius: 24, style: .continuous)
                        )
                        .shadow(color: .black.opacity(0.18), radius: 18, y: 8)
                    }
                    .environment(\.colorScheme, .light)
                    .frame(width: paletteWidth, alignment: .leading)
                    .offset(x: paletteX, y: sourceFrame.maxY - 55)
                    .transition(
                        .scale(scale: 0.94, anchor: .topTrailing)
                            .combined(with: .opacity)
                    )
                }
            }
        }
    }

    private var rankedTemplates: [CardTemplate] {
        TemplatePicker.ranked(TemplatePicker.all, photoAspects: photos.map(\.aspect))
    }

    // MARK: - Step 3: back

    private var backEditor: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Write the back")
                .font(Tokens.Font.headline)

            TextField("Title (optional)", text: $title)
                .textFieldStyle(.roundedBorder)
                .focused($focusedField, equals: .title)
                .onChange(of: title) { _, new in
                    if new.count > ComposerLogic.maxTitleLength {
                        title = String(new.prefix(ComposerLogic.maxTitleLength))
                    }
                }

            ZStack(alignment: .topLeading) {
                Image(hasPlacedStamp ? "PostcardBackBlank" : "PostcardBack")
                    .resizable()
                    .aspectRatio(PostcardCanvasMetrics.aspectRatio, contentMode: .fit)
                    .overlay {
                        RoundedRectangle(cornerRadius: 2)
                            .stroke(.gray.opacity(0.4), lineWidth: 1)
                    }

                PostcardMessageTextView(
                    text: $backText,
                    font: selectedBackFont.uiFont(pointSize: selectedBackFontPointSize),
                    textColor: UIColor(Color(hex: backTextColorHex)),
                    isEditable: true,
                    validationFonts: lockedBackFonts,
                    adaptiveMinimumPointSize: nil,
                    onCapacityChange: { messageHasNoMoreRoom = $0 }
                )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .clipped()
                    .focused($focusedField, equals: .backText)
                    .onChange(of: backText) { old, new in
                        if new.count > ComposerLogic.maxMessageLength {
                            backText = String(new.prefix(ComposerLogic.maxMessageLength))
                        }
                        if new.count < old.count {
                            messageHasNoMoreRoom = false
                            fontSelectionMessage = nil
                        }
                    }

                if backText.isEmpty {
                    Text("Your message")
                        .font(selectedBackFont.font(pointSize: selectedBackFontPointSize))
                        .foregroundStyle(Color(hex: backTextColorHex).opacity(0.35))
                        .padding(.horizontal, 24)
                        .padding(.top, 24)
                        .allowsHitTesting(false)
                }

                if selectedStamp == nil {
                    GeometryReader { proxy in
                        let frame = PostcardBackLayout.stampFrame(in: proxy.size)
                        Text("click to choose stamp...")
                            .font(Tokens.Font.caption2)
                            .foregroundStyle(Color.secondary.opacity(0.68))
                            .multilineTextAlignment(.center)
                            .lineLimit(3)
                            .minimumScaleFactor(0.72)
                            .padding(4)
                            .frame(width: frame.width, height: frame.height)
                            .position(x: frame.midX, y: frame.midY)
                    }
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
                }

                if let selectedStamp {
                    GeometryReader { proxy in
                        let frame = PostcardBackLayout.stampFrame(in: proxy.size)
                        PostcardPlacedStampImage(
                            option: selectedStamp,
                            size: frame.size
                        )
                            .scaleEffect(stampScale, anchor: .bottomLeading)
                            .offset(y: stampVerticalOffset(for: frame))
                            .opacity(stampOpacity)
                            .position(x: frame.midX, y: frame.midY)
                    }
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
                }

                GeometryReader { proxy in
                    let frame = PostcardBackLayout.stampFrame(in: proxy.size)
                    let canvasFrame = proxy.frame(in: .named("composerRoot"))
                    let anchorFrame = frame.offsetBy(
                        dx: canvasFrame.minX,
                        dy: canvasFrame.minY
                    )
                    Button {
                        focusedField = nil
                        withAnimation(.spring(response: 0.28, dampingFraction: 0.84)) {
                            isStampPickerPresented = true
                        }
                    } label: {
                        Color.clear
                            .frame(width: frame.width, height: frame.height)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .position(x: frame.midX, y: frame.midY)
                    .accessibilityLabel(
                        selectedStamp.map { "Change stamp, \($0.accessibilityLabel)" }
                            ?? "Choose stamp, required"
                    )
                    .accessibilityHint("Opens the stamp palette")
                    .preference(
                        key: StampPickerAnchorPreferenceKey.self,
                        value: anchorFrame
                    )
                }
            }
            .aspectRatio(PostcardCanvasMetrics.aspectRatio, contentMode: .fit)
            .frame(maxWidth: PostcardCanvasMetrics.maxWidth)
            .background {
                GeometryReader { proxy in
                    Color.clear.preference(
                        key: PostcardCanvasSizePreferenceKey.self,
                        value: proxy.size
                    )
                }
            }
            .clipped()
            .shadow(
                color: Tokens.Shadow.raised.color,
                radius: Tokens.Shadow.raised.radius,
                y: Tokens.Shadow.raised.y
            )
            .frame(maxWidth: .infinity)
            .onPreferenceChange(PostcardCanvasSizePreferenceKey.self) {
                backCanvasSize = $0
            }

            if messageHasNoMoreRoom {
                Text("No more room")
                    .font(Tokens.Font.caption)
                    .foregroundStyle(.red)
                    .frame(maxWidth: PostcardCanvasMetrics.maxWidth, alignment: .trailing)
                    .frame(maxWidth: .infinity)
            }

            fontOptions

            HStack {
                Text("Color")
                Spacer()
                ForEach(PostcardBackTextColor.allCases) { color in
                    Button {
                        selectBackTextColor(color.hex)
                    } label: {
                        Circle()
                            .fill(Color(hex: color.hex))
                            .frame(width: 28, height: 28)
                            .overlay(Circle().stroke(backTextColorHex == color.hex ? .blue : .clear, lineWidth: 3))
                    }
                    .accessibilityLabel(color.name)
                }

                ColorPicker("Custom color", selection: customBackTextColorBinding, supportsOpacity: false)
                    .labelsHidden()
                    .frame(width: 34)
                    .accessibilityLabel("Custom color")
            }
        }
    }

    private var fontOptions: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Font")

            ForEach(PostcardBackFont.allCases) { font in
                Button {
                    selectBackFont(font)
                } label: {
                    HStack {
                        Text(font.name)
                            .font(font.previewFont)
                        Spacer()
                        if backFontId == font.id {
                            Image(systemName: "checkmark")
                                .font(Tokens.Font.caption.weight(.bold))
                        }
                    }
                    .foregroundStyle(Tokens.Color.chromeText)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(backFontId == font.id ? Color.blue.opacity(0.1) : Color(.secondarySystemBackground))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(backFontId == font.id ? .blue : .secondary.opacity(0.2), lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
                .accessibilityLabel(font.name)
            }

            if let fontSelectionMessage {
                Text(fontSelectionMessage)
                    .font(Tokens.Font.caption)
                    .foregroundStyle(.red)
            }
        }
    }

    private var selectedStamp: StampOption? {
        StampCatalog.option(withID: selectedStampID)
    }

    @ViewBuilder
    private func stampPickerOverlay(anchor: CGRect?) -> some View {
        GeometryReader { proxy in
            if isStampPickerPresented, let sourceFrame = anchor {
                let paletteWidth: CGFloat = 264
                let screenMargin: CGFloat = 12
                let arrowWidth: CGFloat = 20
                let minimumX = screenMargin
                let maximumX = max(minimumX, proxy.size.width - paletteWidth - screenMargin)
                let paletteX = min(
                    max(sourceFrame.midX - paletteWidth / 2, minimumX),
                    maximumX
                )
                let arrowX = min(
                    max(sourceFrame.midX - paletteX - arrowWidth / 2, 14),
                    paletteWidth - arrowWidth - 14
                )

                ZStack(alignment: .topLeading) {
                    Color.black.opacity(0.001)
                        .ignoresSafeArea()
                        .contentShape(Rectangle())
                        .onTapGesture {
                            withAnimation(.easeOut(duration: 0.16)) {
                                isStampPickerPresented = false
                            }
                        }
                        .accessibilityHidden(true)

                    VStack(alignment: .leading, spacing: 0) {
                        StampPopoverArrow()
                            .fill(.regularMaterial)
                            .frame(width: arrowWidth, height: 11)
                            .padding(.leading, arrowX)

                        StampPickerPopover(selectedStampID: selectedStampID) { option in
                            selectStamp(option)
                        }
                        .background(
                            .regularMaterial,
                            in: RoundedRectangle(cornerRadius: 24, style: .continuous)
                        )
                        .shadow(color: .black.opacity(0.18), radius: 18, y: 8)
                    }
                    .frame(width: paletteWidth, alignment: .leading)
                    .offset(x: paletteX, y: sourceFrame.maxY - 55)
                    .transition(
                        .scale(scale: 0.94, anchor: .topTrailing)
                            .combined(with: .opacity)
                    )
                }
            }
        }
    }

    private var stampScale: CGFloat {
        switch stampMotion {
        case .settled: return 1
        case .lifted: return 1.08
        case .pressed: return 0.94
        }
    }

    private func stampVerticalOffset(for frame: CGRect) -> CGFloat {
        switch stampMotion {
        case .settled: return 0
        case .lifted: return -frame.height * 0.34
        case .pressed: return frame.height * 0.025
        }
    }

    private func selectStamp(_ option: StampOption) {
        stampAnimationTask?.cancel()
        selectedStampID = option.id
        stampMotion = .settled

        if accessibilityReduceMotion {
            hasPlacedStamp = true
            stampOpacity = 0
            withAnimation(.easeInOut(duration: 0.2)) {
                stampOpacity = 1
            }
            return
        }

        stampOpacity = 1
        stampAnimationTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 16_000_000)
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.16)) {
                stampMotion = .lifted
            }

            try? await Task.sleep(nanoseconds: 160_000_000)
            guard !Task.isCancelled else { return }
            hasPlacedStamp = true
            withAnimation(.easeIn(duration: 0.12)) {
                stampMotion = .pressed
            }

            try? await Task.sleep(nanoseconds: 120_000_000)
            guard !Task.isCancelled else { return }
            withAnimation(.spring(response: 0.24, dampingFraction: 0.66)) {
                stampMotion = .settled
            }
        }
    }

    // MARK: - Step 4: logistics

    private var logistics: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Logistics")
                .font(Tokens.Font.headline)

            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 10) {
                    TextField("Place, optional", text: $locationLabel)
                        .textFieldStyle(.roundedBorder)
                        .focused($focusedField, equals: .location)

                    Button {
                        Task { await useCurrentLocation() }
                    } label: {
                        Label("Current", systemImage: "location")
                            .font(Tokens.Font.button)
                            .frame(height: 36)
                    }
                    .buttonStyle(.bordered)
                    .disabled(currentLocation.isRequesting)
                    .accessibilityLabel("Use Current Location")
                }

                if currentLocation.isRequesting {
                    Label("Finding your current location...", systemImage: "location.fill")
                        .font(Tokens.Font.caption)
                        .foregroundStyle(Tokens.Color.chromeText)
                } else if let message = currentLocation.message {
                    Text(message)
                        .font(Tokens.Font.caption)
                        .foregroundStyle(Tokens.Color.chromeText)
                }
            }

            DatePicker("Unlock", selection: $chosenDate, in: Date()..., displayedComponents: [.date, .hourAndMinute])

            if let selectedTemplate {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Summary")
                        .font(Tokens.Font.subheadline.weight(.semibold))

                    PostcardSummaryTextView(
                        title: title,
                        message: backText,
                        messageFont: selectedBackFont.uiFont(pointSize: selectedBackFontPointSize),
                        messageColor: UIColor(Color(hex: backTextColorHex))
                    )
                    .overlay(alignment: .topLeading) {
                        GeometryReader { proxy in
                            let previewWidth = max((proxy.size.width - 16) / 2, 0)
                            TemplateCanvasView(
                                template: selectedTemplate,
                                photos: photos,
                                assignments: .constant(assignments),
                                selectedSlotID: .constant(nil),
                                showsBarriers: photoBarriersEnabled
                            )
                            .frame(
                                width: previewWidth,
                                height: previewWidth / PostcardCanvasMetrics.aspectRatio
                            )
                            .accessibilityLabel("Postcard front preview")
                        }
                        .allowsHitTesting(false)
                    }

                    if let selectedStamp {
                        HStack(spacing: Tokens.Space.sm) {
                            PostcardStampImage(option: selectedStamp)
                                .frame(width: 42, height: 42)

                            Text("Stamp")
                                .font(Tokens.Font.caption)

                            Spacer()
                        }
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel("Selected \(selectedStamp.accessibilityLabel)")
                    }
                }
                .foregroundStyle(Tokens.Color.chromeText)
            }
        }
    }

    // MARK: - Navigation

    private var canContinue: Bool {
        switch step {
        case .photos:
            return photos.count >= ComposerLogic.minPhotos && photos.count <= ComposerLogic.maxPhotos
        case .template:
            return selectedTemplate != nil && assignments.count == selectedTemplate?.slotCount
        case .back:
            return selectedStamp != nil
        case .logistics:
            return true
        }
    }

    private func goNext() {
        errorMessage = nil
        focusedField = nil
        isTemplatePickerPresented = false
        if step == .photos {
            ensureTemplateSelection()
        }
        guard let next = Step(rawValue: step.rawValue + 1) else { return }
        step = next
    }

    private func goBack() {
        errorMessage = nil
        focusedField = nil
        isTemplatePickerPresented = false
        guard let previous = Step(rawValue: step.rawValue - 1) else { return }
        step = previous
    }

    // MARK: - Photo import

    private func importPicked(_ items: [PhotosPickerItem]) async {
        guard !items.isEmpty, !isImportingPhotos else { return }
        isImportingPhotos = true

        var importedPhotos: [CreationPhoto] = []
        var pendingIdentifiers = addedIdentifiers
        var pendingFingerprints = addedFingerprints

        for item in items {
            guard photos.count + importedPhotos.count < ComposerLogic.maxPhotos else { break }
            let identifier = item.itemIdentifier
            guard PhotoSelectionLogic.canAdd(identifier: identifier, selectedIdentifiers: pendingIdentifiers) else {
                continue
            }
            guard
                let data = try? await item.loadTransferable(type: Data.self),
                let image = UIImage(data: data)
            else { continue }
            let fingerprint = PhotoSelectionLogic.fingerprint(for: data)
            guard PhotoSelectionLogic.canAdd(
                fingerprint: fingerprint,
                selectedFingerprints: pendingFingerprints
            ) else {
                continue
            }
            do {
                let photo = try services.creationService.importPhoto(
                    image,
                    sourceIdentifier: identifier,
                    sourceFingerprint: fingerprint
                )
                importedPhotos.append(photo)
                pendingIdentifiers = PhotoSelectionLogic.identifiers(
                    afterAdding: identifier,
                    to: pendingIdentifiers
                )
                pendingFingerprints = PhotoSelectionLogic.fingerprints(
                    afterAdding: fingerprint,
                    to: pendingFingerprints
                )
            } catch {
                errorMessage = "Couldn’t add one of those photos."
            }
        }

        let updateSelection = {
            photos.append(contentsOf: importedPhotos)
            addedIdentifiers = pendingIdentifiers
            addedFingerprints = pendingFingerprints
        }
        if accessibilityReduceMotion {
            updateSelection()
        } else {
            withAnimation(.easeOut(duration: 0.22)) {
                updateSelection()
            }
        }

        pickerItems = []
        isImportingPhotos = false
        ensureTemplateSelection()
    }

    private func beginRemoving(_ photo: CreationPhoto) {
        guard !deletingPhotoIDs.contains(photo.id) else { return }

        if accessibilityReduceMotion {
            remove(photo)
            return
        }

        withAnimation(.easeInOut(duration: 0.3)) {
            _ = deletingPhotoIDs.insert(photo.id)
        }

        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(300))
            withAnimation(.spring(response: 0.28, dampingFraction: 0.86)) {
                remove(photo)
            }
        }
    }

    private func remove(_ photo: CreationPhoto) {
        services.creationService.discard([photo])
        photos.removeAll { $0.id == photo.id }
        deletingPhotoIDs.remove(photo.id)
        addedIdentifiers = PhotoSelectionLogic.identifiers(
            afterRemoving: photo.sourceIdentifier,
            from: addedIdentifiers
        )
        addedFingerprints = PhotoSelectionLogic.fingerprints(
            afterRemoving: photo.sourceFingerprint,
            from: addedFingerprints
        )
        assignments.removeAll { $0.photoID == photo.id }
        ensureTemplateSelection()
    }

    // MARK: - Templates

    private func ensureTemplateSelection() {
        let ranked = rankedTemplates
        guard !ranked.isEmpty else {
            selectedTemplate = nil
            assignments = []
            selectedSlotID = nil
            return
        }
        if let current = selectedTemplate, ranked.contains(where: { $0.id == current.id }) {
            if assignments.count != current.slotCount {
                assignments = current.autoFillMatched(photoIDs: photos.map(\.id), aspects: photoAspectsByID)
            }
            return
        }
        selectTemplate(ranked[0])
    }

    private func selectTemplate(_ template: CardTemplate) {
        selectedTemplate = template
        assignments = template.autoFillMatched(photoIDs: photos.map(\.id), aspects: photoAspectsByID)
        selectedSlotID = template.slots.first?.id
    }

    private var photoAspectsByID: [UUID: CGFloat] {
        Dictionary(uniqueKeysWithValues: photos.map { ($0.id, $0.aspect) })
    }

    private func resetSelectedCrop() {
        guard
            let slotID = selectedSlotID,
            let template = selectedTemplate,
            let slot = template.slots.first(where: { $0.id == slotID }),
            let index = assignments.firstIndex(where: { $0.slotID == slotID })
        else { return }
        let photoID = assignments[index].photoID
        assignments[index].crop = .centred(
            source: photoAspectsByID[photoID] ?? 1,
            target: slot.renderedAspect()
        )
    }

    // MARK: - Seal

    private func seal() async {
        guard !isSealing, let selectedTemplate else { return }
        isSealing = true
        defer { isSealing = false }
        errorMessage = nil
        focusedField = nil

        let unlockDate = ComposerLogic.unlockInstant(from: chosenDate, calendar: .current)
        let input = PostcardCreationInput(
            title: title,
            photos: photos,
            template: selectedTemplate,
            assignments: assignments,
            backText: backText,
            backFontId: backFontId,
            backFontPointSize: Double(selectedBackFontPointSize),
            backTextColorHex: backTextColorHex,
            stampAssetID: selectedStampID,
            locationLabel: locationLabel,
            unlockDate: unlockDate
        )

        do {
            _ = try await services.creationService.create(input)
            committed = true
            onSealed?()
            dismiss()
        } catch let error as PostcardCreationError {
            errorMessage = ComposerLogic.creationErrorCopy(error)
        } catch let error as PostcardLifecycle.SealError {
            errorMessage = ComposerLogic.sealErrorCopy(error)
        } catch {
            errorMessage = "Couldn’t save this postcard. Please try again."
        }
    }

    private func useCurrentLocation() async {
        focusedField = nil
        if let place = await currentLocation.currentPlaceLabel() {
            locationLabel = place
        }
    }

    // MARK: - Helpers

    private var selectedBackFont: PostcardBackFont {
        PostcardBackFont.resolved(id: backFontId)
    }

    private var selectedBackFontPointSize: CGFloat {
        lockedBackFontSizes[backFontId] ?? PostcardBackFont.normalPointSize
    }

    private var lockedBackFonts: [UIFont] {
        lockedBackFontSizes.compactMap { id, size in
            PostcardBackFont(rawValue: id)?.uiFont(pointSize: size)
        }
    }

    private func selectBackFont(_ font: PostcardBackFont) {
        if lockedBackFontSizes[font.id] != nil {
            backFontId = font.id
            fontSelectionMessage = nil
            messageHasNoMoreRoom = false
            return
        }

        guard backCanvasSize.width > 0, backCanvasSize.height > 0 else { return }
        guard let pointSize = PostcardMessageLayout.largestFittingPointSize(
            for: backText,
            font: font,
            canvasSize: backCanvasSize
        ) else {
            fontSelectionMessage = "This message is too long for this font."
            return
        }

        lockedBackFontSizes[font.id] = pointSize
        backFontId = font.id
        fontSelectionMessage = nil
        messageHasNoMoreRoom = false
    }

    private var customBackTextColorBinding: Binding<Color> {
        Binding {
            customBackTextColor
        } set: { newColor in
            customBackTextColor = newColor
            if let hex = newColor.hexString {
                selectBackTextColor(hex)
            }
        }
    }

    private func selectBackTextColor(_ value: String) {
        guard let normalized = Color.normalizedHexColor(value) else { return }
        customBackTextColor = Color(hex: normalized)
        backTextColorHex = normalized
    }

    /// Default the picker to tomorrow at 9:00am — a friendly starting point
    /// that's reliably in the future regardless of the current time of day.
    private static func defaultUnlockDate() -> Date {
        let calendar = Calendar.current
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: Date()) ?? Date()
        return calendar.date(bySettingHour: 9, minute: 0, second: 0, of: tomorrow) ?? tomorrow
    }
}

// MARK: - Template picker

private struct TemplateLayoutPreview: View {
    let template: CardTemplate

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                Rectangle()
                    .fill(Color(red: 0.95, green: 0.90, blue: 0.82))
                ForEach(template.slots) { slot in
                    Rectangle()
                        .fill(.gray.opacity(0.25))
                        .overlay(Rectangle().stroke(.white, lineWidth: 2))
                        .frame(
                            width: CGFloat(slot.width) * proxy.size.width,
                            height: CGFloat(slot.height) * proxy.size.height
                        )
                        .position(
                            x: CGFloat(slot.x + slot.width / 2) * proxy.size.width,
                            y: CGFloat(slot.y + slot.height / 2) * proxy.size.height
                        )
                }
            }
            .overlay(Rectangle().stroke(.gray.opacity(0.35), lineWidth: 1))
            .clipped()
        }
        .accessibilityHidden(true)
    }
}

private struct TemplatePickerPopover: View {
    let templates: [CardTemplate]
    let selectedTemplateID: String?
    let width: CGFloat
    let onSelect: (CardTemplate) -> Void

    private let columns = Array(
        repeating: GridItem(.flexible(), spacing: Tokens.Space.sm),
        count: 2
    )

    var body: some View {
        VStack(alignment: .leading, spacing: Tokens.Space.sm) {
            Text("Choose a Template")
                .font(Tokens.Font.headline)

            LazyVGrid(columns: columns, spacing: Tokens.Space.sm) {
                ForEach(templates) { template in
                    let isSelected = selectedTemplateID == template.id

                    Button {
                        onSelect(template)
                    } label: {
                        HStack(spacing: Tokens.Space.xs) {
                            TemplateLayoutPreview(template: template)
                                .frame(width: 42, height: 52)

                            Text(template.name)
                                .font(Tokens.Font.caption.weight(.semibold))
                                .foregroundStyle(Tokens.Color.chromeText)
                                .lineLimit(2)
                                .multilineTextAlignment(.leading)

                            Spacer(minLength: 0)

                            if isSelected {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(.blue)
                                    .font(.system(size: 18, weight: .semibold))
                            }
                        }
                        .padding(Tokens.Space.xs)
                        .frame(maxWidth: .infinity, minHeight: 68, alignment: .leading)
                        .background(
                            RoundedRectangle(cornerRadius: Tokens.Radius.subtle, style: .continuous)
                                .fill(Tokens.Color.paperCream.opacity(0.72))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: Tokens.Radius.subtle, style: .continuous)
                                .stroke(
                                    isSelected ? Color.blue : Tokens.Color.chromeDivider,
                                    lineWidth: isSelected ? 3 : 1
                                )
                        )
                        .contentShape(RoundedRectangle(cornerRadius: Tokens.Radius.subtle, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(template.name)
                    .accessibilityValue(isSelected ? "Selected" : "")
                    .accessibilityAddTraits(isSelected ? .isSelected : [])
                }
            }
        }
        .padding(Tokens.Space.md)
        .frame(width: width)
    }
}

private struct TemplateCanvasView: View {
    let template: CardTemplate
    let photos: [CreationPhoto]
    @Binding var assignments: [SlotAssignment]
    @Binding var selectedSlotID: String?
    let showsBarriers: Bool

    @State private var dragStartCrop: PhotoCrop?
    @State private var dragStartSlotID: String?
    @State private var magnifyStartScale: Double?
    @State private var magnifyStartSlotID: String?

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .topLeading) {
                Rectangle()
                    .fill(Color(red: 0.95, green: 0.90, blue: 0.82))

                ForEach(template.slots) { slot in
                    slotView(slot, in: proxy.size)
                }

                if showsBarriers {
                    PostcardPhotoBarriers(template: template)
                }

                if let selectedSlot = template.slots.first(where: { $0.id == selectedSlotID }) {
                    Rectangle()
                        .stroke(.blue, lineWidth: 3)
                        .frame(
                            width: CGFloat(selectedSlot.width) * proxy.size.width,
                            height: CGFloat(selectedSlot.height) * proxy.size.height
                        )
                        .offset(
                            x: CGFloat(selectedSlot.x) * proxy.size.width,
                            y: CGFloat(selectedSlot.y) * proxy.size.height
                        )
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }
            }
            .overlay(
                Rectangle().stroke(
                    .gray.opacity(0.35),
                    lineWidth: showsBarriers ? 0 : 1
                )
            )
            .clipped()
        }
    }

    private func slotView(_ slot: TemplateSlot, in size: CGSize) -> some View {
        let slotSize = CGSize(width: CGFloat(slot.width) * size.width, height: CGFloat(slot.height) * size.height)
        let targetAspect = renderedAspect(of: slotSize)
        let assignment = assignments.first { $0.slotID == slot.id }
        let photo = assignment.flatMap { assignment in photos.first { $0.id == assignment.photoID } }
        let crop = (assignment?.crop ?? .centered).constrained(
            sourceAspect: photo?.aspect ?? targetAspect,
            targetAspect: targetAspect
        )

        return ZStack {
            Rectangle().fill(.white)

            if let image = photo?.thumbnail {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: slotSize.width * CGFloat(crop.scale), height: slotSize.height * CGFloat(crop.scale))
                    .offset(x: CGFloat(crop.offsetX) * slotSize.width, y: CGFloat(crop.offsetY) * slotSize.height)
            } else {
                Text("Photo")
                    .foregroundStyle(Tokens.Color.chromeText)
            }
        }
        .frame(width: slotSize.width, height: slotSize.height)
        .clipped()
        .contentShape(Rectangle())
        .highPriorityGesture(
            TapGesture().onEnded {
                selectSlot(slot.id)
            }
        )
        .gesture(dragGesture(for: slot, slotSize: slotSize))
        .simultaneousGesture(magnifyGesture(for: slot, slotSize: slotSize))
        // Keep the gesture-bearing view at the slot's actual size. Attaching
        // gestures after `position` makes every positioned child participate
        // in the full canvas layout region, so the last slot wins hit testing.
        .offset(
            x: CGFloat(slot.x) * size.width,
            y: CGFloat(slot.y) * size.height
        )
    }

    private func dragGesture(for slot: TemplateSlot, slotSize: CGSize) -> some Gesture {
        DragGesture()
            .onChanged { value in
                selectSlot(slot.id)
                guard let index = assignments.firstIndex(where: { $0.slotID == slot.id }) else { return }
                if dragStartSlotID != slot.id {
                    dragStartSlotID = slot.id
                    dragStartCrop = assignments[index].crop
                }
                let start = dragStartCrop ?? assignments[index].crop
                let proposedCrop = PhotoCrop(
                    scale: start.scale,
                    offsetX: start.offsetX + Double(value.translation.width / max(slotSize.width, 1)),
                    offsetY: start.offsetY + Double(value.translation.height / max(slotSize.height, 1))
                )
                assignments[index].crop = constrainedCrop(
                    proposedCrop,
                    targetAspect: renderedAspect(of: slotSize),
                    assignmentIndex: index
                )
            }
            .onEnded { _ in
                dragStartCrop = nil
                dragStartSlotID = nil
            }
    }

    private func magnifyGesture(for slot: TemplateSlot, slotSize: CGSize) -> some Gesture {
        MagnificationGesture()
            .onChanged { value in
                selectSlot(slot.id)
                guard let index = assignments.firstIndex(where: { $0.slotID == slot.id }) else { return }
                if magnifyStartSlotID != slot.id {
                    magnifyStartSlotID = slot.id
                    magnifyStartScale = assignments[index].crop.scale
                }
                let start = magnifyStartScale ?? assignments[index].crop.scale
                var proposedCrop = assignments[index].crop
                proposedCrop.scale = start * Double(value)
                assignments[index].crop = constrainedCrop(
                    proposedCrop,
                    targetAspect: renderedAspect(of: slotSize),
                    assignmentIndex: index
                )
            }
            .onEnded { _ in
                magnifyStartScale = nil
                magnifyStartSlotID = nil
            }
    }

    private func constrainedCrop(
        _ crop: PhotoCrop,
        targetAspect: CGFloat,
        assignmentIndex: Int
    ) -> PhotoCrop {
        let photoID = assignments[assignmentIndex].photoID
        let sourceAspect = photos.first(where: { $0.id == photoID })?.aspect ?? targetAspect
        return crop.constrained(sourceAspect: sourceAspect, targetAspect: targetAspect)
    }

    private func renderedAspect(of size: CGSize) -> CGFloat {
        guard size.height > 0 else { return 1 }
        return size.width / size.height
    }

    private func selectSlot(_ slotID: String) {
        guard selectedSlotID != slotID else { return }
        selectedSlotID = slotID
        dragStartCrop = nil
        dragStartSlotID = nil
        magnifyStartScale = nil
        magnifyStartSlotID = nil
    }
}

//
//  ComposerView.swift
//  DearFutureMe
//
//  MVP postcard creation flow:
//   1. Pick 1-6 photos
//   2. Choose a ranked template and adjust photo crops inside slots
//   3. Write the postcard back and choose text styling
//   4. Add optional typed location, choose unlock date, seal locally
//

import SwiftUI
import PhotosUI
import UIKit

struct ComposerView: View {

    let services: AppServices

    /// Called on a successful seal, before dismissal — the timeline uses it to
    /// trigger the first-seal notification priming (§7.1).
    var onSealed: (() -> Void)? = nil

    @Environment(\.dismiss) private var dismiss

    @State private var step: Step = .photos
    @State private var photos: [CreationPhoto] = []
    @State private var addedIdentifiers: Set<String> = []
    @State private var pickerItems: [PhotosPickerItem] = []

    @State private var selectedTemplate: CardTemplate?
    @State private var assignments: [SlotAssignment] = []
    @State private var selectedSlotID: String?

    @State private var title = ""
    @State private var backText = ""
    @State private var backFontId = BackFont.system.id
    @State private var backTextColorHex = BackTextColor.espresso.hex
    @State private var locationLabel = ""
    @State private var chosenDate = ComposerView.defaultUnlockDate()

    @State private var isSealing = false
    @State private var committed = false
    @State private var errorMessage: String?

    @FocusState private var focusedField: Field?

    private enum Field { case title, backText, location }

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
                        .disabled(isSealing)
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") { focusedField = nil }
                }
            }
        }
        .interactiveDismissDisabled(isSealing)
        .onChange(of: pickerItems) { _, items in
            Task { await importPicked(items) }
        }
        .onDisappear {
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
                        .font(.caption.weight(.semibold))
                        .frame(width: 24, height: 24)
                        .background(Circle().fill(item.rawValue <= step.rawValue ? .blue : .gray.opacity(0.25)))
                        .foregroundStyle(item.rawValue <= step.rawValue ? .white : .secondary)
                    Text(item.title)
                        .font(.caption2)
                        .foregroundStyle(item == step ? .primary : .secondary)
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
                        .font(.footnote)
                        .foregroundStyle(.red)
                }
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .scrollDismissesKeyboard(.interactively)
    }

    private var footer: some View {
        HStack {
            Button("Back") { goBack() }
                .disabled(step == .photos || isSealing)

            Spacer()

            Button(step == .logistics ? "Seal" : "Next") {
                if step == .logistics {
                    Task { await seal() }
                } else {
                    goNext()
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(!canContinue || isSealing)
        }
        .padding()
    }

    // MARK: - Step 1: photos

    private var photoSelection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Choose 1-6 photos")
                .font(.headline)

            if photos.isEmpty {
                emptyPhotoPicker
            } else {
                selectedPhotoGrid
            }

            photoPicker {
                Label(photos.isEmpty ? "Add photos" : "Add more photos", systemImage: "photo.on.rectangle")
            }
            .buttonStyle(.bordered)
            .disabled(photos.count >= ComposerLogic.maxPhotos)

            Text("\(photos.count) of \(ComposerLogic.maxPhotos) selected")
                .font(.caption)
                .foregroundStyle(.secondary)
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
                    .font(.subheadline.weight(.semibold))
                Text("Tap here to choose up to 6")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 190)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(.gray.opacity(0.08))
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
            label: label
        )
    }

    private func photoThumb(_ photo: CreationPhoto, selectionNumber: Int) -> some View {
        GeometryReader { proxy in
            let side = min(proxy.size.width, proxy.size.height)

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
                .clipped()

                RoundedRectangle(cornerRadius: 2)
                    .stroke(.white, lineWidth: 2)

                Text("\(selectionNumber)")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.white)
                    .frame(width: 24, height: 24)
                    .background(Circle().fill(.blue))
                    .shadow(radius: 2, y: 1)
                    .padding(6)
                    .frame(width: side, height: side, alignment: .topLeading)

                Button {
                    remove(photo)
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
                .frame(width: side, height: side, alignment: .topTrailing)
            }
            .frame(width: side, height: side)
            .background(Color(.secondarySystemBackground))
            .clipped()
        }
        .aspectRatio(1, contentMode: .fit)
    }

    // MARK: - Step 2: template

    private var templateSelection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Choose a template")
                .font(.headline)

            let ranked = rankedTemplates
            if ranked.isEmpty {
                Text("Choose photos first.")
                    .foregroundStyle(.secondary)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(ranked) { template in
                            TemplateThumbnail(
                                template: template,
                                isSelected: selectedTemplate?.id == template.id
                            )
                            .onTapGesture {
                                selectTemplate(template)
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }

                if let selectedTemplate {
                    Text("Tap a photo, then drag or pinch to adjust it.")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    TemplateCanvasView(
                        template: selectedTemplate,
                        photos: photos,
                        assignments: $assignments,
                        selectedSlotID: $selectedSlotID
                    )
                    .aspectRatio(4.0 / 5.0, contentMode: .fit)
                    .frame(maxWidth: .infinity)

                    Button("Reset selected crop") {
                        resetSelectedCrop()
                    }
                    .buttonStyle(.bordered)
                    .disabled(selectedSlotID == nil)
                }
            }
        }
        .onAppear { ensureTemplateSelection() }
    }

    private var rankedTemplates: [CardTemplate] {
        TemplatePicker.ranked(TemplatePicker.all, photoAspects: photos.map(\.aspect))
    }

    // MARK: - Step 3: back

    private var backEditor: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Write the back")
                .font(.headline)

            ZStack(alignment: .topLeading) {
                Image("PostcardBack")
                    .resizable()
                    .scaledToFit()
                    .overlay {
                        RoundedRectangle(cornerRadius: 2)
                            .stroke(.gray.opacity(0.4), lineWidth: 1)
                    }

                Text(backText.isEmpty ? "Your message" : backText)
                    .font(selectedBackFont.font)
                    .foregroundStyle(Color(hex: backTextColorHex))
                    .padding(.horizontal, 32)
                    .padding(.top, 42)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .opacity(backText.isEmpty ? 0.35 : 1)
            }
            .frame(maxWidth: .infinity)

            TextField("Title", text: $title)
                .textFieldStyle(.roundedBorder)
                .focused($focusedField, equals: .title)
                .onChange(of: title) { _, new in
                    if new.count > ComposerLogic.maxTitleLength {
                        title = String(new.prefix(ComposerLogic.maxTitleLength))
                    }
                }

            TextEditor(text: $backText)
                .focused($focusedField, equals: .backText)
                .frame(height: 160)
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(.secondary.opacity(0.25)))
                .onChange(of: backText) { _, new in
                    if new.count > ComposerLogic.maxMessageLength {
                        backText = String(new.prefix(ComposerLogic.maxMessageLength))
                    }
                }

            Picker("Font", selection: $backFontId) {
                ForEach(BackFont.allCases) { font in
                    Text(font.name).tag(font.id)
                }
            }
            .pickerStyle(.segmented)

            HStack {
                Text("Color")
                Spacer()
                ForEach(BackTextColor.allCases) { color in
                    Button {
                        backTextColorHex = color.hex
                    } label: {
                        Circle()
                            .fill(Color(hex: color.hex))
                            .frame(width: 28, height: 28)
                            .overlay(Circle().stroke(backTextColorHex == color.hex ? .blue : .clear, lineWidth: 3))
                    }
                    .accessibilityLabel(color.name)
                }
            }
        }
    }

    // MARK: - Step 4: logistics

    private var logistics: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Logistics")
                .font(.headline)

            TextField("Place, optional", text: $locationLabel)
                .textFieldStyle(.roundedBorder)
                .focused($focusedField, equals: .location)

            DatePicker("Unlock", selection: $chosenDate, in: Date()..., displayedComponents: [.date, .hourAndMinute])

            if let selectedTemplate {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Summary")
                        .font(.subheadline.weight(.semibold))
                    Text("\(photos.count) photo\(photos.count == 1 ? "" : "s")")
                    Text(selectedTemplate.name)
                    Text(locationLabel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "No place" : locationLabel)
                }
                .font(.caption)
                .foregroundStyle(.secondary)
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
            return true
        case .logistics:
            return true
        }
    }

    private func goNext() {
        errorMessage = nil
        focusedField = nil
        if step == .photos {
            ensureTemplateSelection()
        }
        guard let next = Step(rawValue: step.rawValue + 1) else { return }
        step = next
    }

    private func goBack() {
        errorMessage = nil
        focusedField = nil
        guard let previous = Step(rawValue: step.rawValue - 1) else { return }
        step = previous
    }

    // MARK: - Photo import

    private func importPicked(_ items: [PhotosPickerItem]) async {
        for item in items {
            guard photos.count < ComposerLogic.maxPhotos else { break }
            let identifier = item.itemIdentifier
            guard PhotoSelectionLogic.canAdd(identifier: identifier, selectedIdentifiers: addedIdentifiers) else {
                continue
            }
            guard
                let data = try? await item.loadTransferable(type: Data.self),
                let image = UIImage(data: data)
            else { continue }
            do {
                let photo = try services.creationService.importPhoto(image, sourceIdentifier: identifier)
                photos.append(photo)
                addedIdentifiers = PhotoSelectionLogic.identifiers(
                    afterAdding: identifier,
                    to: addedIdentifiers
                )
            } catch {
                errorMessage = "Couldn’t add one of those photos."
            }
        }
        pickerItems = []
        ensureTemplateSelection()
    }

    private func remove(_ photo: CreationPhoto) {
        services.creationService.discard([photo])
        photos.removeAll { $0.id == photo.id }
        addedIdentifiers = PhotoSelectionLogic.identifiers(
            afterRemoving: photo.sourceIdentifier,
            from: addedIdentifiers
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
        assignments[index].crop = .centred(source: photoAspectsByID[photoID] ?? 1, target: slot.aspect)
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
            backTextColorHex: backTextColorHex,
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

    // MARK: - Helpers

    private var selectedBackFont: BackFont {
        BackFont.allCases.first { $0.id == backFontId } ?? .system
    }

    /// Default the picker to tomorrow at 9:00am — a friendly starting point
    /// that's reliably in the future regardless of the current time of day.
    private static func defaultUnlockDate() -> Date {
        let calendar = Calendar.current
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: Date()) ?? Date()
        return calendar.date(bySettingHour: 9, minute: 0, second: 0, of: tomorrow) ?? tomorrow
    }
}

// MARK: - Template preview

private struct TemplateThumbnail: View {
    let template: CardTemplate
    let isSelected: Bool

    var body: some View {
        VStack(spacing: 8) {
            GeometryReader { proxy in
                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(.white)
                    ForEach(template.slots) { slot in
                        RoundedRectangle(cornerRadius: 4)
                            .fill(.gray.opacity(0.25))
                            .overlay(RoundedRectangle(cornerRadius: 4).stroke(.gray.opacity(0.6)))
                            .frame(width: CGFloat(slot.width) * proxy.size.width, height: CGFloat(slot.height) * proxy.size.height)
                            .position(
                                x: CGFloat(slot.x + slot.width / 2) * proxy.size.width,
                                y: CGFloat(slot.y + slot.height / 2) * proxy.size.height
                            )
                    }
                }
            }
            .frame(width: 112, height: 140)
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(isSelected ? .blue : .clear, lineWidth: 3))

            Text(template.name)
                .font(.caption)
                .lineLimit(1)
        }
    }
}

private struct TemplateCanvasView: View {
    let template: CardTemplate
    let photos: [CreationPhoto]
    @Binding var assignments: [SlotAssignment]
    @Binding var selectedSlotID: String?

    @State private var dragStartCrop: PhotoCrop?
    @State private var magnifyStartScale: Double?

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color(red: 0.95, green: 0.90, blue: 0.82))

                ForEach(template.slots) { slot in
                    slotView(slot, in: proxy.size)
                }
            }
        }
    }

    private func slotView(_ slot: TemplateSlot, in size: CGSize) -> some View {
        let slotSize = CGSize(width: CGFloat(slot.width) * size.width, height: CGFloat(slot.height) * size.height)
        let assignment = assignments.first { $0.slotID == slot.id }
        let photo = assignment.flatMap { assignment in photos.first { $0.id == assignment.photoID } }
        let crop = assignment?.crop ?? .centered

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
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: slotSize.width, height: slotSize.height)
        .clipped()
        .overlay(
            Rectangle()
                .stroke(selectedSlotID == slot.id ? .blue : .white, lineWidth: selectedSlotID == slot.id ? 3 : 1)
        )
        .position(
            x: CGFloat(slot.x + slot.width / 2) * size.width,
            y: CGFloat(slot.y + slot.height / 2) * size.height
        )
        .contentShape(Rectangle())
        .onTapGesture { selectedSlotID = slot.id }
        .gesture(dragGesture(for: slot, slotSize: slotSize))
        .simultaneousGesture(magnifyGesture(for: slot))
    }

    private func dragGesture(for slot: TemplateSlot, slotSize: CGSize) -> some Gesture {
        DragGesture()
            .onChanged { value in
                guard selectedSlotID == slot.id, let index = assignments.firstIndex(where: { $0.slotID == slot.id }) else { return }
                if dragStartCrop == nil { dragStartCrop = assignments[index].crop }
                let start = dragStartCrop ?? assignments[index].crop
                assignments[index].crop.offsetX = start.offsetX + Double(value.translation.width / max(slotSize.width, 1))
                assignments[index].crop.offsetY = start.offsetY + Double(value.translation.height / max(slotSize.height, 1))
            }
            .onEnded { _ in dragStartCrop = nil }
    }

    private func magnifyGesture(for slot: TemplateSlot) -> some Gesture {
        MagnificationGesture()
            .onChanged { value in
                guard selectedSlotID == slot.id, let index = assignments.firstIndex(where: { $0.slotID == slot.id }) else { return }
                if magnifyStartScale == nil { magnifyStartScale = assignments[index].crop.scale }
                let start = magnifyStartScale ?? assignments[index].crop.scale
                assignments[index].crop.scale = min(max(start * Double(value), 1), 4)
            }
            .onEnded { _ in magnifyStartScale = nil }
    }
}

// MARK: - Back style

private enum BackFont: String, CaseIterable, Identifiable {
    case system
    case rounded
    case serif

    var id: String { rawValue }

    var name: String {
        switch self {
        case .system: return "Clean"
        case .rounded: return "Soft"
        case .serif: return "Letter"
        }
    }

    var font: Font {
        switch self {
        case .system: return .body
        case .rounded: return .system(.body, design: .rounded)
        case .serif: return .system(.body, design: .serif)
        }
    }
}

private enum BackTextColor: String, CaseIterable, Identifiable {
    case espresso
    case taupe
    case sage
    case black

    var id: String { rawValue }

    var name: String {
        switch self {
        case .espresso: return "Espresso"
        case .taupe: return "Taupe"
        case .sage: return "Sage"
        case .black: return "Black"
        }
    }

    var hex: String {
        switch self {
        case .espresso: return "#2B241E"
        case .taupe: return "#A98B76"
        case .sage: return "#6F754F"
        case .black: return "#111111"
        }
    }
}

private extension Color {
    init(hex: String) {
        let raw = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        var value: UInt64 = 0
        Scanner(string: raw).scanHexInt64(&value)
        let r = Double((value >> 16) & 0xFF) / 255.0
        let g = Double((value >> 8) & 0xFF) / 255.0
        let b = Double(value & 0xFF) / 255.0
        self.init(red: r, green: g, blue: b)
    }
}

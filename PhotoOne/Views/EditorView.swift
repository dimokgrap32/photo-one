import SwiftUI
import PhotosUI

@MainActor
struct EditorView: View {

    enum Tool: String, CaseIterable, Identifiable {
        case auto = "Авто"
        case light = "Свет"
        case background = "Фон"
        case portrait = "Портрет"
        case filters = "Фильтры"
        case crop = "Кадр"

        var id: String { rawValue }

        var icon: String {
            switch self {
            case .auto: return "wand.and.stars"
            case .light: return "sun.max"
            case .background: return "person.crop.rectangle"
            case .portrait: return "face.smiling"
            case .filters: return "camera.filters"
            case .crop: return "crop"
            }
        }
    }

    @StateObject private var model = EditorViewModel()
    @State private var pickerItem: PhotosPickerItem?
    @State private var selectedTool: Tool = .light
    @State private var showOriginal = false
    @State private var showPicker = false
    @State private var showShare = false
    @State private var shareImage: UIImage?

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if model.source == nil {
                EmptyStateView { showPicker = true }
            } else {
                editor
            }
        }
        .photosPicker(isPresented: $showPicker, selection: $pickerItem, matching: .images)
        .onChange(of: pickerItem) { _, item in
            handlePicked(item)
        }
        .sheet(isPresented: $showShare) {
            if let shareImage = shareImage {
                ShareSheet(items: [shareImage])
                    .presentationDetents([.medium, .large])
            }
        }
        .preferredColorScheme(.dark)
    }

    // MARK: - Основной экран

    private var editor: some View {
        VStack(spacing: 0) {
            topBar

            ZStack {
                if let image = showOriginal ? model.originalPreview : model.preview {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                }

                if model.isProcessing {
                    ProgressView()
                        .tint(.white)
                        .padding(10)
                        .background(.black.opacity(0.35), in: Capsule())
                        .padding(10)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in showOriginal = true }
                    .onEnded { _ in showOriginal = false }
            )

            panel
            toolBar
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 6)
    }

    private var topBar: some View {
        HStack(spacing: 16) {
            Button {
                showPicker = true
            } label: {
                Image(systemName: "photo.on.rectangle")
            }

            Button {
                model.reset()
            } label: {
                Image(systemName: "arrow.counterclockwise")
            }
            .disabled(model.state.isIdentity)

            Spacer()

            Text("Фото One")
                .font(.headline)

            Spacer()

            Button {
                export()
            } label: {
                if model.isExporting {
                    ProgressView().tint(.white)
                } else {
                    Image(systemName: "square.and.arrow.up")
                }
            }
            .disabled(model.isExporting || model.isProcessing)
        }
        .font(.title3)
        .foregroundStyle(.white)
        .padding(.vertical, 10)
    }

    // MARK: - Панель инструмента

    @ViewBuilder
    private var panel: some View {
        VStack(spacing: 10) {
            switch selectedTool {
            case .auto:
                VStack(spacing: 8) {
                    Button(model.state.autoApplied ? "Авто включено" : "Улучшить автоматически") {
                        model.state.autoApplied.toggle()
                    }
                    .buttonStyle(ChipButtonStyle(active: model.state.autoApplied))

                    Text("Экспозиция, контраст и баланс белого подбираются по снимку")
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.55))
                }

            case .light:
                VStack(spacing: 6) {
                    SliderRow(title: "Яркость", value: $model.state.brightness, range: -1...1)
                    SliderRow(title: "Контраст", value: $model.state.contrast, range: -1...1)
                    SliderRow(title: "Насыщенность", value: $model.state.saturation, range: -1...1)
                    SliderRow(title: "Тепло", value: $model.state.warmth, range: -1...1)
                }

            case .background:
                VStack(spacing: 10) {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(BackgroundMode.allCases) { mode in
                                Button(mode.rawValue) {
                                    model.state.background = mode
                                }
                                .buttonStyle(ChipButtonStyle(active: model.state.background == mode))
                            }
                        }
                        .padding(.horizontal, 2)
                    }

                    if model.state.background == .blur {
                        SliderRow(title: "Сила", value: $model.state.backgroundBlur, range: 0...1)
                    }

                    if model.state.background == .color {
                        HStack(spacing: 10) {
                            ForEach(EditState.backgroundColors, id: \.self) { hex in
                                Circle()
                                    .fill(Color(hex: hex))
                                    .frame(width: 26, height: 26)
                                    .overlay(
                                        Circle().stroke(
                                            Color.white,
                                            lineWidth: model.state.backgroundColorHex == hex ? 2 : 0
                                        )
                                    )
                                    .onTapGesture {
                                        model.state.backgroundColorHex = hex
                                    }
                            }
                        }
                    }

                    if model.state.background != .none, !model.hasMask {
                        Text("Объект не найден — нужен снимок с чётким передним планом")
                            .font(.caption2)
                            .foregroundStyle(.orange.opacity(0.85))
                            .multilineTextAlignment(.center)
                    } else if model.state.background != .none {
                        Text("Передний план не меняется: обрабатывается только фон")
                            .font(.caption2)
                            .foregroundStyle(.white.opacity(0.55))
                    }
                }

            case .portrait:
                VStack(spacing: 8) {
                    SliderRow(title: "Кожа", value: $model.state.soften, range: 0...1)
                    Text("Смягчает только область лица, если оно есть в кадре")
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.55))
                }

            case .filters:
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(PhotoFilter.allCases) { item in
                            Button(item.rawValue) {
                                model.state.filter = item
                            }
                            .buttonStyle(ChipButtonStyle(active: model.state.filter == item))
                        }
                    }
                    .padding(.horizontal, 2)
                }

            case .crop:
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(CropRatio.allCases) { item in
                            Button(item.rawValue) {
                                model.state.crop = item
                            }
                            .buttonStyle(ChipButtonStyle(active: model.state.crop == item))
                        }
                    }
                    .padding(.horizontal, 2)
                }
            }
        }
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity)
    }

    // MARK: - Нижняя панель инструментов

    private var toolBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(Tool.allCases) { item in
                    Button {
                        selectedTool = item
                    } label: {
                        VStack(spacing: 4) {
                            Image(systemName: item.icon)
                                .font(.system(size: 17))
                            Text(item.rawValue)
                                .font(.caption2)
                        }
                        .frame(width: 64, height: 48)
                        .foregroundStyle(selectedTool == item ? Color.black : Color.white.opacity(0.65))
                        .background(
                            selectedTool == item ? Color.white : Color.clear,
                            in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.vertical, 6)
        }
    }

    // MARK: - Действия

    private func handlePicked(_ item: PhotosPickerItem?) {
        guard let item = item else { return }
        Task {
            if let data = try? await item.loadTransferable(type: Data.self),
               let image = UIImage(data: data) {
                model.load(image)
            }
            pickerItem = nil
        }
    }

    private func export() {
        Task {
            if let image = await model.renderFullSize() {
                shareImage = image
                showShare = true
            }
        }
    }
}

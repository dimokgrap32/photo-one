import SwiftUI
import CoreImage

@MainActor
final class EditorViewModel: ObservableObject {

    @Published private(set) var source: UIImage?
    @Published private(set) var preview: UIImage?
    @Published private(set) var originalPreview: UIImage?
    @Published private(set) var isProcessing = false
    @Published private(set) var isExporting = false
    @Published private(set) var hasMask = false

    @Published var state = EditState() {
        didSet {
            if state != oldValue { scheduleRefresh() }
        }
    }

    private var prepared: UIImage?
    private var preparedMask: CIImage?
    private var refreshTask: Task<Void, Never>?
    private var generation = 0

    private let previewDimension: CGFloat = 1440

    // MARK: - Загрузка

    func load(_ image: UIImage) {
        refreshTask?.cancel()
        source = image
        let preparedImage = PhotoEngine.prepare(image, maxDimension: previewDimension)
        prepared = preparedImage
        preparedMask = nil
        hasMask = false
        originalPreview = preparedImage
        preview = preparedImage
        state = EditState()
        Task { await performRefresh() }
    }

    func reset() {
        state = EditState()
    }

    // MARK: - Обновление превью

    private func scheduleRefresh() {
        refreshTask?.cancel()
        refreshTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 150_000_000)
            guard !Task.isCancelled else { return }
            await self?.performRefresh()
        }
    }

    private func performRefresh() async {
        guard let prepared = prepared else { return }

        let snapshot = state
        generation += 1
        let currentGeneration = generation

        let cachedMask = preparedMask
        isProcessing = true

        // Vision и Core Image — на фоновом потоке, UI не блокируем.
        let result = await Task.detached(priority: .userInitiated) { () -> (UIImage?, CIImage?) in
            var mask = cachedMask
            if snapshot.background != .none, mask == nil {
                mask = PhotoEngine.foregroundMask(for: prepared)
            }
            let image = PhotoEngine.render(prepared: prepared, state: snapshot, mask: mask)
            return (image, mask)
        }.value

        guard currentGeneration == generation else { return }

        preparedMask = result.1
        hasMask = result.1 != nil
        preview = result.0
        isProcessing = false
    }

    // MARK: - Экспорт

    func renderFullSize() async -> UIImage? {
        guard let source = source else { return nil }

        let snapshot = state
        isExporting = true

        let result = await Task.detached(priority: .userInitiated) { () -> UIImage? in
            let big = PhotoEngine.prepare(source, maxDimension: 4096)
            var mask: CIImage?
            if snapshot.background != .none {
                mask = PhotoEngine.foregroundMask(for: big)
            }
            return PhotoEngine.render(prepared: big, state: snapshot, mask: mask)
        }.value

        isExporting = false
        return result
    }
}

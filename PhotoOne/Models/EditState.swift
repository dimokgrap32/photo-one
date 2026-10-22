import Foundation

// MARK: - Фон

enum BackgroundMode: String, CaseIterable, Identifiable {
    case none = "Нет"
    case blur = "Боке"
    case darken = "Затемнить"
    case mono = "Ч/Б"
    case color = "Цвет"

    var id: String { rawValue }
}

// MARK: - Фильтры

enum PhotoFilter: String, CaseIterable, Identifiable {
    case none = "Оригинал"
    case vivid = "Vivid"
    case warm = "Тёплый"
    case cool = "Холодный"
    case mono = "Ч/Б"
    case fade = "Fade"
    case noir = "Noir"
    case chrome = "Chrome"

    var id: String { rawValue }
}

// MARK: - Кадрирование

enum CropRatio: String, CaseIterable, Identifiable {
    case original = "Оригинал"
    case square = "1:1"
    case portrait = "4:5"
    case landscape = "16:9"

    var id: String { rawValue }
}

// MARK: - Состояние редактирования

struct EditState: Equatable {
    var autoApplied = false

    var brightness: Double = 0
    var contrast: Double = 0
    var saturation: Double = 0
    var warmth: Double = 0

    var background: BackgroundMode = .none
    var backgroundBlur: Double = 0.45
    var backgroundColorHex: String = "#101014"

    var soften: Double = 0
    var filter: PhotoFilter = .none
    var crop: CropRatio = .original

    static let backgroundColors = [
        "#101014", "#FFFFFF", "#F2E3C6",
        "#1B2A1F", "#2B1B3A", "#E4572E"
    ]

    var isIdentity: Bool {
        !autoApplied
            && brightness == 0 && contrast == 0 && saturation == 0 && warmth == 0
            && background == .none && soften == 0
            && filter == .none && crop == .original
    }
}

import UIKit
import CoreImage
import CoreVideo

extension UIImage {
    /// Приводит изображение к ориентации `.up`, чтобы Core Image и Vision работали в одной системе координат.
    func normalizedUp() -> UIImage {
        guard imageOrientation != .up else { return self }
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        format.opaque = false
        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        return renderer.image { _ in
            draw(in: CGRect(origin: .zero, size: size))
        }
    }
}

extension CIColor {
    convenience init?(hex: String) {
        var value = hex.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        if value.hasPrefix("#") { value.removeFirst() }
        guard value.count == 6, let number = UInt32(value, radix: 16) else { return nil }
        self.init(
            red: CGFloat((number >> 16) & 0xFF) / 255.0,
            green: CGFloat((number >> 8) & 0xFF) / 255.0,
            blue: CGFloat(number & 0xFF) / 255.0,
            alpha: 1.0
        )
    }
}

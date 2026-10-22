import SwiftUI
import UIKit
import Foundation

// MARK: - Пустое состояние

struct EmptyStateView: View {
    var onPick: () -> Void

    var body: some View {
        VStack(spacing: 18) {
            Image(systemName: "wand.and.stars")
                .font(.system(size: 54, weight: .light))
                .foregroundStyle(.white.opacity(0.85))

            Text("Фото One")
                .font(.largeTitle.bold())
                .foregroundStyle(.white)

            Text("Один тап — готово.\nФон отдельно, передний план не трогаем.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.white.opacity(0.65))

            Button(action: onPick) {
                Label("Выбрать фото", systemImage: "photo")
                    .font(.headline)
                    .padding(.horizontal, 22)
                    .padding(.vertical, 14)
                    .background(Color.white, in: Capsule())
                    .foregroundStyle(Color.black)
            }
            .padding(.top, 6)
        }
        .padding(32)
    }
}

// MARK: - Чипы

struct ChipButtonStyle: ButtonStyle {
    var active: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(.medium))
            .lineLimit(1)
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .background(
                active ? Color.white : Color.white.opacity(0.12),
                in: Capsule()
            )
            .foregroundStyle(active ? Color.black : Color.white.opacity(0.9))
            .opacity(configuration.isPressed ? 0.7 : 1)
    }
}

// MARK: - Слайдер

struct SliderRow: View {
    let title: String
    @Binding var value: Double
    let range: ClosedRange<Double>

    var body: some View {
        HStack(spacing: 10) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.white.opacity(0.7))
                .frame(width: 92, alignment: .leading)

            Slider(value: $value, in: range)
                .tint(.white)

            Text(String(format: "%+.2f", value))
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.white.opacity(0.5))
                .frame(width: 48, alignment: .trailing)
        }
    }
}

// MARK: - Share sheet

struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

// MARK: - Hex-цвет

extension Color {
    init(hex: String) {
        var value = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.hasPrefix("#") { value.removeFirst() }

        var number: UInt64 = 0
        Scanner(string: value).scanHexInt64(&number)

        self.init(
            red: Double((number >> 16) & 0xFF) / 255.0,
            green: Double((number >> 8) & 0xFF) / 255.0,
            blue: Double(number & 0xFF) / 255.0
        )
    }
}

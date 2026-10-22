import UIKit
import CoreImage
import CoreImage.CIFilterBuiltins
import CoreVideo
import Vision

/// Вся обработка фото: Core Image для цвета, Vision для масок.
enum PhotoEngine {

    static let context = CIContext(options: [.cacheIntermediates: false])

    // MARK: - Подготовка

    /// Нормализует ориентацию и уменьшает снимок до `maxDimension` по длинной стороне.
    static func prepare(_ image: UIImage, maxDimension: CGFloat) -> UIImage {
        let upright = image.normalizedUp()
        let size = upright.size
        guard size.width > 1, size.height > 1 else { return upright }

        let longest = max(size.width, size.height)
        let scale = min(1, maxDimension / longest)
        guard scale < 0.999 else { return upright }

        let target = CGSize(
            width: max(1, floor(size.width * scale)),
            height: max(1, floor(size.height * scale))
        )
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        format.opaque = false
        let renderer = UIGraphicsImageRenderer(size: target, format: format)
        return renderer.image { _ in
            upright.draw(in: CGRect(origin: .zero, size: target))
        }
    }

    // MARK: - Маска переднего плана

    /// Возвращает маску переднего плана (белое — объект). iOS 17+.
    static func foregroundMask(for image: UIImage) -> CIImage? {
        guard let cgImage = image.cgImage else { return nil }

        let request = VNGenerateForegroundInstanceMaskRequest()
        let handler = VNImageRequestHandler(cgImage: cgImage, orientation: .up, options: [:])

        do {
            try handler.perform([request])
        } catch {
            return nil
        }

        guard let observation = request.results?.first,
              !observation.allInstances.isEmpty else { return nil }

        do {
            let buffer = try observation.generateScaledMaskForImage(
                forInstances: observation.allInstances,
                from: handler
            )
            return CIImage(cvPixelBuffer: buffer)
        } catch {
            return nil
        }
    }

    // MARK: - Рендер

    static func render(prepared: UIImage, state: EditState, mask: CIImage?) -> UIImage? {
        guard let base = CIImage(image: prepared) else { return nil }

        var image = applyAdjustments(base, state: state)

        if state.background != .none, let mask = mask {
            image = applyBackground(image, state: state, mask: mask)
        }

        if state.soften > 0.01, let skin = faceMask(for: prepared) {
            image = applySoften(image, state: state, skin: skin)
        }

        image = applyFilter(image, state: state)
        image = applyCrop(image, ratio: state.crop)

        let extent = image.extent
        guard extent.width > 1, extent.height > 1, !extent.isInfinite else { return nil }
        guard let cgImage = context.createCGImage(image, from: extent) else { return nil }
        return UIImage(cgImage: cgImage, scale: 1, orientation: .up)
    }

    // MARK: - Цвет

    private static func applyAdjustments(_ image: CIImage, state: EditState) -> CIImage {
        var output = image

        if state.autoApplied {
            for filter in image.autoAdjustmentFilters() {
                output = output.applyingFilter(filter)
            }
        }

        if state.brightness != 0 || state.contrast != 0 || state.saturation != 0 {
            let controls = CIFilter.colorControls()
            controls.inputImage = output
            controls.brightness = Float(state.brightness * 0.30)
            controls.contrast = Float(1 + state.contrast * 0.80)
            controls.saturation = Float(1 + state.saturation)
            if let result = controls.outputImage {
                output = result
            }
        }

        if state.warmth != 0 {
            let temperature = CIFilter.temperatureAndTint()
            temperature.inputImage = output
            temperature.neutral = CIVector(x: 6500, y: 0)
            temperature.targetNeutral = CIVector(x: CGFloat(6500 - state.warmth * 2200), y: 0)
            if let result = temperature.outputImage {
                output = result
            }
        }

        return output
    }

    // MARK: - Фон

    private static func applyBackground(_ image: CIImage, state: EditState, mask: CIImage) -> CIImage {
        let extent = image.extent
        let background: CIImage

        switch state.background {
        case .none:
            return image
        case .blur:
            // Сильное размытие фона, передний план остаётся резким.
            let sigma = CGFloat(4 + state.backgroundBlur * 36)
            background = image
                .clampedToExtent()
                .applyingGaussianBlur(sigma: sigma)
                .cropped(to: extent)
        case .darken:
            background = image.applyingFilter("CIColorControls", parameters: [
                kCIInputBrightnessKey: -0.30,
                kCIInputContrastKey: 1.08
            ])
        case .mono:
            background = image
                .applyingFilter("CIPhotoEffectMono")
                .applyingFilter("CIColorControls", parameters: [kCIInputBrightnessKey: -0.05])
        case .color:
            let color = CIColor(hex: state.backgroundColorHex)
                ?? CIColor(red: 0.05, green: 0.05, blue: 0.07, alpha: 1)
            background = CIImage(color: color).cropped(to: extent)
        }

        let blend = CIFilter.blendWithMask()
        blend.inputImage = image
        blend.backgroundImage = background
        blend.maskImage = mask.cropped(to: extent)
        return blend.outputImage?.cropped(to: extent) ?? image
    }

    // MARK: - Портрет

    /// Мягкая маска по области лица (Vision, face rectangles).
    private static func faceMask(for image: UIImage) -> CIImage? {
        guard let cgImage = image.cgImage else { return nil }

        let request = VNDetectFaceRectanglesRequest()
        let handler = VNImageRequestHandler(cgImage: cgImage, orientation: .up, options: [:])

        do {
            try handler.perform([request])
        } catch {
            return nil
        }

        guard let faces = request.results, !faces.isEmpty else { return nil }

        let width = CGFloat(cgImage.width)
        let height = CGFloat(cgImage.height)

        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        format.opaque = false
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: width, height: height), format: format)

        let maskImage = renderer.image { _ in
            UIColor.white.setFill()
            for face in faces {
                let box = face.boundingBox
                let rect = CGRect(
                    x: box.origin.x * width,
                    y: (1 - box.origin.y - box.height) * height,
                    width: box.width * width,
                    height: box.height * height
                )
                let expanded = rect.insetBy(dx: -rect.width * 0.12, dy: -rect.height * 0.12)
                UIBezierPath(ovalIn: expanded).fill()
            }
        }

        guard let maskCG = maskImage.cgImage else { return nil }
        let mask = CIImage(cgImage: maskCG)
        let feather = max(width, height) * 0.02

        return mask
            .clampedToExtent()
            .applyingGaussianBlur(sigma: feather)
            .cropped(to: mask.extent)
    }

    private static func applySoften(_ image: CIImage, state: EditState, skin: CIImage) -> CIImage {
        let extent = image.extent
        let intensity = CGFloat(state.soften)

        let smooth = image
            .clampedToExtent()
            .applyingGaussianBlur(sigma: 4 + intensity * 8)
            .cropped(to: extent)

        let weightedMask = skin.applyingFilter("CIColorMatrix", parameters: [
            "inputRVector": CIVector(x: intensity, y: 0, z: 0, w: 0),
            "inputGVector": CIVector(x: 0, y: intensity, z: 0, w: 0),
            "inputBVector": CIVector(x: 0, y: 0, z: intensity, w: 0),
            "inputAVector": CIVector(x: 0, y: 0, z: 0, w: 1)
        ]).cropped(to: extent)

        let blend = CIFilter.blendWithMask()
        blend.inputImage = smooth
        blend.backgroundImage = image
        blend.maskImage = weightedMask
        return blend.outputImage?.cropped(to: extent) ?? image
    }

    // MARK: - Фильтры

    private static func applyFilter(_ image: CIImage, state: EditState) -> CIImage {
        switch state.filter {
        case .none:
            return image
        case .vivid:
            return image.applyingFilter("CIColorControls", parameters: [
                kCIInputSaturationKey: 1.35,
                kCIInputContrastKey: 1.08
            ])
        case .warm:
            return image.applyingFilter("CITemperatureAndTint", parameters: [
                "inputNeutral": CIVector(x: 6500, y: 0),
                "inputTargetNeutral": CIVector(x: 4600, y: 0)
            ])
        case .cool:
            return image.applyingFilter("CITemperatureAndTint", parameters: [
                "inputNeutral": CIVector(x: 6500, y: 0),
                "inputTargetNeutral": CIVector(x: 8600, y: 0)
            ])
        case .mono:
            return image.applyingFilter("CIPhotoEffectMono")
        case .fade:
            return image.applyingFilter("CIPhotoEffectFade")
        case .noir:
            return image.applyingFilter("CIPhotoEffectNoir")
        case .chrome:
            return image.applyingFilter("CIPhotoEffectChrome")
        }
    }

    // MARK: - Кадр

    private static func applyCrop(_ image: CIImage, ratio: CropRatio) -> CIImage {
        guard ratio != .original else { return image }

        let extent = image.extent
        guard extent.width > 1, extent.height > 1 else { return image }

        let target: CGFloat
        switch ratio {
        case .original: return image
        case .square: target = 1
        case .portrait: target = 4.0 / 5.0
        case .landscape: target = 16.0 / 9.0
        }

        let current = extent.width / extent.height
        let rect: CGRect

        if current > target {
            let width = extent.height * target
            rect = CGRect(
                x: extent.midX - width / 2,
                y: extent.minY,
                width: width,
                height: extent.height
            )
        } else {
            let height = extent.width / target
            rect = CGRect(
                x: extent.minX,
                y: extent.midY - height / 2,
                width: extent.width,
                height: height
            )
        }

        return image
            .cropped(to: rect)
            .transformed(by: CGAffineTransform(translationX: -rect.origin.x, y: -rect.origin.y))
    }
}

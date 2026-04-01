//
//  ScheduleBackgroundArtwork.swift
//  MySJTU
//
//  Created by boar on 2026/03/21.
//

import SwiftUI
import UIKit

struct ScheduleBackgroundEffectConfiguration: Equatable {
    static let defaultTransparency = 0.35
    static let defaultBlurRadius = 18.0
    static let defaultParallaxEnabled = true
    static let parallaxCropAspectRatioMultiplier: CGFloat = 0.9
    static let transparencyRange: ClosedRange<Double> = 0.0...0.8
    static let blurRadiusRange: ClosedRange<Double> = 0.0...30.0

    let transparency: Double
    let blurRadius: Double

    var clampedTransparency: Double {
        min(max(transparency, Self.transparencyRange.lowerBound), Self.transparencyRange.upperBound)
    }

    var clampedBlurRadius: Double {
        min(max(blurRadius, Self.blurRadiusRange.lowerBound), Self.blurRadiusRange.upperBound)
    }

    var imageOpacity: Double {
        max(0.2, 1 - clampedTransparency * 0.6)
    }

    var topOverlayOpacity: Double {
        0.18 + clampedTransparency * 0.24
    }

    var middleOverlayOpacity: Double {
        0.36 + clampedTransparency * 0.34
    }

    var bottomOverlayOpacity: Double {
        0.52 + clampedTransparency * 0.32
    }

    var flatOverlayOpacity: Double {
        0.08 + clampedTransparency * 0.34
    }

    var usesDefaultValues: Bool {
        abs(clampedTransparency - Self.defaultTransparency) < 0.001 &&
        abs(clampedBlurRadius - Self.defaultBlurRadius) < 0.001
    }

    static var defaultValue: Self {
        Self(
            transparency: defaultTransparency,
            blurRadius: defaultBlurRadius
        )
    }

    static func maximumBackgroundAspectRatio(for viewportSize: CGSize) -> CGFloat {
        let width = min(viewportSize.width, viewportSize.height)
        let height = max(viewportSize.width, viewportSize.height)
        guard width > 0, height > 0 else { return 9.0 / 19.5 }
        return width / height
    }

    static func landscapeBackgroundAspectRatio(for viewportSize: CGSize) -> CGFloat {
        let width = max(viewportSize.width, viewportSize.height)
        let height = min(viewportSize.width, viewportSize.height)
        guard width > 0, height > 0 else { return 19.5 / 9.0 }
        return width / height
    }

    static func parallaxBackgroundAspectRatio(for viewportSize: CGSize) -> CGFloat {
        maximumBackgroundAspectRatio(for: viewportSize) * parallaxCropAspectRatioMultiplier
    }

    static func landscapeParallaxBackgroundAspectRatio(for viewportSize: CGSize) -> CGFloat {
        landscapeBackgroundAspectRatio(for: viewportSize) * parallaxCropAspectRatioMultiplier
    }

    static func imageAspectRatio(for imageSize: CGSize) -> CGFloat? {
        guard imageSize.width > 0, imageSize.height > 0 else { return nil }
        return imageSize.width / imageSize.height
    }

    static func constrainedBackgroundAspectRatio(for imageSize: CGSize, viewportSize: CGSize) -> CGFloat {
        guard let imageAspectRatio = imageAspectRatio(for: imageSize) else {
            return maximumBackgroundAspectRatio(for: viewportSize)
        }
        return min(imageAspectRatio, maximumBackgroundAspectRatio(for: viewportSize))
    }

    static func cropAspectRatio(for imageSize: CGSize, parallaxEnabled: Bool, viewportSize: CGSize) -> CGFloat {
        return parallaxEnabled
        ? parallaxBackgroundAspectRatio(for: viewportSize)
        : maximumBackgroundAspectRatio(for: viewportSize)
    }
}

struct ScheduleBackgroundArtwork: View {
    let image: UIImage
    let effect: ScheduleBackgroundEffectConfiguration

    var body: some View {
        Image(uiImage: image)
            .resizable()
            .scaledToFill()
            .opacity(effect.imageOpacity)
            .blur(radius: effect.clampedBlurRadius)
            .scaleEffect(1.05)
            .overlay {
                Rectangle()
                    .fill(
                        LinearGradient(
                            colors: [
                                Color(UIColor.systemBackground).opacity(effect.topOverlayOpacity),
                                Color(UIColor.systemBackground).opacity(effect.middleOverlayOpacity),
                                Color(UIColor.systemBackground).opacity(effect.bottomOverlayOpacity)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
            }
            .overlay {
                Rectangle()
                    .fill(Color(UIColor.systemBackground).opacity(effect.flatOverlayOpacity))
            }
    }
}

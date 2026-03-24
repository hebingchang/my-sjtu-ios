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

    static var maximumBackgroundAspectRatio: CGFloat {
        let screenBounds = UIScreen.main.bounds
        let width = min(screenBounds.width, screenBounds.height)
        let height = max(screenBounds.width, screenBounds.height)
        guard width > 0, height > 0 else { return 9.0 / 19.5 }
        return width / height
    }

    static var parallaxBackgroundAspectRatio: CGFloat {
        maximumBackgroundAspectRatio * parallaxCropAspectRatioMultiplier
    }

    static func imageAspectRatio(for imageSize: CGSize) -> CGFloat? {
        guard imageSize.width > 0, imageSize.height > 0 else { return nil }
        return imageSize.width / imageSize.height
    }

    static func constrainedBackgroundAspectRatio(for imageSize: CGSize) -> CGFloat {
        guard let imageAspectRatio = imageAspectRatio(for: imageSize) else {
            return maximumBackgroundAspectRatio
        }
        return min(imageAspectRatio, maximumBackgroundAspectRatio)
    }

    static func cropAspectRatio(for imageSize: CGSize, parallaxEnabled: Bool) -> CGFloat {
        return parallaxEnabled ? parallaxBackgroundAspectRatio : maximumBackgroundAspectRatio
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

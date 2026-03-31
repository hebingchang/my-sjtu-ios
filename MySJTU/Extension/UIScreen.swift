//
//  UIScreen.swift
//  MySJTU
//
//  Created by boar on 2024/11/26.
//

import UIKit

extension UIScreen {
    public func setBrightness(to value: CGFloat, duration: TimeInterval = 0.3, ticksPerSecond: Double = 120) {
        let clampedValue = max(min(value, 1), 0)

        guard duration > 0, ticksPerSecond > 0 else {
            brightness = clampedValue
            return
        }

        let startingBrightness = brightness
        let delta = clampedValue - startingBrightness
        let totalTicks = max(Int(ticksPerSecond * duration), 1)
        let changePerTick = delta / CGFloat(totalTicks)
        let delayBetweenTicks = 1 / ticksPerSecond

        let time = DispatchTime.now()

        for i in 1...totalTicks {
            DispatchQueue.main.asyncAfter(deadline: time + delayBetweenTicks * Double(i)) { [weak self] in
                guard let self else { return }
                self.brightness = max(min(startingBrightness + (changePerTick * CGFloat(i)), 1), 0)
            }
        }
    }
}

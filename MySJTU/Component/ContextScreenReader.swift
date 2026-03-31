//
//  ContextScreenReader.swift
//  MySJTU
//
//  Created by boar on 2026/03/30.
//

import SwiftUI
import UIKit

private final class ContextScreenProbeView: UIView {
    var onScreenChange: ((UIScreen?) -> Void)?
    private weak var lastScreen: UIScreen?
    private var lastBounds: CGRect = .null

    override func didMoveToWindow() {
        super.didMoveToWindow()
        reportScreenIfNeeded()
    }

    override func didMoveToSuperview() {
        super.didMoveToSuperview()
        reportScreenIfNeeded()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        reportScreenIfNeeded()
    }

    func reportScreenIfNeeded() {
        let screen = window?.windowScene?.screen
        let bounds = screen?.bounds ?? .null

        guard lastScreen !== screen || lastBounds != bounds else { return }

        lastScreen = screen
        lastBounds = bounds
        onScreenChange?(screen)
    }
}

private struct ContextScreenReader: UIViewRepresentable {
    let onChange: (UIScreen?) -> Void

    func makeUIView(context: Context) -> ContextScreenProbeView {
        let view = ContextScreenProbeView(frame: .zero)
        view.isUserInteractionEnabled = false
        view.backgroundColor = .clear
        view.onScreenChange = onChange
        return view
    }

    func updateUIView(_ uiView: ContextScreenProbeView, context: Context) {
        uiView.onScreenChange = onChange
        uiView.reportScreenIfNeeded()
    }
}

extension View {
    func onContextScreenChange(perform action: @escaping (UIScreen?) -> Void) -> some View {
        background {
            ContextScreenReader(onChange: action)
                .frame(width: 0, height: 0)
        }
    }
}

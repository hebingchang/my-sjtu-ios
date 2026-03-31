//
//  HTMLTextView.swift
//  MySJTU
//
//  Created by boar on 2024/12/04.
//

import SwiftUI
import UIKit

struct HTMLTextView: UIViewRepresentable {
    let htmlContent: String

    func makeUIView(context: Context) -> UITextView {
        let textView = UITextView()
        textView.isSelectable = false
        textView.isEditable = false
        textView.isScrollEnabled = true
        textView.showsHorizontalScrollIndicator = true
        textView.showsVerticalScrollIndicator = false
        textView.alwaysBounceHorizontal = false
        textView.alwaysBounceVertical = false
        textView.isDirectionalLockEnabled = true
        textView.backgroundColor = .clear
        return textView
    }

    func updateUIView(_ uiView: UITextView, context: Context) {
        guard let data = htmlContent.data(using: .utf8) else { return }
        let options: [NSAttributedString.DocumentReadingOptionKey: Any] = [
            .documentType: NSAttributedString.DocumentType.html,
            .characterEncoding: String.Encoding.utf8.rawValue
        ]
        if let attributedString = try? NSAttributedString(data: data, options: options, documentAttributes: nil) {
            uiView.attributedText = attributedString
            uiView.textColor = .label
            uiView.font = UIFont.preferredFont(forTextStyle: .body)
        }
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: UITextView, context: Context) -> CGSize? {
        guard let width = proposal.width, width > 0 else {
            return nil
        }

        let fittingSize = uiView.sizeThatFits(
            CGSize(width: width, height: .greatestFiniteMagnitude)
        )
        return CGSize(width: width, height: fittingSize.height)
    }
}

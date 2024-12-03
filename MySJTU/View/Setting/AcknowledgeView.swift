//
//  AcknowledgeView.swift
//  MySJTU
//
//  Created by boar on 2024/11/10.
//

import SwiftUI
import AcknowList

struct AcknowledgeView: View {
    var body: some View {
        if let url = Bundle.main.url(forResource: "Package", withExtension: "resolved"),
           let data = try? Data(contentsOf: url),
           let acknowList = try? AcknowPackageDecoder().decode(from: data) {
            AcknowListSwiftUIView(acknowList: acknowList)
        }
    }
}

#Preview {
    AcknowledgeView()
}

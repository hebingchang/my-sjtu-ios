//
//  ContentView.swift
//  MySJTULite Watch App
//
//  Created by 何炳昌 on 2024/12/18.
//

import SwiftUI

struct ContentView: View {
    var collegeId = UserDefaults.shared.integer(forKey: "collegeId")

    var body: some View {
        VStack {
            Image(systemName: "globe")
                .imageScale(.large)
                .foregroundStyle(.tint)
            Text("Hello, world! \(collegeId)")
        }
        .padding()
    }
}

#Preview {
    ContentView()
}

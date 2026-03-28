//
//  MySJTUWatchApp.swift
//  MySJTUWatch Watch App
//
//  Created by boar on 2026/03/27.
//

import SwiftUI

@main
struct MySJTUWatch_Watch_AppApp: App {
    @StateObject private var store = WatchScheduleStore()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(store)
        }
    }
}

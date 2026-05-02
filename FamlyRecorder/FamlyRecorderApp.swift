//
//  FamlyRecorderApp.swift
//  FamlyRecorder
//
//  Created by kikuchitakashi on 2026/04/05.
//

import SwiftUI

@main
struct FamlyRecorderApp: App {
    @Environment(\.scenePhase) private var scenePhase
    private let recorder: RecorderManager

    init() {
        let arguments = ProcessInfo.processInfo.arguments
        let mode: RecorderManager.Mode = arguments.contains("-ui-testing") ? .simulated : .live
        recorder = RecorderManager(mode: mode)
    }

    var body: some Scene {
        WindowGroup {
            TabView {
                ContentView(recorder: recorder)
                    .tabItem { Label("録音", systemImage: "mic.fill") }
                RecordingListView(recorder: recorder)
                    .tabItem { Label("一覧", systemImage: "list.bullet") }
            }
        }
        .onChange(of: scenePhase) { _, newPhase in
            recorder.setBackgroundMode(enabled: newPhase == .background)
        }
    }
}

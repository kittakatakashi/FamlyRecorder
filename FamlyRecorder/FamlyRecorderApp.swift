//
//  FamlyRecorderApp.swift
//  FamlyRecorder
//
//  Created by kikuchitakashi on 2026/04/05.
//

import SwiftUI

@main
struct FamlyRecorderApp: App {
    private let recorder: RecorderManager

    init() {
        let arguments = ProcessInfo.processInfo.arguments
        let mode: RecorderManager.Mode = arguments.contains("-ui-testing") ? .simulated : .live
        recorder = RecorderManager(mode: mode)
    }

    var body: some Scene {
        WindowGroup {
            ContentView(recorder: recorder)
        }
    }
}

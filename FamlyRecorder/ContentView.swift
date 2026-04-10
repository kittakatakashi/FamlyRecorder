//
//  ContentView.swift
//  FamlyRecorder
//
//  Created by kikuchitakashi on 2026/04/05.
//

import SwiftUI

struct ContentView: View {
    @StateObject private var recorder: RecorderManager

    @MainActor
    init() {
        _recorder = StateObject(wrappedValue: RecorderManager())
    }

    @MainActor
    init(recorder: RecorderManager) {
        _recorder = StateObject(wrappedValue: recorder)
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 20) {
                statusCard
                autoRecordingSection
                savedFileSection
                Spacer()
            }
            .padding(24)
            .navigationTitle("Famly Recorder")
        }
        .onAppear {
            recorder.prepare()
        }
        .alert("録音エラー", isPresented: errorBinding) {
            Button("OK") {
                recorder.dismissError()
            }
        } message: {
            Text(recorder.errorMessage ?? "")
        }
    }

    private var statusCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(recorder.permissionStatusText, systemImage: "mic.fill")
                .accessibilityIdentifier("permissionStatusLabel")
            Label(recorder.bufferStatusText, systemImage: "waveform")
                .accessibilityIdentifier("bufferStatusLabel")
            Label(recorder.recordingStatusText, systemImage: recorder.isRecordingClip ? "record.circle.fill" : "record.circle")
                .accessibilityIdentifier("recordingStatusLabel")
            Label(recorder.energyModeStatusText, systemImage: recorder.isLowPowerBackgroundMode ? "leaf.fill" : "bolt.fill")
                .accessibilityIdentifier("energyModeStatusLabel")

            if let fileName = recorder.lastSavedFileName {
                Label("保存済み: \(fileName)", systemImage: "folder.fill")
                    .accessibilityIdentifier("savedFileLabel")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private var autoRecordingSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("自動録音")
                .font(.headline)
            Text("会話を検知すると録音を開始し、会話が止まると自動で録音を停止します。")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("autoRecordingText")
        }
    }

    private var savedFileSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("保存先")
                .font(.headline)
            Text("録音ファイルは「ファイル」Appの「このiPhone内」>「FamlyRecorder」で確認できます。")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("saveDestinationText")
        }
    }

    private var errorBinding: Binding<Bool> {
        Binding(
            get: { recorder.errorMessage != nil },
            set: { newValue in
                if !newValue {
                    recorder.dismissError()
                }
            }
        )
    }
}

#Preview {
    ContentView()
}

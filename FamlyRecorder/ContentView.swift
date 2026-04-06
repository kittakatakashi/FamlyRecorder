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
                controlButton
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

            if let fileName = recorder.lastSavedFileName {
                Label("保存済み: \(fileName)", systemImage: "folder.fill")
                    .accessibilityIdentifier("savedFileLabel")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private var controlButton: some View {
        Button {
            if recorder.isRecordingClip {
                recorder.stopClipRecording()
            } else {
                recorder.startClipRecording()
            }
        } label: {
            Text(recorder.isRecordingClip ? "録音停止" : "録音開始")
                .font(.title3.bold())
                .frame(maxWidth: .infinity)
                .padding(.vertical, 18)
        }
        .accessibilityIdentifier("recordButton")
        .buttonStyle(.borderedProminent)
        .tint(recorder.isRecordingClip ? .red : .blue)
        .disabled(!recorder.canControlRecording)
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

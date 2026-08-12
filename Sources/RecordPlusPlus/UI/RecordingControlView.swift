import SwiftUI
import CoreMedia

struct RecordingControlView: View {
    @ObservedObject var recordingManager: RecordingManager

    var body: some View {
        VStack(spacing: 12) {
            if recordingManager.isRecording {
                recordingStatusBar
            }

            HStack(spacing: 16) {
                if !recordingManager.isRecording {
                    Button(action: { recordingManager.startRecording() }) {
                        Label("Start Recording", systemImage: "record.circle")
                            .frame(minWidth: 120)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(recordingManager.selectedWindow == nil)
                    .keyboardShortcut("r", modifiers: [.command])
                } else {
                    Button(action: { recordingManager.stopRecording() }) {
                        Label("Stop Recording", systemImage: "stop.circle.fill")
                            .frame(minWidth: 120)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.red)
                    .keyboardShortcut("s", modifiers: [.command])
                }
            }
        }
        .padding()
        .background(Color(nsColor: .controlBackgroundColor))
        .cornerRadius(8)
    }

    @ViewBuilder
    private var recordingStatusBar: some View {
        VStack(spacing: 8) {
            HStack {
                Circle()
                    .fill(recordingManager.isWindowVisible ? .red : .orange)
                    .frame(width: 10, height: 10)
                Text(recordingManager.isWindowVisible ? "Recording" : "Window Hidden")
                    .font(.headline)
                    .foregroundColor(recordingManager.isWindowVisible ? .red : .orange)

                Spacer()

                Text(recordingManager.elapsedTime)
                    .font(.system(.body, design: .monospaced))
                    .foregroundColor(.secondary)
            }

            HStack {
                Label("Frames: \(recordingManager.frameCount)", systemImage: "film")
                    .font(.caption)
                    .foregroundColor(.secondary)

                Spacer()

                if let size = recordingManager.currentFileSize {
                    Label(size, systemImage: "doc")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
    }
}
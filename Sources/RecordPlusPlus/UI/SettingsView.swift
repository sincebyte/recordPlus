import SwiftUI

struct SettingsView: View {
    @ObservedObject var recordingManager: RecordingManager

    private let presets: [EncoderConfig] = [
        .hd1080p60, .hd1080p30,
        .qhd1440p60, .qhd1440p30,
        .uhd2160p60, .uhd2160p30
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("Video Settings", systemImage: "gearshape.fill")
                .font(.headline)

            Picker("Resolution & Frame Rate", selection: $recordingManager.selectedPreset) {
                ForEach(presets, id: \.displayName) { preset in
                    Text(preset.displayName).tag(preset)
                }
            }
            .pickerStyle(.menu)
            .labelsHidden()

            Divider()

            Label("Chroma Key Settings", systemImage: "camera.filters")
                .font(.headline)

            ColorPicker("Key Color", selection: $recordingManager.keyColor)

            VStack(alignment: .leading, spacing: 4) {
                Text("Threshold: \(recordingManager.threshold, specifier: "%.3f")")
                    .font(.caption)
                Slider(value: $recordingManager.threshold, in: 0.0...1.0, step: 0.01)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Smoothness: \(recordingManager.smoothness, specifier: "%.3f")")
                    .font(.caption)
                Slider(value: $recordingManager.smoothness, in: 0.0...0.5, step: 0.01)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Spill Suppression: \(recordingManager.spillSuppression, specifier: "%.2f")")
                    .font(.caption)
                Slider(value: $recordingManager.spillSuppression, in: 0.0...1.0, step: 0.05)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Corner Radius: \(Int(recordingManager.cornerRadius))")
                    .font(.caption)
                Slider(value: $recordingManager.cornerRadius, in: 0...60, step: 1)
            }

            Divider()

            Label("Border", systemImage: "square.dashed")
                .font(.headline)

            ColorPicker("Border Color", selection: $recordingManager.borderColor)

            VStack(alignment: .leading, spacing: 4) {
                Text("Border Width: \(Int(recordingManager.borderWidth))")
                    .font(.caption)
                Slider(value: $recordingManager.borderWidth, in: 0...20, step: 0.5)
            }

            Divider()

            if let outputURL = recordingManager.outputURL {
                Label("Output: \(outputURL.lastPathComponent)", systemImage: "folder")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
        }
        .padding()
        .frame(width: 260)
    }
}
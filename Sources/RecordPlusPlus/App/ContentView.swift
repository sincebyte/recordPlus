import SwiftUI

struct ContentView: View {
    @StateObject private var windowListVM = WindowListViewModel()
    @StateObject private var recordingManager = RecordingManager()
    @StateObject private var permissionManager = PermissionManager()
    @State private var showSettings = false

    var body: some View {
        NavigationSplitView {
            sidebar
        } detail: {
            detailView
        }
        .frame(minWidth: 700, minHeight: 500)
        .task {
            await permissionManager.checkPermissions()
            if permissionManager.allPermissionsGranted {
                await windowListVM.refreshWindows()
            }
        }
        .onChange(of: permissionManager.screenRecordingGranted) { granted in
            if granted {
                Task { await windowListVM.refreshWindows() }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            Task {
                await permissionManager.checkPermissions()
                if permissionManager.allPermissionsGranted {
                    await windowListVM.refreshWindows()
                }
            }
        }
    }

    @ViewBuilder
    private var sidebar: some View {
        List {
            if !permissionManager.allPermissionsGranted {
                Section {
                    permissionRequestView
                }
            }

            if windowListVM.isLoading {
                Section {
                    HStack {
                        Spacer()
                        ProgressView()
                            .scaleEffect(0.8)
                        Text("Loading windows...")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Spacer()
                    }
                    .padding(.vertical, 8)
                }
            } else if let error = windowListVM.errorMessage {
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Label(error, systemImage: "exclamationmark.triangle")
                            .font(.caption)
                            .foregroundColor(.red)
                        Button("Retry") {
                            Task { await windowListVM.refreshWindows() }
                        }
                        .font(.caption)
                    }
                    .padding(.vertical, 4)
                }
            }

            ForEach(windowListVM.applications, id: \.0) { appName, windows in
                Section(header: Text(appName).font(.headline)) {
                    ForEach(windows) { window in
                        WindowListRow(window: window, isSelected: windowListVM.selectedWindow == window)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                windowListVM.selectWindow(window)
                                recordingManager.selectedWindow = window
                            }
                    }
                }
            }
        }
        .listStyle(.sidebar)
        .frame(minWidth: 260)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button(action: {
                    Task { await windowListVM.refreshWindows() }
                }) {
                    Image(systemName: "arrow.clockwise")
                }
                .help("Refresh window list")
            }
        }
    }

    @ViewBuilder
    private var detailView: some View {
        VStack(spacing: 0) {
            if let window = windowListVM.selectedWindow {
                selectedWindowInfo(window)
            } else {
                noSelectionView
            }

            Divider()

            RecordingControlView(recordingManager: recordingManager)

            if let error = recordingManager.errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundColor(.red)
                    .padding(.horizontal)
                    .padding(.bottom, 4)
            }
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button(action: { showSettings.toggle() }) {
                    Image(systemName: "gearshape")
                }
                .help("Settings")
                .popover(isPresented: $showSettings) {
                    SettingsView(recordingManager: recordingManager)
                }
            }
        }
    }

    @ViewBuilder
    private func selectedWindowInfo(_ window: WindowInfo) -> some View {
        VStack(spacing: 8) {
            Image(systemName: "macwindow")
                .font(.system(size: 40))
                .foregroundColor(.accentColor)

            Text(window.appName)
                .font(.title2)
                .bold()

            Text(window.title)
                .font(.body)
                .foregroundColor(.secondary)

            Text("\(Int(window.frame.width)) x \(Int(window.frame.height))")
                .font(.caption)
                .foregroundColor(.secondary)
                .monospacedDigit()
        }
        .padding()
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private var noSelectionView: some View {
        VStack(spacing: 16) {
            Image(systemName: "rectangle.on.rectangle")
                .font(.system(size: 48))
                .foregroundColor(.secondary.opacity(0.5))

            Text("Select a window to start recording")
                .font(.title3)
                .foregroundColor(.secondary)

            Text("Choose a window from the sidebar to capture")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private var permissionRequestView: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Screen Recording Required", systemImage: "lock.shield")
                .font(.headline)
                .foregroundColor(.orange)

            Text("Record++ needs permission to capture your screen.")
                .font(.caption)
                .foregroundColor(.secondary)

            Button("Grant Permission") {
                Task {
                    await permissionManager.requestScreenRecordingPermission()
                    if permissionManager.allPermissionsGranted {
                        await windowListVM.refreshWindows()
                    }
                }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
        }
        .padding(.vertical, 8)
    }
}
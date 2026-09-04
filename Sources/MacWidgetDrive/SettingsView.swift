import SwiftUI
import AppKit

// MARK: - Navigation

private enum Nav: Hashable {
    case settings
    case about
}

// MARK: - SettingsView

struct SettingsView: View {
    @ObservedObject var appState: AppState
    @State private var nav: Nav = .settings

    var body: some View {
        HSplitView {
            sidebar.frame(minWidth: 150, maxWidth: 180)
            detail.frame(minWidth: 420)
        }
        .frame(minWidth: 600, minHeight: 420)
    }

    private var sidebar: some View {
        List(selection: $nav) {
            Label("Settings", systemImage: "slider.horizontal.3").tag(Nav.settings)
            Label("About", systemImage: "info.circle").tag(Nav.about)
        }
        .listStyle(.sidebar)
    }

    @ViewBuilder
    private var detail: some View {
        switch nav {
        case .settings:
            RouteSettingsView(appState: appState)
        case .about:
            AboutView()
        }
    }
}

// MARK: - Route settings panel

struct RouteSettingsView: View {
    @ObservedObject var appState: AppState
    @State private var originDraft: String = ""
    @State private var destinationDraft: String = ""
    @State private var didLoadDrafts = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("Route").font(.headline)

                addressField(label: "Starting Address",
                             prompt: "e.g. 1 Infinite Loop, Cupertino, CA",
                             text: $originDraft)
                addressField(label: "Ending Address",
                             prompt: "e.g. 1600 Amphitheatre Parkway, Mountain View, CA",
                             text: $destinationDraft)

                Button("Save Route") {
                    appState.updateRoute(origin: originDraft, destination: destinationDraft)
                }

                Divider()

                Text("Update Frequency").font(.headline)

                Form {
                    LabeledContent("Check every") {
                        Stepper(value: $appState.refreshIntervalMinutes, in: 1...120) {
                            Text("\(appState.refreshIntervalMinutes) minute\(appState.refreshIntervalMinutes == 1 ? "" : "s")")
                        }
                        .frame(maxWidth: 220)
                    }
                }

                Divider()

                Text("System").font(.headline)

                Toggle("Launch at login", isOn: launchAtLoginBinding)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(20)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onAppear {
            guard !didLoadDrafts else { return }
            originDraft = appState.originAddress
            destinationDraft = appState.destinationAddress
            didLoadDrafts = true
        }
    }

    /// Label on one row, full-width text field on the next — stretches with the window.
    private func addressField(label: String, prompt: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.subheadline).foregroundColor(.secondary)
            TextField(prompt, text: text)
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: .infinity)
        }
    }

    private var launchAtLoginBinding: Binding<Bool> {
        Binding(
            get: { LoginItem.isEnabled },
            set: { enabled in LoginItem.set(enabled: enabled) }
        )
    }
}

// MARK: - About

struct AboutView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                HStack(spacing: 16) {
                    Image(systemName: "car.fill")
                        .font(.system(size: 48))
                        .foregroundColor(.accentColor)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Mac Widget Drive")
                            .font(.title.bold())
                        Text("Version \(displayVersion)")
                            .foregroundColor(.secondary)
                    }
                }

                Divider()

                VStack(alignment: .leading, spacing: 6) {
                    Text("Description").font(.headline)
                    Text("A lightweight desktop widget that checks live driving time between two addresses on a schedule, shown directly on your desktop wallpaper.")
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Details").font(.headline)
                    infoRow("Built", buildDate)
                    infoRow("Settings", settingsPath)
                    Button("Show in Finder") {
                        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: settingsPath)])
                    }
                    .padding(.top, 4)
                }
            }
            .padding(20)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var displayVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? appVersion
    }

    private var buildDate: String {
        guard let url = Bundle.main.executableURL,
              let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
              let date = attrs[.modificationDate] as? Date else { return "—" }
        let fmt = DateFormatter()
        fmt.dateStyle = .medium
        fmt.timeStyle = .short
        return fmt.string(from: date)
    }

    private var settingsPath: String {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return support.appendingPathComponent("MacWidgetDrive/settings.json").path
    }

    private func infoRow(_ label: String, _ value: String) -> some View {
        HStack(alignment: .top, spacing: 0) {
            Text(label).foregroundColor(.secondary).frame(width: 72, alignment: .leading)
            Text(value).textSelection(.enabled)
        }
    }
}

import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    @ObservedObject var controller: AwakeController
    @State private var selection: WatchedApp.ID?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            GroupBox {
                VStack(alignment: .leading, spacing: 8) {
                    Toggle("Launch Doppio at login", isOn: Binding(
                        get: { controller.launchAtLogin },
                        set: { controller.launchAtLogin = $0 }
                    ))
                    Toggle("Keep the display on", isOn: $controller.keepDisplayOn)
                    Picker("Duration on click:", selection: $controller.defaultDuration) {
                        ForEach(DurationOption.all, id: \.self) { option in
                            Text(option.englishTitle).tag(option.seconds)
                        }
                    }
                    .fixedSize()
                    Picker("Deactivate on battery below:", selection: $controller.lowBatteryThreshold) {
                        Text("Never").tag(0)
                        ForEach([5, 10, 15, 20, 30], id: \.self) { percent in
                            Text("\(percent) %").tag(percent)
                        }
                    }
                    .fixedSize()
                    Toggle("Activate automatically while any of these apps is running", isOn: $controller.autoEnabled)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(4)
            }

            Text("Watched apps").font(.headline)

            List(selection: $selection) {
                if controller.watchedApps.isEmpty {
                    Text("No apps yet. Add one with the + button.")
                        .foregroundStyle(.secondary)
                }
                ForEach(controller.watchedApps) { app in
                    HStack {
                        Image(nsImage: NSWorkspace.shared.icon(forFile: app.path))
                            .resizable()
                            .frame(width: 20, height: 20)
                        Text(app.name)
                        Spacer()
                        if controller.isRunning(app) {
                            Text("Running")
                                .font(.caption)
                                .foregroundStyle(.green)
                        }
                    }
                    .tag(app.id)
                    .contextMenu {
                        Button("Remove") { controller.remove(app) }
                    }
                }
            }
            .frame(minHeight: 200)
            .onDeleteCommand(perform: removeSelected)

            HStack(spacing: 4) {
                Button(action: showAddMenu) {
                    listButtonIcon("plus")
                }

                Button(action: removeSelected) {
                    listButtonIcon("minus")
                }
                .disabled(selection == nil)

                Spacer()
            }
        }
        .padding(20)
        .frame(width: 480, height: 515)
        .toolbar {
            if #available(macOS 26.0, *) {
                ToolbarItem(placement: .principal) {
                    Text("Doppio Settings").font(.headline)
                }
                .sharedBackgroundVisibility(.hidden)
            } else {
                ToolbarItem(placement: .principal) {
                    Text("Doppio Settings").font(.headline)
                }
            }
        }
    }

    /// Pops up the add menu at the cursor. A SwiftUI `Menu` renders at a different size than the − button.
    private func showAddMenu() {
        let menu = NSMenu()
        menu.addItem(ClosureMenuItem(title: "Choose from Applications…", action: pickApp))
        menu.addItem(.separator())
        for app in runningApps() {
            let item = ClosureMenuItem(title: app.localizedName ?? app.bundleIdentifier ?? "?") {
                controller.addRunningApp(app)
            }
            item.image = app.icon.map(resized)
            menu.addItem(item)
        }
        menu.popUp(positioning: nil, at: NSEvent.mouseLocation, in: nil)
    }

    /// Same-sized icon so the + menu and the − button render identically.
    private func listButtonIcon(_ systemName: String) -> some View {
        Image(systemName: systemName)
            .frame(width: 16, height: 16)
    }

    private func runningApps() -> [NSRunningApplication] {
        let watched = Set(controller.watchedApps.map(\.bundleID))
        return NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular && $0.bundleIdentifier != Bundle.main.bundleIdentifier }
            .filter { !watched.contains($0.bundleIdentifier ?? "") }
            .sorted { ($0.localizedName ?? "") < ($1.localizedName ?? "") }
    }

    private func resized(_ image: NSImage) -> NSImage {
        let copy = image.copy() as! NSImage
        copy.size = NSSize(width: 16, height: 16)
        return copy
    }

    private func pickApp() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.allowsMultipleSelection = true
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.prompt = "Add"
        if panel.runModal() == .OK {
            panel.urls.forEach(controller.addApp(at:))
        }
    }

    private func removeSelected() {
        guard let id = selection, let app = controller.watchedApps.first(where: { $0.id == id }) else { return }
        controller.remove(app)
        selection = nil
    }
}

private final class ClosureMenuItem: NSMenuItem {
    private let handler: () -> Void

    init(title: String, action handler: @escaping () -> Void) {
        self.handler = handler
        super.init(title: title, action: #selector(run), keyEquivalent: "")
        target = self
    }

    required init(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    @objc private func run() { handler() }
}

import AppKit
import Combine
import ServiceManagement

struct DurationOption: Hashable {
    let title: String
    let englishTitle: String
    /// `nil` means indefinitely.
    let seconds: TimeInterval?

    static let all: [DurationOption] = [
        DurationOption(title: "Indefinidamente", englishTitle: "Indefinitely", seconds: nil),
        DurationOption(title: "15 minutos", englishTitle: "15 minutes", seconds: 15 * 60),
        DurationOption(title: "30 minutos", englishTitle: "30 minutes", seconds: 30 * 60),
        DurationOption(title: "1 hora", englishTitle: "1 hour", seconds: 60 * 60),
        DurationOption(title: "2 horas", englishTitle: "2 hours", seconds: 2 * 60 * 60),
        DurationOption(title: "5 horas", englishTitle: "5 hours", seconds: 5 * 60 * 60),
    ]
}

struct WatchedApp: Codable, Identifiable, Hashable {
    let bundleID: String
    let name: String
    let path: String

    var id: String { bundleID }
}

@MainActor
final class AwakeController: ObservableObject {
    // Manual mode
    @Published private(set) var manualActive = false
    @Published private(set) var manualUntil: Date?

    // Settings (persisted)
    @Published var autoEnabled: Bool { didSet { defaults.set(autoEnabled, forKey: Keys.autoEnabled); refresh() } }
    @Published var keepDisplayOn: Bool { didSet { defaults.set(keepDisplayOn, forKey: Keys.keepDisplayOn); refresh() } }
    /// Duration used when toggling with a left click. `nil` means indefinitely.
    @Published var defaultDuration: TimeInterval? {
        didSet { defaults.set(defaultDuration ?? 0, forKey: Keys.defaultDuration) }
    }
    /// Battery percentage at or below which Doppio stops keeping the Mac awake. 0 disables it.
    @Published var lowBatteryThreshold: Int {
        didSet { defaults.set(lowBatteryThreshold, forKey: Keys.lowBatteryThreshold); refresh() }
    }
    @Published private(set) var watchedApps: [WatchedApp] { didSet { saveWatchedApps(); refresh() } }

    // Derived state
    @Published private(set) var triggeringApps: [WatchedApp] = []
    @Published private(set) var isActive = false
    /// On battery at or below `lowBatteryThreshold`; blocks every activation.
    @Published private(set) var batteryLow = false

    private let blocker = SleepBlocker()
    private let defaults = UserDefaults.standard
    private var cancellables = Set<AnyCancellable>()
    private var expiryTimer: Timer?
    private var batteryMonitor: BatteryMonitor?

    private enum Keys {
        static let autoEnabled = "autoEnabled"
        static let keepDisplayOn = "keepDisplayOn"
        static let watchedApps = "watchedApps"
        static let defaultDuration = "defaultDuration"
        static let lowBatteryThreshold = "lowBatteryThreshold"
    }

    init() {
        defaults.register(defaults: [Keys.autoEnabled: true, Keys.keepDisplayOn: true, Keys.lowBatteryThreshold: 10])
        autoEnabled = defaults.bool(forKey: Keys.autoEnabled)
        keepDisplayOn = defaults.bool(forKey: Keys.keepDisplayOn)
        lowBatteryThreshold = defaults.integer(forKey: Keys.lowBatteryThreshold)
        let storedDuration = defaults.double(forKey: Keys.defaultDuration)
        defaultDuration = storedDuration > 0 ? storedDuration : nil
        if let data = defaults.data(forKey: Keys.watchedApps),
           let apps = try? JSONDecoder().decode([WatchedApp].self, from: data) {
            watchedApps = apps
        } else {
            watchedApps = []
        }

        NSWorkspace.shared.publisher(for: \.runningApplications)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.refresh() }
            .store(in: &cancellables)

        batteryMonitor = BatteryMonitor { [weak self] in
            MainActor.assumeIsolated { self?.refresh() }
        }

        refresh()
    }

    // MARK: Manual control

    func activate(for duration: TimeInterval?) {
        expiryTimer?.invalidate()
        expiryTimer = nil
        manualActive = true
        manualUntil = duration.map { Date().addingTimeInterval($0) }
        if let duration {
            expiryTimer = Timer.scheduledTimer(withTimeInterval: duration, repeats: false) { [weak self] _ in
                Task { @MainActor in self?.deactivate() }
            }
        }
        refresh()
    }

    func deactivate() {
        expiryTimer?.invalidate()
        expiryTimer = nil
        manualActive = false
        manualUntil = nil
        refresh()
    }

    func toggle() {
        manualActive ? deactivate() : activate(for: defaultDuration)
    }

    // MARK: Watched apps

    func addApp(at url: URL) {
        guard let bundle = Bundle(url: url), let bundleID = bundle.bundleIdentifier else { return }
        guard !watchedApps.contains(where: { $0.bundleID == bundleID }) else { return }
        let name = (bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String)
            ?? (bundle.object(forInfoDictionaryKey: "CFBundleName") as? String)
            ?? url.deletingPathExtension().lastPathComponent
        watchedApps.append(WatchedApp(bundleID: bundleID, name: name, path: url.path))
        watchedApps.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    func addRunningApp(_ app: NSRunningApplication) {
        guard let url = app.bundleURL else { return }
        addApp(at: url)
    }

    func remove(_ app: WatchedApp) {
        watchedApps.removeAll { $0.bundleID == app.bundleID }
    }

    func isRunning(_ app: WatchedApp) -> Bool {
        triggeringApps.contains(app)
    }

    // MARK: Launch at login

    var launchAtLogin: Bool {
        get { SMAppService.mainApp.status == .enabled }
        set {
            do {
                if newValue { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            } catch {
                NSLog("Launch at login change failed: \(error)")
            }
            objectWillChange.send()
        }
    }

    // MARK: State

    private func refresh() {
        let runningIDs = Set(NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier))
        let triggering = autoEnabled ? watchedApps.filter { runningIDs.contains($0.bundleID) } : []
        if triggering != triggeringApps { triggeringApps = triggering }

        let low = lowBatteryThreshold > 0 && (batteryMonitor?.isBelow(lowBatteryThreshold) ?? false)
        if low != batteryLow { batteryLow = low }
        // A manual session ends for good on low battery; app triggers resume once charging.
        if low && manualActive {
            expiryTimer?.invalidate()
            expiryTimer = nil
            manualActive = false
            manualUntil = nil
        }

        let shouldBeActive = !low && (manualActive || !triggering.isEmpty)
        if shouldBeActive {
            let reason = manualActive
                ? "Doppio: manual"
                : "Doppio: \(triggering.map(\.name).joined(separator: ", "))"
            blocker.hold(keepDisplayOn: keepDisplayOn, reason: reason)
        } else {
            blocker.release()
        }
        if isActive != shouldBeActive { isActive = shouldBeActive }
    }

    private func saveWatchedApps() {
        if let data = try? JSONEncoder().encode(watchedApps) {
            defaults.set(data, forKey: Keys.watchedApps)
        }
    }
}

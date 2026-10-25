import AppKit
import Combine

/// Menu bar icon: left click toggles, right click (or ⌃/⌥ click) opens the menu.
@MainActor
final class StatusItemController: NSObject, NSMenuDelegate {
    private let controller: AwakeController
    private let openSettings: () -> Void
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private var cancellables = Set<AnyCancellable>()

    init(controller: AwakeController, openSettings: @escaping () -> Void) {
        self.controller = controller
        self.openSettings = openSettings
        super.init()

        if let button = statusItem.button {
            button.target = self
            button.action = #selector(handleClick)
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }

        controller.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.updateIcon() }
            .store(in: &cancellables)
        updateIcon()
    }

    private func updateIcon() {
        guard let button = statusItem.button else { return }
        button.image = SteamingCupIcon.image(active: controller.isActive)
        button.toolTip = tooltip()
    }

    private func tooltip() -> String {
        if controller.batteryLow {
            return "En pausa: batería por debajo del \(controller.lowBatteryThreshold) %"
        }
        if controller.manualActive {
            if let until = controller.manualUntil {
                return "Activo hasta las \(until.formatted(date: .omitted, time: .shortened))"
            }
            return "Activo indefinidamente"
        }
        if !controller.triggeringApps.isEmpty {
            return "Activo por: \(controller.triggeringApps.map(\.name).joined(separator: ", "))"
        }
        return "Inactivo"
    }

    @objc private func handleClick() {
        guard let event = NSApp.currentEvent else { return }
        let wantsMenu = event.type == .rightMouseUp
            || event.modifierFlags.contains(.control)
            || event.modifierFlags.contains(.option)
        if wantsMenu {
            showMenu()
        } else {
            controller.toggle()
        }
    }

    private func showMenu() {
        let menu = buildMenu()
        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        statusItem.menu = nil
    }

    private func buildMenu() -> NSMenu {
        let menu = NSMenu()

        let status = NSMenuItem(title: tooltip(), action: nil, keyEquivalent: "")
        status.isEnabled = false
        menu.addItem(status)
        menu.addItem(.separator())

        if controller.manualActive {
            menu.addItem(item("Desactivar", #selector(deactivate)))
        }
        let activateItem = NSMenuItem(title: "Activar", action: nil, keyEquivalent: "")
        let sub = NSMenu()
        for (index, option) in DurationOption.all.enumerated() {
            let entry = item(option.title, #selector(activateDuration(_:)))
            entry.tag = index
            entry.state = option.seconds == controller.defaultDuration ? .on : .off
            sub.addItem(entry)
        }
        activateItem.submenu = sub
        menu.addItem(activateItem)

        menu.addItem(.separator())
        let auto = item("Activar automáticamente con apps", #selector(toggleAuto))
        auto.state = controller.autoEnabled ? .on : .off
        menu.addItem(auto)
        let display = item("Mantener pantalla encendida", #selector(toggleDisplay))
        display.state = controller.keepDisplayOn ? .on : .off
        menu.addItem(display)

        menu.addItem(.separator())
        menu.addItem(item("Ajustes…", #selector(showSettings), key: ","))
        menu.addItem(item("Salir", #selector(quit), key: "q"))
        return menu
    }

    private func item(_ title: String, _ action: Selector, key: String = "") -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = self
        return item
    }

    @objc private func activateDuration(_ sender: NSMenuItem) {
        controller.activate(for: DurationOption.all[sender.tag].seconds)
    }

    @objc private func deactivate() { controller.deactivate() }
    @objc private func toggleAuto() { controller.autoEnabled.toggle() }
    @objc private func toggleDisplay() { controller.keepDisplayOn.toggle() }
    @objc private func showSettings() { openSettings() }
    @objc private func quit() { NSApp.terminate(nil) }
}

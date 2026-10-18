import Foundation
import ServiceManagement

public class AutostartManager {
    public static let shared = AutostartManager()

    private init() {}

    public var isAutostartEnabled: Bool {
        if #available(macOS 13.0, *) {
            let status = SMAppService.mainApp.status
            return status == .enabled || status == .requiresApproval
        }
        return false
    }

    private let initializedKey = "AltSwitch_AutostartInitialized"

    /// On the first launch of an installed copy, autostart is switched on once. Later the user's
    /// choice (menu or setup assistant) is never overridden. Builds outside an Applications
    /// folder are left alone so a development copy does not become the login item.
    public func enableOnFirstLaunchIfInstalled() {
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: initializedKey) else { return }
        let appPath = Bundle.main.bundleURL.resolvingSymlinksInPath().path
        let applicationFolders = FileManager.default
            .urls(for: .applicationDirectory, in: [.localDomainMask, .userDomainMask])
            .map { $0.resolvingSymlinksInPath().path + "/" }
        guard applicationFolders.contains(where: { appPath.hasPrefix($0) }) else { return }
        defaults.set(true, forKey: initializedKey)
        _ = setAutostart(enabled: true, openSettingsIfApprovalNeeded: false)
    }

    public func setAutostart(enabled: Bool, openSettingsIfApprovalNeeded: Bool = true) -> Bool {
        if #available(macOS 13.0, *) {
            do {
                if enabled {
                    if SMAppService.mainApp.status != .enabled {
                        try SMAppService.mainApp.register()
                    }
                } else {
                    if SMAppService.mainApp.status != .notRegistered {
                        try SMAppService.mainApp.unregister()
                    }
                }

                if openSettingsIfApprovalNeeded && SMAppService.mainApp.status == .requiresApproval {
                    SMAppService.openSystemSettingsLoginItems()
                }
                return true
            } catch {
                NSLog("AltSwitch: AutostartManager error: %@", error.localizedDescription)
                if openSettingsIfApprovalNeeded && SMAppService.mainApp.status == .requiresApproval {
                    SMAppService.openSystemSettingsLoginItems()
                }
                return false
            }
        }
        return false
    }
}

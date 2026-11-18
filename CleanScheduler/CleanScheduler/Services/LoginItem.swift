import ServiceManagement

// MARK: - Open at login

enum LoginItem {
    static var isEnabled: Bool { SMAppService.mainApp.status == .enabled }
    static var needsApproval: Bool { SMAppService.mainApp.status == .requiresApproval }

    /// Returns an error message, or nil on success.
    static func set(_ enabled: Bool) -> String? {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            if enabled && needsApproval {
                return "Allow Clean Scheduler in System Settings › General › Login Items."
            }
            return nil
        } catch {
            return "Couldn't change Open at login: \(error.localizedDescription)"
        }
    }
}

import ServiceManagement

enum LaunchAtLogin {
    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    static func setEnabled(_ enable: Bool) {
        let service = SMAppService.mainApp
        if enable {
            if service.status != .enabled {
                try? service.register()
                if service.status == .requiresApproval {
                    SMAppService.openSystemSettingsLoginItems()
                }
            }
        } else {
            if service.status == .enabled {
                try? service.unregister()
            }
        }
    }
}

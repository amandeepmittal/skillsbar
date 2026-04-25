import Foundation
import Combine
import ServiceManagement

@MainActor
final class LoginItemController: ObservableObject {
    @Published private(set) var status: SMAppService.Status
    @Published var errorMessage: String?

    private var service: SMAppService {
        .mainApp
    }

    init() {
        status = SMAppService.mainApp.status
    }

    var isEnabled: Bool {
        status == .enabled || status == .requiresApproval
    }

    var requiresApproval: Bool {
        status == .requiresApproval
    }

    func refresh() {
        status = service.status
    }

    func setEnabled(_ enabled: Bool) {
        refresh()

        do {
            if enabled {
                if status != .enabled && status != .requiresApproval {
                    try service.register()
                }
            } else if status != .notRegistered && status != .notFound {
                try service.unregister()
            }

            errorMessage = nil
        } catch {
            errorMessage = "Couldn't update Start at Login: \(error.localizedDescription)"
        }

        refresh()
    }

    func openLoginItemsSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }
}

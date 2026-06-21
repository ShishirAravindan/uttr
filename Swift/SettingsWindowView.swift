import SwiftUI

struct SettingsWindowView: View {
    @ObservedObject var settings: SettingsManager
    @ObservedObject var permissions: PermissionManager

    var body: some View {
        SettingsTabView(settings: settings, permissions: permissions)
            .frame(width: 520)
    }
}

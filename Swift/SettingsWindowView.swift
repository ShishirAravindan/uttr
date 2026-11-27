import SwiftUI

struct SettingsWindowView: View {
    @ObservedObject var settings: SettingsManager
    @ObservedObject var permissions: PermissionManager
    @ObservedObject var voices: ReadAloudVoices

    var body: some View {
        SettingsTabView(settings: settings, permissions: permissions, voices: voices)
            .frame(width: 520)
    }
}

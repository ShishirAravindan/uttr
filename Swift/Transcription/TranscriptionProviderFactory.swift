enum TranscriptionProviderFactory {
    @MainActor
    static func make(id: String) -> TranscriptionProvider {
        switch id {
        case "fluidaudio.parakeet.v2":
            return FluidAudioProvider(version: .v2)
        default:
            return FluidAudioProvider(version: .v3)
        }
    }
}

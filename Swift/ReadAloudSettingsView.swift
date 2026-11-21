import SwiftUI

/// Settings → Read Aloud: the voice, its speed, and for mlx-audio voices the
/// model's download state and controls, plus the runtime and downloaded models.
struct ReadAloudSettingsSection: View {
    @ObservedObject var settings: SettingsManager
    @ObservedObject var voices: ReadAloudVoices
    @Environment(\.colorScheme) var scheme

    private var selected: ReadAloudVoice { settings.readAloudVoice }

    private var showsRuntime: Bool {
        if case .mlx = selected { return true }
        return voices.runtimeStatus != .notInstalled
            || MLXSpeechModel.presets.contains { voices.status(of: $0) == .downloaded }
    }

    var body: some View {
        SectionBlock(label: "Read Aloud") {
            SettingsCard(scheme: scheme) {
                SettingRow(label: "Voice", scheme: scheme) {
                    VoiceMenu(selected: selected, voices: voices, scheme: scheme) {
                        settings.updateReadAloudVoice($0)
                    }
                }
                if let notice = voices.notice {
                    Caption(text: notice, scheme: scheme, isWarning: false)
                        .padding(.horizontal, 16)
                        .padding(.bottom, 10)
                        .padding(.top, -4)
                }
                RowDivider(scheme: scheme)
                SpeedRow(speed: settings.readAloud.speed, scheme: scheme) { settings.updateReadAloudSpeed($0) }
                if case .mlx(let model) = selected {
                    RowDivider(scheme: scheme)
                    ModelStatusRow(model: model, voices: voices, scheme: scheme)
                    MLXModelControls(model: model, settings: settings, scheme: scheme)
                        .id(model.id)
                }
            }
            if showsRuntime {
                RuntimeCard(settings: settings, voices: voices, scheme: scheme)
            }
        }
    }
}

// MARK: - Voice menu

private struct VoiceMenu: View {
    let selected: ReadAloudVoice
    @ObservedObject var voices: ReadAloudVoices
    let scheme: ColorScheme
    let onSelect: (ReadAloudVoice) -> Void

    var body: some View {
        Menu {
            Button("Kokoro — natural, on the Neural Engine") { onSelect(.kokoro) }
            Button("System voice — built into macOS") { onSelect(.system) }
            Divider()
            Section("Expressive · mlx-audio on the GPU") {
                ForEach(MLXSpeechModel.presets) { model in
                    Button {
                        onSelect(.mlx(model))
                    } label: {
                        Label("\(model.name) — \(model.summary) · \(sizeLabel(model))",
                              systemImage: voices.status(of: model) == .downloaded ? "checkmark.circle" : "arrow.down.circle")
                    }
                }
            }
        } label: {
            PickerLabel(text: selected.displayName, scheme: scheme)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
    }

    private func sizeLabel(_ model: MLXSpeechModel) -> String {
        voices.status(of: model) == .downloaded ? "downloaded" : "≈\(model.approximateSize)"
    }
}

// MARK: - Speed

private struct SpeedRow: View {
    let speed: Double
    let scheme: ColorScheme
    let onCommit: (Double) -> Void
    @State private var draft = 1.0

    var body: some View {
        SettingRow(label: "Speed", scheme: scheme) {
            HStack(spacing: 10) {
                Slider(value: $draft, in: ReadAloudSettings.speedRange, step: 0.05,
                       onEditingChanged: { editing in if !editing { onCommit(draft) } })
                .frame(width: 170)
                .accessibilityLabel("Read-aloud speed")
                Text(String(format: "%.2f×", draft))
                    .font(.system(size: 12).monospacedDigit())
                    .foregroundColor(.textSecondary(for: scheme))
                    .frame(width: 40, alignment: .trailing)
            }
        }
        .onAppear { draft = speed }
        .onChange(of: speed) { _, value in draft = value }
    }
}

// MARK: - Model status

private struct ModelStatusRow: View {
    let model: MLXSpeechModel
    @ObservedObject var voices: ReadAloudVoices
    let scheme: ColorScheme

    private var status: ReadAloudVoices.ModelStatus { voices.status(of: model) }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Model")
                        .font(.system(size: 13))
                        .foregroundColor(.textPrimary(for: scheme))
                    Text(model.repo)
                        .font(.system(size: 11))
                        .foregroundColor(.textTertiary(for: scheme))
                        .textSelection(.enabled)
                }
                Spacer()
                Text(statusText)
                    .font(.system(size: 12))
                    .foregroundColor(isFailure ? Color(nsColor: .systemOrange) : .textSecondary(for: scheme))
                    .multilineTextAlignment(.trailing)
                    .fixedSize(horizontal: false, vertical: true)
                actions
            }
            if case .downloading(let progress) = status {
                if let fraction = progress?.fraction {
                    ProgressView(value: fraction).controlSize(.small)
                } else {
                    ProgressView().progressViewStyle(.linear).controlSize(.small)
                }
            }
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 16)
    }

    @ViewBuilder
    private var actions: some View {
        switch status {
        case .downloading:
            SettingsActionButton(icon: "xmark.circle", label: "Cancel download", scheme: scheme) {
                voices.cancelDownload(model)
            }
        case .downloaded:
            SettingsActionButton(icon: "folder", label: "Show \(model.name) in Finder", scheme: scheme) {
                voices.reveal(model)
            }
        case .notDownloaded, .failed:
            SettingsActionButton(icon: "arrow.down.circle", label: "Download \(model.name)", scheme: scheme) {
                voices.install(model)
            }
        }
    }

    private var isFailure: Bool {
        if case .failed = status { return true }
        return false
    }

    private var statusText: String {
        switch status {
        case .notDownloaded:
            return "Not downloaded · ≈\(model.approximateSize)"
        case .downloading(let progress):
            if case .installing(let message) = voices.runtimeStatus { return message }
            guard let progress else { return "Starting download…" }
            if progress.phase == .verifying { return "Checking the model loads…" }
            guard progress.total > 0 else { return "Downloading…" }
            let done = ByteCountFormatter.string(fromByteCount: progress.bytes, countStyle: .file)
            let total = ByteCountFormatter.string(fromByteCount: progress.total, countStyle: .file)
            return "\(Int((progress.fraction ?? 0) * 100))% · \(done) of \(total)"
        case .downloaded:
            if voices.workerState == .ready(model.repo) { return "Loaded and warm" }
            if voices.workerState == .loading(model.repo) { return "Loading into memory…" }
            return "Downloaded"
        case .failed(let message):
            return message
        }
    }
}

// MARK: - Model controls

/// Controls for the preset's own options. Changes apply from the next sentence read.
private struct MLXModelControls: View {
    let model: MLXSpeechModel
    @ObservedObject var settings: SettingsManager
    let scheme: ColorScheme

    @State private var style = ""
    @State private var exaggeration = MLXModelOptions.defaultExaggeration
    @State private var cfgWeight = MLXModelOptions.defaultCFGWeight
    @State private var temperature = 0.8
    @State private var showsAdvanced = false
    @FocusState private var isStyleFocused: Bool

    private var options: MLXModelOptions { settings.modelOptions(for: model) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if !model.voices.isEmpty {
                RowDivider(scheme: scheme)
                SettingRow(label: "Speaker", scheme: scheme) {
                    Menu {
                        ForEach(model.voices, id: \.self) { voice in
                            Button(voice.replacingOccurrences(of: "_", with: " ").capitalized) {
                                update { $0.voice = voice == model.defaultVoice ? nil : voice }
                            }
                        }
                    } label: {
                        PickerLabel(text: (options.voice ?? model.defaultVoice ?? "")
                            .replacingOccurrences(of: "_", with: " ").capitalized, scheme: scheme, minWidth: 140)
                    }
                    .menuStyle(.borderlessButton)
                    .fixedSize()
                }
            }

            if model.controls.contains(.style) {
                RowDivider(scheme: scheme)
                styleEditor
            }

            if model.controls.contains(.exaggeration) {
                RowDivider(scheme: scheme)
                SliderRow(label: "Exaggeration", caption: "Higher is more dramatic and emotional.",
                          value: $exaggeration, range: 0.25...2.0, scheme: scheme) {
                    update { $0.exaggeration = exaggeration == MLXModelOptions.defaultExaggeration ? nil : exaggeration }
                }
            }

            if model.controls.contains(.cfgWeight) {
                RowDivider(scheme: scheme)
                SliderRow(label: "Pace guidance", caption: "Lower is slower and more deliberate.",
                          value: $cfgWeight, range: 0...1, scheme: scheme) {
                    update { $0.cfgWeight = cfgWeight == MLXModelOptions.defaultCFGWeight ? nil : cfgWeight }
                }
            }

            RowDivider(scheme: scheme)
            DisclosureGroup(isExpanded: $showsAdvanced) {
                SliderRow(label: "Variation", caption: "Sampling temperature. Higher varies delivery more, and can garble words.",
                          value: $temperature, range: 0.1...1.2, scheme: scheme) {
                    update { $0.temperature = temperature == model.defaultTemperature ? nil : temperature }
                }
                .padding(.horizontal, -16)
            } label: {
                Text("Advanced")
                    .font(.system(size: 12))
                    .foregroundColor(.textSecondary(for: scheme))
            }
            .padding(.vertical, 10)
            .padding(.horizontal, 16)
        }
        .onAppear(perform: load)
    }

    private var styleEditor: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(model.styleMode == .voiceDesign ? "Voice description" : "Style direction")
                .font(.system(size: 13))
                .foregroundColor(.textPrimary(for: scheme))
            Caption(text: model.styleMode == .voiceDesign
                    ? "Describe the narrator in plain words: age, warmth, pace, accent. The model builds the voice from it."
                    : "Tell the speaker how to read, for example \"calm and thoughtful\" or \"bright and playful\".",
                    scheme: scheme, isWarning: false)
            TextField(model.defaultStyle ?? "", text: $style, axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 12))
                .lineLimit(2...4)
                .focused($isStyleFocused)
                .onSubmit(commitStyle)
                .onChange(of: isStyleFocused) { _, focused in if !focused { commitStyle() } }
                .accessibilityLabel(model.styleMode == .voiceDesign ? "Voice description" : "Style direction")
            HStack {
                Spacer()
                Button("Restore default") {
                    style = model.defaultStyle ?? ""
                    update { $0.style = nil }
                }
                .disabled(options.style == nil)
                .controlSize(.small)
            }
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 16)
    }

    private func load() {
        style = options.style ?? model.defaultStyle ?? ""
        exaggeration = options.exaggeration ?? MLXModelOptions.defaultExaggeration
        cfgWeight = options.cfgWeight ?? MLXModelOptions.defaultCFGWeight
        temperature = options.temperature ?? model.defaultTemperature
    }

    private func commitStyle() {
        let trimmed = style.trimmingCharacters(in: .whitespacesAndNewlines)
        update { $0.style = trimmed.isEmpty || trimmed == model.defaultStyle ? nil : trimmed }
    }

    private func update(_ change: (inout MLXModelOptions) -> Void) {
        var options = self.options
        change(&options)
        settings.updateModelOptions(options, for: model)
    }
}

private struct SliderRow: View {
    let label: String
    let caption: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let scheme: ColorScheme
    let onCommit: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 10) {
                Text(label)
                    .font(.system(size: 13))
                    .foregroundColor(.textPrimary(for: scheme))
                Spacer()
                Slider(value: $value, in: range, onEditingChanged: { editing in if !editing { onCommit() } })
                .frame(width: 170)
                .accessibilityLabel(label)
                Text(String(format: "%.2f", value))
                    .font(.system(size: 12).monospacedDigit())
                    .foregroundColor(.textSecondary(for: scheme))
                    .frame(width: 40, alignment: .trailing)
            }
            Caption(text: caption, scheme: scheme, isWarning: false)
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 16)
    }
}

// MARK: - Runtime and models

private struct RuntimeCard: View {
    @ObservedObject var settings: SettingsManager
    @ObservedObject var voices: ReadAloudVoices
    let scheme: ColorScheme

    private static let unloadChoices = [1, 5, 15, 30, 60]

    var body: some View {
        SettingsCard(scheme: scheme) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Text("mlx-audio runtime")
                        .font(.system(size: 13))
                        .foregroundColor(.textPrimary(for: scheme))
                    Spacer()
                    runtimeStatus
                    runtimeActions
                }
                Caption(text: "Speech-LLM voices run in a local Python worker on the Apple Silicon GPU. uttr installs mlx-audio into its own environment with uv, or with Python 3.11 or later if uv isn't installed.",
                        scheme: scheme, isWarning: false)
            }
            .padding(.vertical, 12)
            .padding(.horizontal, 16)

            RowDivider(scheme: scheme)
            SettingRow(label: "Worker", scheme: scheme) {
                HStack(spacing: 6) {
                    Text(workerText)
                        .font(.system(size: 12))
                        .foregroundColor(.textSecondary(for: scheme))
                        .multilineTextAlignment(.trailing)
                    if case .ready = voices.workerState {
                        SettingsActionButton(icon: "eject", label: "Unload the model now", scheme: scheme) {
                            voices.unloadModel()
                        }
                    }
                }
            }

            RowDivider(scheme: scheme)
            SettingRow(label: "Unload after", scheme: scheme) {
                Menu {
                    ForEach(Self.unloadChoices, id: \.self) { minutes in
                        Button(unloadLabel(minutes)) { settings.updateReadAloudIdleUnload(minutes: minutes) }
                    }
                } label: {
                    PickerLabel(text: unloadLabel(settings.readAloud.idleUnloadMinutes), scheme: scheme, minWidth: 160)
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
            }

            RowDivider(scheme: scheme)
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Text("Downloaded models")
                        .font(.system(size: 13))
                        .foregroundColor(.textPrimary(for: scheme))
                    Spacer()
                    Text("\(downloadedCount) of \(MLXSpeechModel.presets.count)")
                        .font(.system(size: 12))
                        .foregroundColor(.textSecondary(for: scheme))
                    SettingsActionButton(icon: "arrow.clockwise", label: "Check again for downloaded models", scheme: scheme) {
                        voices.refresh()
                    }
                    SettingsActionButton(icon: "folder", label: "Manage models in Finder", scheme: scheme) {
                        voices.revealModelsFolder()
                    }
                }
                Caption(text: "Models live in the Hugging Face cache (\(abbreviated(voices.modelsFolder.path))). To free space, move a model's models--… folder to the Trash; uttr notices when Settings opens again.",
                        scheme: scheme, isWarning: false)
            }
            .padding(.vertical, 12)
            .padding(.horizontal, 16)
        }
    }

    @ViewBuilder
    private var runtimeStatus: some View {
        switch voices.runtimeStatus {
        case .notInstalled:
            Text("Not installed").font(.system(size: 12)).foregroundColor(.textSecondary(for: scheme))
        case .installing(let message):
            HStack(spacing: 6) {
                ProgressView().controlSize(.small)
                Text(message).font(.system(size: 12)).foregroundColor(.textSecondary(for: scheme))
            }
        case .installed:
            Text("Installed").font(.system(size: 12)).foregroundColor(.textSecondary(for: scheme))
        case .failed(let message):
            Text(message)
                .font(.system(size: 12))
                .foregroundColor(Color(nsColor: .systemOrange))
                .multilineTextAlignment(.trailing)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder
    private var runtimeActions: some View {
        switch voices.runtimeStatus {
        case .installing:
            EmptyView()
        case .installed:
            SettingsActionButton(icon: "arrow.triangle.2.circlepath", label: "Reinstall or update mlx-audio", scheme: scheme) {
                voices.installRuntime()
            }
            SettingsActionButton(icon: "folder", label: "Show the runtime and worker log in Finder", scheme: scheme) {
                voices.revealRuntimeFolder()
            }
        case .notInstalled, .failed:
            SettingsActionButton(icon: "arrow.down.circle", label: "Install mlx-audio", scheme: scheme) {
                voices.installRuntime()
            }
        }
    }

    private var workerText: String {
        switch voices.workerState {
        case .stopped: return "Not running · starts on the next read"
        case .starting: return "Starting…"
        case .loading(let repo): return "Loading \(name(of: repo))…"
        case .ready(let repo): return "Running · \(name(of: repo)) loaded"
        case .failed(let message): return message
        }
    }

    private var downloadedCount: Int {
        MLXSpeechModel.presets.filter { voices.status(of: $0) == .downloaded }.count
    }

    private func name(of repo: String) -> String {
        MLXSpeechModel.presets.first { $0.repo == repo }?.name ?? repo
    }

    private func unloadLabel(_ minutes: Int) -> String {
        minutes == 1 ? "1 minute idle" : "\(minutes) minutes idle"
    }

    private func abbreviated(_ path: String) -> String {
        (path as NSString).abbreviatingWithTildeInPath
    }
}

private struct Caption: View {
    let text: String
    let scheme: ColorScheme
    let isWarning: Bool

    var body: some View {
        Text(text)
            .font(.system(size: 11))
            .foregroundColor(isWarning ? Color(nsColor: .systemOrange) : .textTertiary(for: scheme))
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

import SwiftUI

/// Settings → Text to Speech: the voice, speed, and preview; for expressive voices,
/// the model's download state and the dials its preset declares, in two tiers:
/// voice character (shown) and advanced (collapsed).
struct TextToSpeechSettings<Shortcut: View>: View {
    @ObservedObject var settings: SettingsManager
    @ObservedObject var voices: ReadAloudVoices
    let shortcut: Shortcut
    @Environment(\.colorScheme) var scheme

    init(settings: SettingsManager, voices: ReadAloudVoices, @ViewBuilder shortcut: () -> Shortcut) {
        self.settings = settings
        self.voices = voices
        self.shortcut = shortcut()
    }

    private var selected: ReadAloudVoice { settings.readAloudVoice }

    var body: some View {
        VStack(alignment: .leading, spacing: 28) {
            SectionBlock(label: "Voice") {
                SettingsCard(scheme: scheme) {
                    shortcut
                    SettingRow(label: "Voice", scheme: scheme) {
                        VoiceMenu(selected: selected, voices: voices, scheme: scheme) {
                            settings.updateReadAloudVoice($0)
                        }
                    }
                    if let notice = voices.notice {
                        Caption(text: notice, scheme: scheme)
                            .padding(.horizontal, 16)
                            .padding(.bottom, 10)
                            .padding(.top, -4)
                    }
                    RowDivider(scheme: scheme)
                    SpeedRow(speed: settings.readAloud.speed, scheme: scheme) { settings.updateReadAloudSpeed($0) }
                    RowDivider(scheme: scheme)
                    PreviewRow(voices: voices, scheme: scheme)
                }
            }

            if case .mlx(let model) = selected {
                SectionBlock(label: model.name) {
                    SettingsCard(scheme: scheme) {
                        ModelStatusRow(model: model, voices: voices, scheme: scheme)
                        ForEach(model.parameters(in: .character)) { parameter in
                            RowDivider(scheme: scheme)
                            ParameterControl(parameter: parameter, model: model, settings: settings, scheme: scheme)
                        }
                    }
                }
                .id(model.id)

                AdvancedCard(model: model, settings: settings, voices: voices, scheme: scheme)
                    .id("advanced-\(model.id)")
            }
        }
    }
}

extension TextToSpeechSettings where Shortcut == EmptyView {
    init(settings: SettingsManager, voices: ReadAloudVoices) {
        self.init(settings: settings, voices: voices) { EmptyView() }
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
            Section("Expressive · on the GPU") {
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

// MARK: - Speed and preview

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
                    .frame(width: 44, alignment: .trailing)
            }
        }
        .onAppear { draft = speed }
        .onChange(of: speed) { _, value in draft = value }
    }
}

private struct PreviewRow: View {
    @ObservedObject var voices: ReadAloudVoices
    let scheme: ColorScheme

    var body: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Preview")
                    .font(.system(size: 13))
                    .foregroundColor(.textPrimary(for: scheme))
                Caption(text: voices.canPreview
                        ? "Plays a short sample with dialogue and a question, with the settings below."
                        : "Available once the selected voice is ready.",
                        scheme: scheme)
            }
            Spacer()
            Button {
                voices.preview()
            } label: {
                Label("Play", systemImage: "play.fill")
            }
            .controlSize(.small)
            .disabled(!voices.canPreview)
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 16)
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
                    Text(model.summary)
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
            if case .downloading(let fraction) = status {
                if let fraction {
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
                voices.download(model)
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
        case .downloading(let fraction):
            guard let fraction else { return "Preparing the model…" }
            return "Downloading \(Int(fraction * 100))% of ≈\(model.approximateSize)"
        case .downloaded:
            switch voices.hostState {
            case .ready(model.repo): return "In memory"
            case .loading(model.repo): return "Loading into memory…"
            default: return "Downloaded"
            }
        case .failed(let message):
            return message
        }
    }
}

// MARK: - Advanced

private struct AdvancedCard: View {
    let model: MLXSpeechModel
    @ObservedObject var settings: SettingsManager
    @ObservedObject var voices: ReadAloudVoices
    let scheme: ColorScheme
    @State private var isExpanded = false

    private static let unloadChoices = [1, 5, 15, 30, 60]

    var body: some View {
        SettingsCard(scheme: scheme) {
            DisclosureGroup(isExpanded: $isExpanded) {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(model.parameters(in: .advanced)) { parameter in
                        RowDivider(scheme: scheme)
                        ParameterControl(parameter: parameter, model: model, settings: settings, scheme: scheme)
                    }
                    RowDivider(scheme: scheme)
                    SettingRow(label: "Sentences per chunk", scheme: scheme) {
                        Picker("", selection: Binding(
                            get: { settings.readAloud.sentencesPerChunk },
                            set: { settings.updateSentencesPerChunk($0) }
                        )) {
                            Text("1").tag(1)
                            Text("2").tag(2)
                            Text("3").tag(3)
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                        .frame(width: 120)
                    }
                    Caption(text: "Fewer sentences start sooner; more give the model context for its tone.", scheme: scheme)
                        .padding(.horizontal, 16)
                        .padding(.bottom, 10)
                        .padding(.top, -4)
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
                    SettingRow(label: "Memory", scheme: scheme) {
                        HStack(spacing: 6) {
                            Text(memoryText)
                                .font(.system(size: 12))
                                .foregroundColor(.textSecondary(for: scheme))
                            if case .ready = voices.hostState {
                                SettingsActionButton(icon: "eject", label: "Unload the model now", scheme: scheme) {
                                    voices.unloadModel()
                                }
                            }
                        }
                    }
                    RowDivider(scheme: scheme)
                    HStack {
                        Spacer()
                        Button("Reset \(model.name) to defaults") { settings.resetParameters(for: model) }
                            .controlSize(.small)
                            .disabled(settings.parameterValues(for: model).isEmpty)
                    }
                    .padding(.vertical, 10)
                    .padding(.horizontal, 16)
                }
                .padding(.horizontal, -16)
            } label: {
                Text("Advanced")
                    .font(.system(size: 13))
                    .foregroundColor(.textPrimary(for: scheme))
            }
            .padding(.vertical, 12)
            .padding(.horizontal, 16)
        }
    }

    private var memoryText: String {
        switch voices.hostState {
        case .unloaded: return "Not loaded · loads on the next read"
        case .loading: return "Loading…"
        case .ready(let repo): return "\(MLXSpeechModel.presets.first { $0.repo == repo }?.name ?? repo) loaded"
        case .failed(let message): return message
        }
    }

    private func unloadLabel(_ minutes: Int) -> String {
        minutes == 1 ? "1 minute idle" : "\(minutes) minutes idle"
    }
}

// MARK: - Parameter controls

/// Draws one `TTSParameter` from its kind. Values equal to the default are not
/// stored, so presets can improve their defaults later.
private struct ParameterControl: View {
    let parameter: TTSParameter
    let model: MLXSpeechModel
    @ObservedObject var settings: SettingsManager
    let scheme: ColorScheme

    private var stored: TTSValue? { settings.parameterValues(for: model)[parameter.id] }
    private var current: TTSValue? { model.value(parameter.id, in: settings.parameterValues(for: model)) }

    private func set(_ value: TTSValue?) {
        settings.updateParameter(parameter, to: value, for: model)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            switch parameter.kind {
            case .slider(let range, let step, let typical):
                SliderControl(label: parameter.label, value: current?.number, typical: typical,
                              range: range, step: step, isCustom: stored != nil, scheme: scheme,
                              onCommit: { set(.number($0)) }, onReset: { set(nil) })
            case .choice(let options):
                HStack {
                    Text(parameter.label)
                        .font(.system(size: 13))
                        .foregroundColor(.textPrimary(for: scheme))
                    Spacer()
                    Menu {
                        ForEach(options, id: \.self) { option in
                            Button(Self.display(option)) { set(.text(option)) }
                        }
                    } label: {
                        PickerLabel(text: Self.display(current?.text ?? ""), scheme: scheme, minWidth: 160)
                    }
                    .menuStyle(.borderlessButton)
                    .fixedSize()
                }
            case .text(let placeholder):
                TextParameter(label: parameter.label, value: current?.text ?? "", placeholder: placeholder,
                              isCustom: stored != nil, scheme: scheme,
                              onCommit: { text in
                                  let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                                  set(trimmed.isEmpty ? nil : .text(trimmed))
                              },
                              onReset: { set(nil) })
            case .toggle:
                Toggle(isOn: Binding(get: { current?.flag ?? false }, set: { set(.flag($0)) })) {
                    Text(parameter.label)
                        .font(.system(size: 13))
                        .foregroundColor(.textPrimary(for: scheme))
                }
                .toggleStyle(.checkbox)
            }
            if let caption = parameter.caption {
                Caption(text: caption, scheme: scheme)
            }
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 16)
    }

    /// "conversational_a" → "Conversational A", "Uncle_Fu" → "Uncle Fu".
    static func display(_ option: String) -> String {
        option.split(separator: "_").map { $0.prefix(1).uppercased() + $0.dropFirst() }.joined(separator: " ")
    }
}

private struct SliderControl: View {
    let label: String
    /// `nil` when the model's own default applies.
    let value: Double?
    let typical: Double
    let range: ClosedRange<Double>
    let step: Double
    let isCustom: Bool
    let scheme: ColorScheme
    let onCommit: (Double) -> Void
    let onReset: () -> Void
    @State private var draft = 0.0

    var body: some View {
        HStack(spacing: 10) {
            Text(label)
                .font(.system(size: 13))
                .foregroundColor(.textPrimary(for: scheme))
            Spacer()
            Slider(value: $draft, in: range, step: step,
                   onEditingChanged: { editing in if !editing { onCommit(draft) } })
                .frame(width: 150)
                .accessibilityLabel(label)
            Text(value == nil ? "Default" : String(format: "%.2f", draft))
                .font(.system(size: 12).monospacedDigit())
                .foregroundColor(.textSecondary(for: scheme))
                .frame(width: 48, alignment: .trailing)
            SettingsActionButton(icon: "arrow.uturn.backward", label: "Restore the default \(label.lowercased())", scheme: scheme, action: onReset)
                .opacity(isCustom ? 1 : 0)
                .disabled(!isCustom)
        }
        .onAppear { draft = value ?? typical }
        .onChange(of: value) { _, newValue in draft = newValue ?? typical }
    }
}

private struct TextParameter: View {
    let label: String
    let value: String
    let placeholder: String
    let isCustom: Bool
    let scheme: ColorScheme
    let onCommit: (String) -> Void
    let onReset: () -> Void
    @State private var draft = ""
    @FocusState private var isFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(label)
                    .font(.system(size: 13))
                    .foregroundColor(.textPrimary(for: scheme))
                Spacer()
                Button("Restore default", action: onReset)
                    .controlSize(.small)
                    .disabled(!isCustom)
            }
            TextField(placeholder, text: $draft, axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 12))
                .lineLimit(2...4)
                .focused($isFocused)
                .onSubmit { onCommit(draft) }
                .onChange(of: isFocused) { _, focused in if !focused { onCommit(draft) } }
                .accessibilityLabel(label)
        }
        .onAppear { draft = value }
        .onChange(of: value) { _, newValue in if !isFocused { draft = newValue } }
    }
}

struct Caption: View {
    let text: String
    let scheme: ColorScheme
    var isWarning = false

    var body: some View {
        Text(text)
            .font(.system(size: 11))
            .foregroundColor(isWarning ? Color(nsColor: .systemOrange) : .textTertiary(for: scheme))
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

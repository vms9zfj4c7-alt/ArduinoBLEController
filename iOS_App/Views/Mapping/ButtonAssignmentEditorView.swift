import SwiftUI

/// Éditeur détaillé pour configurer l'apparence, la broche et le comportement d'un bouton ou curseur.
struct ButtonAssignmentEditorView: View {
    let boardCapability: ArduinoBoardCapability
    let isConnected: Bool
    let onSave: (ButtonAssignment) -> Void
    let onTest: (ButtonAssignment, Bool) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var draft: ButtonAssignment

    private static let curatedSymbols: [String] = [
        "arrow.up", "arrow.down", "arrow.left", "arrow.right",
        "lightbulb.fill", "lightbulb.circle.fill", "flashlight.on.fill", "bolt.fill",
        "speaker.wave.3.fill", "rotate.right.fill", "hand.raised.fill", "speedometer",
        "slider.horizontal.3", "scope", "stop.circle.fill", "wave.3.right"
    ]
    private static let symbolGridColumns = Array(repeating: GridItem(.flexible()), count: 8)

    init(
        assignment: ButtonAssignment,
        boardCapability: ArduinoBoardCapability,
        isConnected: Bool,
        onSave: @escaping (ButtonAssignment) -> Void,
        onTest: @escaping (ButtonAssignment, Bool) -> Void
    ) {
        self.boardCapability = boardCapability
        self.isConnected = isConnected
        self.onSave = onSave
        self.onTest = onTest
        _draft = State(initialValue: assignment)
    }

    private var availableActionTypes: [ButtonActionType] {
        if draft.id.isSlider {
            return [.pinServo, .pinPWM]
        }
        return ButtonActionType.allCases
    }

    private var selectablePins: [ArduinoPinOption] {
        var pins: [ArduinoPinOption]
        if draft.actionType == .pinPWM && !boardCapability.pwmAvailablePins.isEmpty {
            pins = boardCapability.pwmAvailablePins
        } else {
            pins = boardCapability.availablePins
        }
        if !pins.contains(where: { $0.number == draft.primaryPin }) {
            pins.insert(
                ArduinoPinOption(number: draft.primaryPin, supportsPWM: false, isBuiltInLED: false),
                at: 0
            )
        }
        return pins
    }

    var body: some View {
        NavigationStack {
            Form {
                appearanceSection
                actionTypeSection
                actionDetailsSection

                if !draft.id.isSlider && draft.actionType != .emergencyStop {
                    behaviorSection
                }

                liveTestSection
            }
            .navigationTitle(draft.id.slotDisplayName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annuler") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Enregistrer") {
                        onSave(draft)
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
        }
    }

    // MARK: - Sections

    private var appearanceSection: some View {
        Section("Apparence sur la manette") {
            TextField("Nom affiché", text: $draft.label)

            Picker("Couleur", selection: $draft.colorToken) {
                ForEach(ControllerColorToken.allCases) { token in
                    HStack {
                        Circle()
                            .fill(token.color)
                            .frame(width: 14, height: 14)
                        Text(token.displayName)
                    }
                    .tag(token)
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Icône")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                LazyVGrid(columns: Self.symbolGridColumns, spacing: 10) {
                    ForEach(Self.curatedSymbols, id: \.self) { symbol in
                        let selected = (draft.symbolName == symbol)
                        Button {
                            draft.symbolName = symbol
                        } label: {
                            Image(systemName: symbol)
                                .font(.body)
                                .frame(width: 34, height: 34)
                                .foregroundStyle(selected ? .white : draft.colorToken.color)
                                .background(selected ? draft.colorToken.color : draft.colorToken.color.opacity(0.14))
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(.vertical, 4)
        }
    }

    private var actionTypeSection: some View {
        Section {
            Picker("Type d'action", selection: $draft.actionType) {
                ForEach(availableActionTypes) { type in
                    Text(type.displayName).tag(type)
                }
            }
            .onChange(of: draft.actionType) { newType in
                adjustDefaults(for: newType)
            }
        } header: {
            Text("Action Arduino (\(boardCapability.boardType.shortBadge))")
        }
    }

    @ViewBuilder
    private var actionDetailsSection: some View {
        switch draft.actionType {
        case .pinDigital:
            Section("Broche digitale") {
                pinPickerRow
                Toggle(
                    "État actif = HIGH (allumé)",
                    isOn: Binding(
                        get: { draft.activeValue > 0 },
                        set: { newValue in
                            draft.activeValue = newValue ? 1 : 0
                            draft.releaseValue = newValue ? 0 : 1
                        }
                    )
                )
            }

        case .pinPWM:
            Section("Sortie PWM (0 à 255)") {
                pinPickerRow
                if draft.id.isSlider {
                    Stepper("Minimum : \(draft.minSliderValue)", value: $draft.minSliderValue, in: 0...254)
                    Stepper("Maximum : \(draft.maxSliderValue)", value: $draft.maxSliderValue, in: (draft.minSliderValue + 1)...255)
                } else {
                    VStack(alignment: .leading) {
                        Text("Intensité active : \(draft.activeValue)")
                        Slider(
                            value: Binding(
                                get: { Double(draft.activeValue) },
                                set: { draft.activeValue = Int($0.rounded()) }
                            ),
                            in: 0...255,
                            step: 1
                        )
                    }
                    Stepper("Valeur au relâchement : \(draft.releaseValue)", value: $draft.releaseValue, in: 0...255, step: 5)
                }
            }

        case .pinServo:
            Section("Servomoteur (0° à 180°)") {
                pinPickerRow
                if draft.id.isSlider {
                    Stepper("Angle min : \(draft.minSliderValue)°", value: $draft.minSliderValue, in: 0...179, step: 5)
                    Stepper("Angle max : \(draft.maxSliderValue)°", value: $draft.maxSliderValue, in: (draft.minSliderValue + 1)...180, step: 5)
                } else {
                    VStack(alignment: .leading) {
                        Text("Angle actif : \(draft.activeValue)°")
                        Slider(
                            value: Binding(
                                get: { Double(draft.activeValue) },
                                set: { draft.activeValue = Int($0.rounded()) }
                            ),
                            in: 0...180,
                            step: 1
                        )
                    }
                    Stepper("Angle au relâchement : \(draft.releaseValue)°", value: $draft.releaseValue, in: 0...180, step: 5)
                }
            }

        case .multiPin:
            Section {
                if draft.extraPinTargets.isEmpty {
                    Text("Aucune broche ajoutée.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach($draft.extraPinTargets) { $target in
                        MultiPinTargetRow(target: $target, boardCapability: boardCapability)
                    }
                    .onDelete { offsets in
                        draft.extraPinTargets.remove(atOffsets: offsets)
                    }
                }

                Button {
                    let defaultPin = boardCapability.availablePins.first?.number ?? draft.primaryPin
                    draft.extraPinTargets.append(
                        PinTarget(pin: defaultPin, signalKind: .digital, activeValue: 1, releaseValue: 0)
                    )
                } label: {
                    Label("Ajouter une broche", systemImage: "plus.circle.fill")
                }
            } header: {
                Text("Broches pilotées simultanément")
            } footer: {
                Text("Idéal pour piloter un pont en H (ex: moteur gauche + droit) depuis une seule touche directionnelle.")
            }

        case .customCommand:
            Section {
                TextField("Commande à l'appui (ex: FWD)", text: $draft.pressCommand)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .font(.system(.body, design: .monospaced))

                TextField("Commande au relâchement (optionnel)", text: $draft.releaseCommand)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .font(.system(.body, design: .monospaced))
            } header: {
                Text("Commandes texte personnalisées")
            } footer: {
                Text("Un retour à la ligne (\\n) est ajouté automatiquement lors de l'envoi BLE.")
            }

        case .emergencyStop:
            Section("Arrêt d'urgence") {
                Text("Envoie la commande universelle X afin de couper immédiatement toutes les sorties actives de l'Arduino.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var pinPickerRow: some View {
        Picker("Broche Arduino", selection: $draft.primaryPin) {
            ForEach(selectablePins) { option in
                Text(option.displayLabel).tag(option.number)
            }
        }
    }

    private var behaviorSection: some View {
        Section {
            Picker("Mode d'appui", selection: $draft.behavior) {
                ForEach(ButtonBehavior.allCases) { mode in
                    Text(mode.displayName).tag(mode)
                }
            }
        } header: {
            Text("Comportement du bouton")
        }
    }

    private var liveTestSection: some View {
        Section("Test en direct") {
            HStack(spacing: 12) {
                Button {
                    onTest(draft, true)
                } label: {
                    Label("Tester Actif", systemImage: "play.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(!isConnected)

                if draft.behavior == .momentary || draft.actionType == .pinDigital || draft.actionType == .multiPin {
                    Button {
                        onTest(draft, false)
                    } label: {
                        Label("Tester Repos", systemImage: "stop.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .disabled(!isConnected)
                }
            }
            if !isConnected {
                Text("Connectez un Arduino pour tester la broche en direct.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func adjustDefaults(for newType: ButtonActionType) {
        switch newType {
        case .pinDigital:
            draft.activeValue = 1
            draft.releaseValue = 0
        case .pinPWM:
            if let firstPWM = boardCapability.pwmAvailablePins.first?.number,
               !boardCapability.pwmPins.contains(draft.primaryPin) {
                draft.primaryPin = firstPWM
            }
            draft.minSliderValue = 0
            draft.maxSliderValue = 255
            draft.activeValue = 200
            draft.releaseValue = 0
        case .pinServo:
            draft.minSliderValue = 0
            draft.maxSliderValue = 180
            draft.activeValue = 90
            draft.releaseValue = 90
        case .multiPin:
            if draft.extraPinTargets.isEmpty {
                let pin = boardCapability.availablePins.first?.number ?? draft.primaryPin
                draft.extraPinTargets = [PinTarget(pin: pin, signalKind: .digital, activeValue: 1, releaseValue: 0)]
            }
        case .customCommand, .emergencyStop:
            break
        }
    }
}

private struct MultiPinTargetRow: View {
    @Binding var target: PinTarget
    let boardCapability: ArduinoBoardCapability

    private var pinOptions: [ArduinoPinOption] {
        var pins = boardCapability.availablePins
        if !pins.contains(where: { $0.number == target.pin }) {
            pins.insert(ArduinoPinOption(number: target.pin, supportsPWM: false, isBuiltInLED: false), at: 0)
        }
        return pins
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Picker("Broche", selection: $target.pin) {
                    ForEach(pinOptions) { opt in
                        Text(opt.shortLabel).tag(opt.number)
                    }
                }
                .labelsHidden()
                .frame(maxWidth: 110, alignment: .leading)

                Spacer()

                Picker("Signal", selection: $target.signalKind) {
                    ForEach(PinSignalKind.allCases) { kind in
                        Text(kind.displayName).tag(kind)
                    }
                }
                .labelsHidden()
            }

            if target.signalKind == .digital {
                HStack {
                    Toggle(
                        "Actif = HIGH",
                        isOn: Binding(
                            get: { target.activeValue > 0 },
                            set: { target.activeValue = $0 ? 1 : 0 }
                        )
                    )
                    .font(.caption)

                    Toggle(
                        "Repos = HIGH",
                        isOn: Binding(
                            get: { target.releaseValue > 0 },
                            set: { target.releaseValue = $0 ? 1 : 0 }
                        )
                    )
                    .font(.caption)
                }
            } else {
                let maxBound = (target.signalKind == .pwm) ? 255 : 180
                HStack {
                    Stepper("Actif: \(target.activeValue)", value: $target.activeValue, in: 0...maxBound, step: 5)
                        .font(.caption)
                    Stepper("Repos: \(target.releaseValue)", value: $target.releaseValue, in: 0...maxBound, step: 5)
                        .font(.caption)
                }
            }
        }
        .padding(.vertical, 4)
    }
}

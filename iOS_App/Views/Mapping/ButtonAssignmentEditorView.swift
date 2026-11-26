import SwiftUI

/// Éditeur simplifié en quelques appuis pour personnaliser un bouton ou curseur.
struct ButtonAssignmentEditorView: View {
    let boardCapability: ArduinoBoardCapability
    let isConnected: Bool
    let onSave: (ButtonAssignment) -> Void
    let onTest: (ButtonAssignment, Bool) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var draft: ButtonAssignment
    @State private var previewPressed = false
    @State private var showAdvancedOptions: Bool

    private enum SimpleRole: String, CaseIterable, Identifiable {
        case toggleSwitch
        case momentaryPress
        case pwmLevel
        case servoAngle

        var id: String { rawValue }

        var title: String {
            switch self {
            case .toggleSwitch: return "Interrupteur"
            case .momentaryPress: return "Poussoir"
            case .pwmLevel: return "Variateur"
            case .servoAngle: return "Servo"
            }
        }

        var subtitle: String {
            switch self {
            case .toggleSwitch: return "ON / OFF au clic"
            case .momentaryPress: return "Actif tant qu'on appuie"
            case .pwmLevel: return "Puissance 0 à 255"
            case .servoAngle: return "Angle 0° à 180°"
            }
        }
    }

    private static let roleColumns = [
        GridItem(.flexible(), spacing: 8),
        GridItem(.flexible(), spacing: 8)
    ]

    private static let pinGridColumns = Array(repeating: GridItem(.flexible(), spacing: 8), count: 4)

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
        let isAdvancedType = (assignment.actionType == .multiPin
            || assignment.actionType == .customCommand
            || assignment.actionType == .emergencyStop)
        _showAdvancedOptions = State(initialValue: isAdvancedType)
    }

    private var activeSimpleRole: SimpleRole? {
        switch draft.actionType {
        case .pinDigital:
            return (draft.behavior == .toggle) ? .toggleSwitch : .momentaryPress
        case .pinPWM:
            return .pwmLevel
        case .pinServo:
            return .servoAngle
        case .multiPin, .customCommand, .emergencyStop:
            return nil
        }
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
                livePreviewSection
                appearanceSection
                simpleRoleSection

                if isPinBasedAction {
                    pinAndValueSection
                } else {
                    specialActionDetailsSection
                }

                if !draft.id.isSlider {
                    advancedOptionsSection
                }

                liveTestSection
            }
            .scrollDismissesKeyboard(.interactively)
            .animation(AppleMotion.fluidSpring, value: draft.actionType)
            .animation(AppleMotion.fluidSpring, value: draft.behavior)
            .animation(AppleMotion.fluidSpring, value: showAdvancedOptions)
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
                        AppHaptics.success()
                        onSave(draft)
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
        }
    }

    private var isPinBasedAction: Bool {
        draft.actionType == .pinDigital || draft.actionType == .pinPWM || draft.actionType == .pinServo
    }

    // MARK: - Sections

    private var livePreviewSection: some View {
        let color = draft.colorToken.color
        let rawLabel = draft.label.trimmingCharacters(in: .whitespacesAndNewlines)
        let title = rawLabel.isEmpty ? draft.id.shortCode : rawLabel

        return Section {
            HStack(spacing: 14) {
                Button {
                    AppHaptics.light()
                    withAnimation(AppleMotion.pressSpring) {
                        previewPressed = true
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) {
                        withAnimation(AppleMotion.fluidSpring) {
                            previewPressed = false
                        }
                    }
                } label: {
                    let shape = RoundedRectangle(cornerRadius: 16, style: .continuous)
                    VStack(spacing: 2) {
                        Text(draft.id.shortCode)
                            .font(.system(size: 16, weight: .black, design: .rounded))
                        Text(title)
                            .font(.system(size: 10, weight: .semibold))
                            .multilineTextAlignment(.center)
                            .lineLimit(2)
                            .minimumScaleFactor(0.68)
                    }
                    .foregroundStyle(previewPressed ? .white : color)
                    .padding(.horizontal, 5)
                    .frame(width: 68, height: 68, alignment: .center)
                    .background(
                        HardwareKeycapBackground(
                            shape: shape,
                            color: color,
                            highlighted: previewPressed
                        )
                    )
                    .scaleEffect(previewPressed ? 0.91 : 1.0)
                }
                .buttonStyle(.borderless)

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text(draft.id.shortCode)
                            .font(.caption2.weight(.bold))
                            .padding(.horizontal, 7)
                            .padding(.vertical, 2)
                            .background(color.opacity(0.16))
                            .foregroundStyle(color)
                            .clipShape(Capsule())
                        Text(draft.id.ps4Hint)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }

                    Text(draft.summaryDescription)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.primary)

                    Text("Touchez l'aperçu pour simuler l'appui")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }

                Spacer(minLength: 0)
            }
            .padding(.vertical, 4)
            .animation(AppleMotion.fluidSpring, value: draft.colorToken)
            .animation(AppleMotion.fluidSpring, value: draft.label)
        } header: {
            Text("Aperçu")
        }
    }

    private var appearanceSection: some View {
        Section("Nom et couleur") {
            TextField("Nom affiché", text: $draft.label)

            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("Couleur")
                        .font(.subheadline)
                    Spacer()
                    Text(draft.colorToken.displayName)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                }

                HStack(spacing: 0) {
                    ForEach(ControllerColorToken.allCases) { token in
                        let isSelected = (draft.colorToken == token)
                        Button {
                            AppHaptics.selection()
                            withAnimation(AppleMotion.pressSpring) {
                                draft.colorToken = token
                            }
                        } label: {
                            ZStack {
                                Circle()
                                    .fill(token.color)
                                    .frame(width: 24, height: 24)
                                if isSelected {
                                    Circle()
                                        .strokeBorder(Color.primary, lineWidth: 2.2)
                                        .frame(width: 30, height: 30)
                                }
                            }
                            .frame(maxWidth: .infinity, minHeight: 32)
                        }
                        .buttonStyle(.borderless)
                        .accessibilityLabel(token.displayName)
                    }
                }
            }
            .padding(.vertical, 4)
        }
    }

    private var simpleRoleSection: some View {
        Section("Que doit faire ce contrôle ?") {
            if draft.id.isSlider {
                Picker("Type de curseur", selection: $draft.actionType) {
                    Text("Servomoteur (0–180°)").tag(ButtonActionType.pinServo)
                    Text("Variateur PWM (0–255)").tag(ButtonActionType.pinPWM)
                }
                .pickerStyle(.segmented)
                .onChange(of: draft.actionType) { newType in
                    AppHaptics.selection()
                    withAnimation(AppleMotion.fluidSpring) {
                        adjustDefaults(for: newType)
                    }
                }
            } else {
                LazyVGrid(columns: Self.roleColumns, spacing: 8) {
                    ForEach(SimpleRole.allCases) { role in
                        let selected = (activeSimpleRole == role)
                        let shape = RoundedRectangle(cornerRadius: 12, style: .continuous)
                        Button {
                            AppHaptics.selection()
                            withAnimation(AppleMotion.fluidSpring) {
                                applySimpleRole(role)
                            }
                        } label: {
                            VStack(spacing: 2) {
                                Text(role.title)
                                    .font(.caption.weight(.bold))
                                    .multilineTextAlignment(.center)
                                Text(role.subtitle)
                                    .font(.system(size: 10, weight: .medium))
                                    .multilineTextAlignment(.center)
                                    .opacity(selected ? 0.88 : 0.72)
                            }
                            .foregroundStyle(selected ? .white : .primary)
                            .frame(maxWidth: .infinity, minHeight: 46)
                            .padding(.horizontal, 6)
                            .background(
                                shape.fill(selected ? draft.colorToken.color : Color(.tertiarySystemFill))
                            )
                        }
                        .buttonStyle(.borderless)
                    }
                }
                .padding(.vertical, 4)
            }
        }
    }

    private var pinAndValueSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 10) {
                Text("Choisir la broche Arduino (\(boardCapability.boardType.shortBadge))")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)

                LazyVGrid(columns: Self.pinGridColumns, spacing: 8) {
                    ForEach(selectablePins) { option in
                        let isSelected = (draft.primaryPin == option.number)
                        let shape = RoundedRectangle(cornerRadius: 10, style: .continuous)
                        Button {
                            AppHaptics.selection()
                            withAnimation(AppleMotion.pressSpring) {
                                draft.primaryPin = option.number
                            }
                        } label: {
                            VStack(spacing: 1) {
                                Text("Pin \(option.number)")
                                    .font(.caption.weight(.bold))
                                if option.isBuiltInLED {
                                    Text("LED")
                                        .font(.system(size: 8, weight: .bold))
                                        .opacity(0.8)
                                } else if option.supportsPWM {
                                    Text("PWM")
                                        .font(.system(size: 8, weight: .medium))
                                        .opacity(0.72)
                                }
                            }
                            .foregroundStyle(isSelected ? .white : .primary)
                            .frame(maxWidth: .infinity, minHeight: 38)
                            .background(
                                shape.fill(isSelected ? draft.colorToken.color : Color(.tertiarySystemFill))
                            )
                        }
                        .buttonStyle(.borderless)
                    }
                }
            }
            .padding(.vertical, 4)

            if draft.actionType == .pinDigital {
                Toggle(
                    "Allumer à l'activation (HIGH)",
                    isOn: Binding(
                        get: { draft.activeValue > 0 },
                        set: { newValue in
                            AppHaptics.light()
                            draft.activeValue = newValue ? 1 : 0
                            draft.releaseValue = newValue ? 0 : 1
                        }
                    )
                )
            } else if draft.actionType == .pinPWM {
                if draft.id.isSlider {
                    Stepper("Minimum : \(draft.minSliderValue)", value: $draft.minSliderValue, in: 0...254)
                    Stepper("Maximum : \(draft.maxSliderValue)", value: $draft.maxSliderValue, in: (draft.minSliderValue + 1)...255)
                } else {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Intensité active : \(draft.activeValue)")
                            .font(.subheadline.weight(.medium))
                            .contentTransition(.numericText())
                        Slider(
                            value: Binding(
                                get: { Double(draft.activeValue) },
                                set: { draft.activeValue = Int($0.rounded()) }
                            ),
                            in: 0...255,
                            step: 1
                        )
                        .tint(draft.colorToken.color)
                    }
                }
            } else if draft.actionType == .pinServo {
                if draft.id.isSlider {
                    Stepper("Angle min : \(draft.minSliderValue)°", value: $draft.minSliderValue, in: 0...179, step: 5)
                    Stepper("Angle max : \(draft.maxSliderValue)°", value: $draft.maxSliderValue, in: (draft.minSliderValue + 1)...180, step: 5)
                } else {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Angle cible : \(draft.activeValue)°")
                            .font(.subheadline.weight(.medium))
                            .contentTransition(.numericText())
                        Slider(
                            value: Binding(
                                get: { Double(draft.activeValue) },
                                set: { draft.activeValue = Int($0.rounded()) }
                            ),
                            in: 0...180,
                            step: 1
                        )
                        .tint(draft.colorToken.color)
                    }
                }
            }
        } header: {
            Text("Broche et réglage")
        }
    }

    @ViewBuilder
    private var specialActionDetailsSection: some View {
        switch draft.actionType {
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
                        AppHaptics.soft()
                        withAnimation(AppleMotion.fluidSpring) {
                            draft.extraPinTargets.remove(atOffsets: offsets)
                        }
                    }
                }

                Button("Ajouter une broche") {
                    AppHaptics.light()
                    let defaultPin = boardCapability.availablePins.first?.number ?? draft.primaryPin
                    withAnimation(AppleMotion.fluidSpring) {
                        draft.extraPinTargets.append(
                            PinTarget(pin: defaultPin, signalKind: .digital, activeValue: 1, releaseValue: 0)
                        )
                    }
                }
            } header: {
                Text("Broches pilotées simultanément")
            }

        case .customCommand:
            Section("Commandes texte libres") {
                TextField("Commande à l'appui (ex: FWD)", text: $draft.pressCommand)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .font(.system(.body, design: .monospaced))

                TextField("Commande au relâchement (optionnel)", text: $draft.releaseCommand)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .font(.system(.body, design: .monospaced))
            }

        case .emergencyStop:
            Section("Arrêt d'urgence") {
                Text("Envoie la commande universelle X afin de couper immédiatement toutes les sorties actives de l'Arduino.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

        case .pinDigital, .pinPWM, .pinServo:
            EmptyView()
        }
    }

    private var advancedOptionsSection: some View {
        Section {
            DisclosureGroup("Options avancées", isExpanded: $showAdvancedOptions) {
                Picker("Type exact", selection: $draft.actionType) {
                    ForEach(availableActionTypes) { type in
                        Text(type.displayName).tag(type)
                    }
                }
                .onChange(of: draft.actionType) { newType in
                    AppHaptics.selection()
                    withAnimation(AppleMotion.fluidSpring) {
                        adjustDefaults(for: newType)
                    }
                }

                if draft.actionType != .emergencyStop {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Comportement d'appui")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)

                        Picker("Mode d'appui", selection: $draft.behavior) {
                            Text("Maintenu").tag(ButtonBehavior.momentary)
                            Text("ON / OFF").tag(ButtonBehavior.toggle)
                            Text("Impulsion").tag(ButtonBehavior.push)
                        }
                        .pickerStyle(.segmented)
                        .onChange(of: draft.behavior) { _ in
                            AppHaptics.selection()
                        }
                    }
                    .padding(.vertical, 4)
                }

                if draft.actionType == .pinPWM {
                    Stepper("Valeur au relâchement : \(draft.releaseValue)", value: $draft.releaseValue, in: 0...255, step: 5)
                } else if draft.actionType == .pinServo {
                    Stepper("Angle au relâchement : \(draft.releaseValue)°", value: $draft.releaseValue, in: 0...180, step: 5)
                }
            }
        }
    }

    private var liveTestSection: some View {
        Section("Test sur l'Arduino") {
            HStack(spacing: 12) {
                Button {
                    AppHaptics.medium()
                    onTest(draft, true)
                } label: {
                    Text("Tester Actif")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(!isConnected)

                if draft.behavior == .momentary || draft.actionType == .pinDigital || draft.actionType == .multiPin {
                    Button {
                        AppHaptics.light()
                        onTest(draft, false)
                    } label: {
                        Text("Mettre au repos")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .disabled(!isConnected)
                }
            }
            if !isConnected {
                Text("Connectez d'abord un Arduino depuis le Radar BLE pour tester en direct.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func applySimpleRole(_ role: SimpleRole) {
        switch role {
        case .toggleSwitch:
            draft.actionType = .pinDigital
            draft.behavior = .toggle
            draft.activeValue = 1
            draft.releaseValue = 0
        case .momentaryPress:
            draft.actionType = .pinDigital
            draft.behavior = .momentary
            draft.activeValue = 1
            draft.releaseValue = 0
        case .pwmLevel:
            draft.actionType = .pinPWM
            draft.behavior = .momentary
            adjustDefaults(for: .pinPWM)
        case .servoAngle:
            draft.actionType = .pinServo
            draft.behavior = .push
            adjustDefaults(for: .pinServo)
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

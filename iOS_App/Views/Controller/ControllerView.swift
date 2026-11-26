import SwiftUI
import Combine

/// Écran principal de contrôle de l'Arduino façon manette de jeu, adaptatif portrait / paysage.
struct ControllerView: View {
    @ObservedObject var viewModel: ControllerViewModel
    let telemetryStore: BLETelemetryStore
    let onOpenScan: () -> Void
    let onOpenMapping: () -> Void

    @Environment(\.verticalSizeClass) private var verticalSizeClass
    @State private var showPS4GuideSheet = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    statusHeaderCard

                    if verticalSizeClass == .compact {
                        landscapeGamepadLayout
                    } else {
                        portraitGamepadLayout
                    }

                    LogConsoleView(
                        logStore: viewModel.logStore,
                        isConnected: viewModel.connectionState.isConnected,
                        onSendRawCommand: { viewModel.sendRawCommand($0) },
                        onClearLogs: { viewModel.clearLogs() }
                    )
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
            }
            .background(Color(.systemGroupedBackground).ignoresSafeArea())
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle("Manette")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        AppHaptics.selection()
                        onOpenMapping()
                    } label: {
                        Label("Assigner", systemImage: "slider.horizontal.3")
                            .font(.subheadline.weight(.medium))
                    }
                }

                ToolbarItem(placement: .topBarTrailing) {
                    if viewModel.connectionState.isConnected {
                        Button("Déconnecter", role: .destructive) {
                            AppHaptics.soft()
                            viewModel.disconnect()
                        }
                        .font(.subheadline)
                    } else {
                        Button("Connecter") {
                            AppHaptics.selection()
                            onOpenScan()
                        }
                        .font(.subheadline.weight(.semibold))
                    }
                }
            }
            .sheet(isPresented: $showPS4GuideSheet) {
                PS4ConnectionGuideSheet(
                    viewModel: viewModel,
                    onOpenMapping: {
                        showPS4GuideSheet = false
                        onOpenMapping()
                    }
                )
            }
        }
    }

    // MARK: - En-tête État & Télémétrie

    private var statusHeaderCard: some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                LivePulseBeacon(
                    color: statusColor,
                    isPulsing: viewModel.connectionState.isBusy,
                    dotSize: 10
                )

                VStack(alignment: .leading, spacing: 2) {
                    Text(viewModel.connectionState.statusText)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)

                    HStack(spacing: 6) {
                        Text(viewModel.boardCapability.boardType.displayName)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        if viewModel.boardCapability.isAutoDetected {
                            Text("Auto")
                                .font(.caption2.weight(.bold))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 1)
                                .background(Color.blue.opacity(0.14))
                                .foregroundStyle(.blue)
                                .clipShape(Capsule())
                        }
                    }
                }

                Spacer()

                TelemetryBadgesView(
                    telemetryStore: telemetryStore,
                    onRequestTelemetry: {
                        AppHaptics.light()
                        viewModel.requestTelemetry()
                    }
                )
            }

            Divider()
                .opacity(0.45)

            // Ligne d'état manette PS4 / DualShock 4 Bluetooth
            HStack(spacing: 8) {
                Button {
                    AppHaptics.selection()
                    showPS4GuideSheet = true
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: viewModel.isPS4Connected ? "gamecontroller.fill" : "gamecontroller")
                            .foregroundStyle(viewModel.isPS4Connected ? Color.green : Color.secondary)
                        Text(viewModel.isPS4Connected ? "Manette : \(viewModel.ps4ControllerName)" : "Manette PS4 / Bluetooth")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(viewModel.isPS4Connected ? .primary : .secondary)
                            .lineLimit(1)
                        if let battery = viewModel.ps4BatteryPercentage {
                            Text("\(battery)%")
                                .font(.caption2.monospacedDigit().weight(.bold))
                                .contentTransition(.numericText())
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.green.opacity(0.15))
                                .foregroundStyle(.green)
                                .clipShape(Capsule())
                        }
                    }
                }
                .buttonStyle(.plain)

                Spacer()

                Button(viewModel.isPS4Connected ? "Détails" : "Connecter PS4") {
                    AppHaptics.selection()
                    showPS4GuideSheet = true
                }
                .font(.caption2.weight(.semibold))
                .foregroundStyle(Color.accentColor)
                .buttonStyle(.borderless)
            }
            .animation(AppleMotion.fluidSpring, value: viewModel.isPS4Connected)

            if !viewModel.connectionState.isConnected {
                HStack(spacing: 8) {
                    Text("Connectez un Arduino pour piloter les broches.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    if case .disconnected = viewModel.connectionState,
                       viewModel.lastConnectedDeviceName != nil {
                        Button("Reconnecter") {
                            AppHaptics.medium()
                            viewModel.reconnectLastDevice()
                        }
                        .font(.caption.weight(.semibold))
                        .buttonStyle(.bordered)
                        .controlSize(.mini)
                    }
                    Button("Scanner") {
                        AppHaptics.selection()
                        onOpenScan()
                    }
                    .font(.caption.weight(.semibold))
                    .buttonStyle(.borderedProminent)
                    .controlSize(.mini)
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(12)
        .appleGroupedCard(cornerRadius: 18)
        .clipped()
        .animation(AppleMotion.fluidSpring, value: viewModel.connectionState)
    }

    // MARK: - Disposition Portrait

    private var portraitGamepadLayout: some View {
        VStack(spacing: 14) {
            // Gâchettes L1 / R1 + Select / STOP / Start
            HStack(spacing: 8) {
                ShoulderPillButton(
                    slotCode: "L1",
                    assignment: viewModel.assignment(for: .shoulderL1),
                    isActive: viewModel.isSlotActive(.shoulderL1),
                    onDown: { viewModel.handleButtonDown(slot: .shoulderL1) },
                    onUp: { viewModel.handleButtonUp(slot: .shoulderL1) }
                )
                .equatable()

                ShoulderPillButton(
                    slotCode: "SEL",
                    assignment: viewModel.assignment(for: .select),
                    isActive: viewModel.isSlotActive(.select),
                    onDown: { viewModel.handleButtonDown(slot: .select) },
                    onUp: { viewModel.handleButtonUp(slot: .select) }
                )
                .equatable()

                ShoulderPillButton(
                    slotCode: "STA",
                    assignment: viewModel.assignment(for: .start),
                    isActive: viewModel.isSlotActive(.start),
                    onDown: { viewModel.handleButtonDown(slot: .start) },
                    onUp: { viewModel.handleButtonUp(slot: .start) }
                )
                .equatable()

                ShoulderPillButton(
                    slotCode: "R1",
                    assignment: viewModel.assignment(for: .shoulderR1),
                    isActive: viewModel.isSlotActive(.shoulderR1),
                    onDown: { viewModel.handleButtonDown(slot: .shoulderR1) },
                    onUp: { viewModel.handleButtonUp(slot: .shoulderR1) }
                )
                .equatable()
            }

            // Curseurs analogiques L2 & R2
            VStack(spacing: 10) {
                sliderCard(for: .sliderLeft)
                sliderCard(for: .sliderRight)
            }

            // Croix directionnelle + Boutons A/B/X/Y
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .center, spacing: 14) {
                    dpadCluster
                    Spacer(minLength: 4)
                    actionButtonsCluster
                }

                VStack(spacing: 14) {
                    dpadCluster
                    actionButtonsCluster
                }
            }
        }
    }

    // MARK: - Disposition Paysage (Manette Console)

    private var landscapeGamepadLayout: some View {
        HStack(alignment: .top, spacing: 14) {
            VStack(spacing: 10) {
                HStack(spacing: 8) {
                    ShoulderPillButton(
                        slotCode: "L1",
                        assignment: viewModel.assignment(for: .shoulderL1),
                        isActive: viewModel.isSlotActive(.shoulderL1),
                        onDown: { viewModel.handleButtonDown(slot: .shoulderL1) },
                        onUp: { viewModel.handleButtonUp(slot: .shoulderL1) }
                    )
                    .equatable()
                }
                sliderCard(for: .sliderLeft)
                dpadCluster
            }

            VStack(spacing: 10) {
                ShoulderPillButton(
                    slotCode: "SEL",
                    assignment: viewModel.assignment(for: .select),
                    isActive: viewModel.isSlotActive(.select),
                    onDown: { viewModel.handleButtonDown(slot: .select) },
                    onUp: { viewModel.handleButtonUp(slot: .select) }
                )
                .equatable()

                ShoulderPillButton(
                    slotCode: "STA",
                    assignment: viewModel.assignment(for: .start),
                    isActive: viewModel.isSlotActive(.start),
                    onDown: { viewModel.handleButtonDown(slot: .start) },
                    onUp: { viewModel.handleButtonUp(slot: .start) }
                )
                .equatable()

                Button {
                    viewModel.triggerEmergencyStop()
                } label: {
                    Label("STOP", systemImage: "exclamationmark.octagon.fill")
                        .font(.caption.weight(.bold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
            }
            .frame(maxWidth: 120)

            VStack(spacing: 10) {
                ShoulderPillButton(
                    slotCode: "R1",
                    assignment: viewModel.assignment(for: .shoulderR1),
                    isActive: viewModel.isSlotActive(.shoulderR1),
                    onDown: { viewModel.handleButtonDown(slot: .shoulderR1) },
                    onUp: { viewModel.handleButtonUp(slot: .shoulderR1) }
                )
                .equatable()
                sliderCard(for: .sliderRight)
                actionButtonsCluster
            }
        }
    }

    private func sliderCard(for slot: GamepadSlot) -> some View {
        AnalogSliderCard(
            slot: slot,
            config: viewModel.assignment(for: slot),
            initialValue: viewModel.initialSliderValue(for: slot),
            externalUpdates: viewModel.externalSliderUpdates,
            onChanged: { value, isFinal in
                viewModel.handleSliderChanged(slot: slot, value: value, isFinal: isFinal)
            }
        )
    }

    private var dpadCluster: some View {
        DPadClusterView(
            upAssignment: viewModel.assignment(for: .dpadUp),
            downAssignment: viewModel.assignment(for: .dpadDown),
            leftAssignment: viewModel.assignment(for: .dpadLeft),
            rightAssignment: viewModel.assignment(for: .dpadRight),
            isUpActive: viewModel.isSlotActive(.dpadUp),
            isDownActive: viewModel.isSlotActive(.dpadDown),
            isLeftActive: viewModel.isSlotActive(.dpadLeft),
            isRightActive: viewModel.isSlotActive(.dpadRight),
            onDown: { viewModel.handleButtonDown(slot: $0) },
            onUp: { viewModel.handleButtonUp(slot: $0) }
        )
        .equatable()
    }

    private var actionButtonsCluster: some View {
        ActionButtonsClusterView(
            buttonY: viewModel.assignment(for: .buttonY),
            buttonX: viewModel.assignment(for: .buttonX),
            buttonB: viewModel.assignment(for: .buttonB),
            buttonA: viewModel.assignment(for: .buttonA),
            isYActive: viewModel.isSlotActive(.buttonY),
            isXActive: viewModel.isSlotActive(.buttonX),
            isBActive: viewModel.isSlotActive(.buttonB),
            isAActive: viewModel.isSlotActive(.buttonA),
            onDown: { viewModel.handleButtonDown(slot: $0) },
            onUp: { viewModel.handleButtonUp(slot: $0) }
        )
        .equatable()
    }

    private var statusColor: Color {
        switch viewModel.connectionState {
        case .connected: return .green
        case .scanning, .connecting, .discoveringServices: return .orange
        case .disconnected: return .red
        }
    }
}

/// Badges isolés : seuls ces deux éléments se redessinent lors des paquets RSSI et température.
private struct TelemetryBadgesView: View {
    @ObservedObject var telemetryStore: BLETelemetryStore
    let onRequestTelemetry: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            if let temp = telemetryStore.latestTemperature {
                Button(action: onRequestTelemetry) {
                    HStack(spacing: 4) {
                        Image(systemName: "thermometer")
                        Text(String(format: "%.1f °C", temp))
                            .monospacedDigit()
                            .contentTransition(.numericText())
                        if telemetryStore.isTemperatureSimulated {
                            Text("(démo)")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 9)
                    .padding(.vertical, 5)
                    .background(Color.orange.opacity(0.14))
                    .foregroundStyle(.orange)
                    .clipShape(Capsule())
                }
                .buttonStyle(TactileScaleButtonStyle(pressedScale: 0.92))
                .transition(.scale(scale: 0.85).combined(with: .opacity))
            }

            if let rssi = telemetryStore.connectedRSSI {
                HStack(spacing: 4) {
                    Circle()
                        .fill(rssiColor(rssi))
                        .frame(width: 6, height: 6)
                    Text("\(rssi) dBm")
                        .font(.caption2.monospacedDigit().weight(.medium))
                        .contentTransition(.numericText())
                }
                .foregroundStyle(.secondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(Color(.tertiarySystemFill))
                .clipShape(Capsule())
                .transition(.scale(scale: 0.85).combined(with: .opacity))
            }
        }
        .animation(AppleMotion.fluidSpring, value: telemetryStore.latestTemperature)
        .animation(AppleMotion.fluidSpring, value: telemetryStore.connectedRSSI)
    }

    private func rssiColor(_ rssi: Int) -> Color {
        if rssi >= -62 { return .green }
        if rssi >= -78 { return .orange }
        return .red
    }
}

private struct ShoulderPillButton: View, Equatable {
    let slotCode: String
    let assignment: ButtonAssignment
    let isActive: Bool
    let onDown: () -> Void
    let onUp: () -> Void

    static func == (lhs: ShoulderPillButton, rhs: ShoulderPillButton) -> Bool {
        lhs.slotCode == rhs.slotCode
            && lhs.assignment == rhs.assignment
            && lhs.isActive == rhs.isActive
    }

    var body: some View {
        let color = assignment.colorToken.color
        let capsule = Capsule()

        TactileHoldControl(
            hitShape: capsule,
            isActive: isActive,
            pressedScale: 0.94,
            onDown: onDown,
            onUp: onUp
        ) { highlighted, _ in
            HStack(spacing: 4) {
                Image(systemName: assignment.symbolName)
                    .font(.caption.weight(.bold))
                Text(assignment.label)
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .foregroundStyle(highlighted ? .white : color)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .padding(.horizontal, 6)
            .background(
                HardwareKeycapBackground(
                    shape: capsule,
                    color: color,
                    highlighted: highlighted
                )
            )
        }
        .accessibilityLabel("\(slotCode) \(assignment.label)")
    }
}

private struct AnalogSliderCard: View {
    let slot: GamepadSlot
    let config: ButtonAssignment
    let externalUpdates: PassthroughSubject<(slot: GamepadSlot, value: Double), Never>
    let onChanged: (Double, Bool) -> Void

    @State private var localValue: Double
    @State private var isDragging: Bool = false

    init(
        slot: GamepadSlot,
        config: ButtonAssignment,
        initialValue: Double,
        externalUpdates: PassthroughSubject<(slot: GamepadSlot, value: Double), Never>,
        onChanged: @escaping (Double, Bool) -> Void
    ) {
        self.slot = slot
        self.config = config
        self.externalUpdates = externalUpdates
        self.onChanged = onChanged
        _localValue = State(initialValue: initialValue)
    }

    var body: some View {
        let minVal = Double(min(config.minSliderValue, config.maxSliderValue))
        let maxVal = Double(max(config.minSliderValue + 1, config.maxSliderValue))
        let clamped = min(max(localValue, minVal), maxVal)
        let roundedInt = Int(clamped.rounded())
        let restInt = min(max(config.releaseValue, Int(minVal)), Int(maxVal))
        let unitSuffix = (config.actionType == .pinServo) ? "°" : ""
        let accent = config.colorToken.color

        VStack(spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: config.symbolName)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(accent)
                    .frame(width: 22, height: 22)
                    .background(accent.opacity(0.14))
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))

                Text(config.label)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.primary)

                Text("\(slot.shortCode) • P\(config.primaryPin)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)

                Spacer()

                HStack(spacing: 6) {
                    if roundedInt != restInt {
                        Button {
                            AppHaptics.light()
                            withAnimation(AppleMotion.fluidSpring) {
                                localValue = Double(restInt)
                            }
                            onChanged(Double(restInt), true)
                        } label: {
                            Image(systemName: "arrow.counterclockwise")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(.secondary)
                                .frame(width: 22, height: 22)
                                .background(Color(.tertiarySystemFill))
                                .clipShape(Circle())
                        }
                        .buttonStyle(TactileScaleButtonStyle(pressedScale: 0.86))
                        .accessibilityLabel("Réinitialiser \(config.label)")
                        .transition(.scale(scale: 0.75).combined(with: .opacity))
                    }

                    Text("\(roundedInt)\(unitSuffix)")
                        .font(.caption.monospacedDigit().weight(.bold))
                        .contentTransition(.numericText())
                        .padding(.horizontal, 9)
                        .padding(.vertical, 3)
                        .background(isDragging ? accent : accent.opacity(0.15))
                        .foregroundStyle(isDragging ? .white : accent)
                        .clipShape(Capsule())
                        .scaleEffect(isDragging ? 1.07 : 1.0)
                        .animation(AppleMotion.pressSpring, value: isDragging)
                        .animation(.easeOut(duration: 0.12), value: roundedInt)
                }
                .animation(AppleMotion.fluidSpring, value: roundedInt == restInt)
            }

            Slider(
                value: Binding(
                    get: { min(max(localValue, minVal), maxVal) },
                    set: { newVal in
                        localValue = newVal
                        onChanged(newVal, false)
                    }
                ),
                in: minVal...maxVal,
                step: 1
            ) { editing in
                withAnimation(AppleMotion.pressSpring) {
                    isDragging = editing
                }
                if !editing {
                    let finalVal = min(max(localValue, minVal), maxVal)
                    onChanged(finalVal, true)
                }
            }
            .tint(accent)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .appleGroupedCard(cornerRadius: 16)
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(isDragging ? accent.opacity(0.55) : .clear, lineWidth: 1.5)
                .animation(AppleMotion.pressSpring, value: isDragging)
        )
        .onChange(of: config) { newConfig in
            let newMin = Double(min(newConfig.minSliderValue, newConfig.maxSliderValue))
            let newMax = Double(max(newConfig.minSliderValue + 1, newConfig.maxSliderValue))
            localValue = min(max(localValue, newMin), newMax)
        }
        .onReceive(externalUpdates) { update in
            if update.slot == slot {
                localValue = min(max(update.value, minVal), maxVal)
            }
        }
    }
}

private struct PS4ConnectionGuideSheet: View {
    @ObservedObject var viewModel: ControllerViewModel
    let onOpenMapping: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section("État actuel") {
                    HStack(spacing: 12) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill((viewModel.isPS4Connected ? Color.green : Color.secondary).opacity(0.14))
                                .frame(width: 42, height: 42)
                            Image(systemName: viewModel.isPS4Connected ? "gamecontroller.fill" : "gamecontroller")
                                .font(.title3)
                                .foregroundStyle(viewModel.isPS4Connected ? Color.green : Color.secondary)
                        }

                        VStack(alignment: .leading, spacing: 3) {
                            Text(viewModel.isPS4Connected ? viewModel.ps4ControllerName : "Aucune manette PS4 détectée")
                                .font(.subheadline.weight(.semibold))
                            if let battery = viewModel.ps4BatteryPercentage {
                                Text("Batterie : \(battery)% • Barre LED synchronisée")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            } else {
                                Text("L'iPhone sert de pont Bluetooth vers votre Arduino.")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }

                    Button {
                        AppHaptics.medium()
                        if viewModel.isPS4Discovering {
                            viewModel.stopPS4Discovery()
                        } else {
                            viewModel.startPS4Discovery()
                        }
                    } label: {
                        HStack {
                            Text(viewModel.isPS4Discovering ? "Recherche en cours..." : "Détecter une manette sans fil")
                            Spacer()
                            if viewModel.isPS4Discovering {
                                ProgressView()
                            }
                        }
                    }

                    Button("Actualiser les manettes connectées") {
                        AppHaptics.light()
                        viewModel.refreshPS4Controllers()
                    }
                }

                Section("Comment appairer une manette PS4 (DualShock 4)") {
                    Label("1. Maintenez simultanément les boutons SHARE + PS pendant 3 secondes jusqu'au clignotement rapide de la barre LED.", systemImage: "1.circle.fill")
                    Label("2. Sur l'iPhone, ouvrez Réglages > Bluetooth et sélectionnez DUALSHOCK 4 Wireless Controller.", systemImage: "2.circle.fill")
                    Label("3. Revenez dans l'application : chaque touche PS4 pilote instantanément l'action assignée à votre Arduino.", systemImage: "3.circle.fill")
                }

                Section("Correspondance PS4 par défaut") {
                    Text("Croix = Bouton A  |  Rond = Bouton B\nCarré = Bouton X  |  Triangle = Bouton Y\nL1 / R1 = Gâchettes  |  L2 / R2 = Curseurs\nShare = Select  |  Options = Start")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Button("Configurer les boutons et sticks dans Assigner") {
                        AppHaptics.selection()
                        dismiss()
                        onOpenMapping()
                    }
                }
            }
            .animation(AppleMotion.fluidSpring, value: viewModel.isPS4Connected)
            .animation(AppleMotion.fluidSpring, value: viewModel.isPS4Discovering)
            .navigationTitle("Manette PS4 Bluetooth")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Fermer") {
                        dismiss()
                    }
                }
            }
        }
    }
}

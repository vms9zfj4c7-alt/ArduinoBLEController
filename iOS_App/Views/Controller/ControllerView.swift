import SwiftUI
import Combine

/// Écran principal de contrôle de l'Arduino, épuré par défaut (Mode Essentiel) ou complet (14 touches).
struct ControllerView: View {
    @ObservedObject var viewModel: ControllerViewModel
    let telemetryStore: BLETelemetryStore
    let onOpenScan: () -> Void
    let onOpenMapping: () -> Void

    @Environment(\.verticalSizeClass) private var verticalSizeClass
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var showPS4GuideSheet = false
    @State private var showConsoleSheet = false

    var body: some View {
        NavigationStack {
            Group {
                if verticalSizeClass == .compact {
                    landscapeContainer
                } else {
                    portraitContainer
                }
            }
            .background(Color(.systemGroupedBackground).ignoresSafeArea())
            .animation(
                AppleMotion.adaptive(AppleMotion.fluidSpring, reduceMotion: reduceMotion),
                value: viewModel.isSimplifiedMode
            )
            .navigationTitle("Manette")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Menu("Options") {
                        Button(
                            viewModel.isSimplifiedMode
                                ? "Mode Complet (14 touches)"
                                : "Mode Essentiel (7 touches)"
                        ) {
                            AppHaptics.selection()
                            withAnimation(AppleMotion.fluidSpring) {
                                viewModel.setSimplifiedMode(!viewModel.isSimplifiedMode)
                            }
                        }

                        Button("Console BLE") {
                            AppHaptics.soft()
                            showConsoleSheet = true
                        }

                        Button(
                            viewModel.isPS4Connected
                                ? "Manette PS4 (\(viewModel.ps4ControllerName))"
                                : "Manette PS4 Bluetooth"
                        ) {
                            AppHaptics.selection()
                            showPS4GuideSheet = true
                        }

                        Button("Configurer les boutons") {
                            AppHaptics.selection()
                            onOpenMapping()
                        }
                    }
                    .font(.subheadline.weight(.medium))
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
            .sheet(isPresented: $showConsoleSheet) {
                NavigationStack {
                    ScrollView {
                        LogConsoleView(
                            logStore: viewModel.logStore,
                            isConnected: viewModel.connectionState.isConnected,
                            alwaysExpanded: true,
                            onSendRawCommand: { viewModel.sendRawCommand($0) },
                            onClearLogs: { viewModel.clearLogs() }
                        )
                        .padding(14)
                    }
                    .background(Color(.systemGroupedBackground).ignoresSafeArea())
                    .scrollDismissesKeyboard(.interactively)
                    .navigationTitle("Console BLE")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Fermer") {
                                showConsoleSheet = false
                            }
                        }
                    }
                }
            }
        }
    }

    // MARK: - Conteneurs Portrait / Paysage

    @ViewBuilder
    private var portraitContainer: some View {
        if viewModel.isSimplifiedMode {
            ViewThatFits(in: .vertical) {
                portraitEssentialLayout
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)

                ScrollView(showsIndicators: false) {
                    portraitEssentialLayout
                        .padding(.horizontal, 14)
                        .padding(.vertical, 12)
                }
                .scrollDismissesKeyboard(.interactively)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        } else {
            ScrollView {
                VStack(spacing: 14) {
                    compactStatusCard(showPS4Prompt: true)
                    portraitFullGamepadLayout
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
            .scrollDismissesKeyboard(.interactively)
        }
    }

    private var landscapeContainer: some View {
        ViewThatFits(in: .vertical) {
            Group {
                if viewModel.isSimplifiedMode {
                    landscapeEssentialCockpit
                } else {
                    landscapeFullCockpit
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 4)

            ScrollView(showsIndicators: false) {
                Group {
                    if viewModel.isSimplifiedMode {
                        landscapeEssentialCockpit
                    } else {
                        landscapeFullCockpit
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 4)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
    }

    // MARK: - Mode Essentiel (Portrait : 1 curseur, croix, A, B, STOP)

    private var portraitEssentialLayout: some View {
        VStack(spacing: 16) {
            compactStatusCard(showPS4Prompt: false)

            sliderCard(for: .sliderLeft, isCompact: false)

            ViewThatFits(in: .horizontal) {
                HStack(alignment: .center, spacing: 12) {
                    DPadClusterView(
                        upAssignment: viewModel.assignment(for: .dpadUp),
                        downAssignment: viewModel.assignment(for: .dpadDown),
                        leftAssignment: viewModel.assignment(for: .dpadLeft),
                        rightAssignment: viewModel.assignment(for: .dpadRight),
                        isUpActive: viewModel.isSlotActive(.dpadUp),
                        isDownActive: viewModel.isSlotActive(.dpadDown),
                        isLeftActive: viewModel.isSlotActive(.dpadLeft),
                        isRightActive: viewModel.isSlotActive(.dpadRight),
                        buttonSize: 58,
                        gridSpacing: 7,
                        containerPadding: 9,
                        cornerRadius: 15,
                        onDown: { viewModel.handleButtonDown(slot: $0) },
                        onUp: { viewModel.handleButtonUp(slot: $0) }
                    )
                    .equatable()

                    EssentialActionPod(
                        slotLetterA: "A",
                        assignmentA: viewModel.assignment(for: .buttonA),
                        isActiveA: viewModel.isSlotActive(.buttonA),
                        slotLetterB: "B",
                        assignmentB: viewModel.assignment(for: .buttonB),
                        isActiveB: viewModel.isSlotActive(.buttonB),
                        includeStopButton: true,
                        buttonHeight: 60,
                        onDown: { viewModel.handleButtonDown(slot: $0) },
                        onUp: { viewModel.handleButtonUp(slot: $0) },
                        onStop: { viewModel.triggerEmergencyStop() }
                    )
                    .equatable()
                    .frame(maxWidth: .infinity)
                }

                VStack(spacing: 14) {
                    portraitDPadCluster
                    EssentialActionPod(
                        slotLetterA: "A",
                        assignmentA: viewModel.assignment(for: .buttonA),
                        isActiveA: viewModel.isSlotActive(.buttonA),
                        slotLetterB: "B",
                        assignmentB: viewModel.assignment(for: .buttonB),
                        isActiveB: viewModel.isSlotActive(.buttonB),
                        includeStopButton: true,
                        buttonHeight: 56,
                        onDown: { viewModel.handleButtonDown(slot: $0) },
                        onUp: { viewModel.handleButtonUp(slot: $0) },
                        onStop: { viewModel.triggerEmergencyStop() }
                    )
                    .equatable()
                }
            }
        }
    }

    // MARK: - Mode Essentiel (Paysage : Cockpit large et aéré)

    private var landscapeEssentialCockpit: some View {
        VStack(spacing: 10) {
            compactLandscapeStatusBar

            HStack(alignment: .center, spacing: 14) {
                DPadClusterView(
                    upAssignment: viewModel.assignment(for: .dpadUp),
                    downAssignment: viewModel.assignment(for: .dpadDown),
                    leftAssignment: viewModel.assignment(for: .dpadLeft),
                    rightAssignment: viewModel.assignment(for: .dpadRight),
                    isUpActive: viewModel.isSlotActive(.dpadUp),
                    isDownActive: viewModel.isSlotActive(.dpadDown),
                    isLeftActive: viewModel.isSlotActive(.dpadLeft),
                    isRightActive: viewModel.isSlotActive(.dpadRight),
                    buttonSize: 54,
                    gridSpacing: 6,
                    containerPadding: 9,
                    cornerRadius: 14,
                    isCompact: true,
                    onDown: { viewModel.handleButtonDown(slot: $0) },
                    onUp: { viewModel.handleButtonUp(slot: $0) }
                )
                .equatable()

                VStack(spacing: 12) {
                    sliderCard(for: .sliderLeft, isCompact: false)

                    EmergencyStopHoldButton(
                        font: .subheadline.weight(.black),
                        minHeight: 46,
                        onTrigger: { viewModel.triggerEmergencyStop() }
                    )
                }
                .frame(maxWidth: .infinity)

                EssentialActionPod(
                    slotLetterA: "A",
                    assignmentA: viewModel.assignment(for: .buttonA),
                    isActiveA: viewModel.isSlotActive(.buttonA),
                    slotLetterB: "B",
                    assignmentB: viewModel.assignment(for: .buttonB),
                    isActiveB: viewModel.isSlotActive(.buttonB),
                    includeStopButton: false,
                    buttonHeight: 62,
                    onDown: { viewModel.handleButtonDown(slot: $0) },
                    onUp: { viewModel.handleButtonUp(slot: $0) },
                    onStop: { viewModel.triggerEmergencyStop() }
                )
                .equatable()
                .frame(width: 142)
            }
        }
    }

    // MARK: - En-tête Unifié

    private func compactStatusCard(showPS4Prompt: Bool) -> some View {
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
                        .minimumScaleFactor(0.85)
                        .layoutPriority(1)

                    HStack(spacing: 6) {
                        Text(viewModel.activeTransport.shortBadge)
                            .font(.caption2.weight(.bold))
                            .tracking(0.3)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 1)
                            .background((viewModel.activeTransport == .wifi ? Color.teal : Color.indigo).opacity(0.16))
                            .foregroundStyle(viewModel.activeTransport == .wifi ? Color.teal : Color.indigo)
                            .clipShape(Capsule())
                            .fixedSize(horizontal: true, vertical: false)
                        Text(viewModel.boardCapability.boardType.shortBadge)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        if viewModel.boardCapability.isAutoDetected {
                            Text("Auto")
                                .font(.caption2.weight(.bold))
                                .tracking(0.3)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 1)
                                .background(Color.blue.opacity(0.14))
                                .foregroundStyle(.blue)
                                .clipShape(Capsule())
                        }
                        if viewModel.isPS4Connected {
                            Text("PS4")
                                .font(.caption2.weight(.bold))
                                .tracking(0.3)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 1)
                                .background(Color.green.opacity(0.16))
                                .foregroundStyle(.green)
                                .clipShape(Capsule())
                        }
                    }
                }

                Spacer(minLength: 4)

                if viewModel.connectionState.isConnected {
                    TelemetryBadgesView(
                        telemetryStore: telemetryStore,
                        onRequestTelemetry: {
                            AppHaptics.light()
                            viewModel.requestTelemetry()
                        }
                    )
                } else {
                    HStack(spacing: 6) {
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
                }
            }

            if showPS4Prompt {
                Divider()
                    .opacity(0.45)

                HStack(spacing: 8) {
                    Button {
                        AppHaptics.selection()
                        showPS4GuideSheet = true
                    } label: {
                        HStack(spacing: 7) {
                            Circle()
                                .fill(viewModel.isPS4Connected ? Color.green : Color.secondary.opacity(0.5))
                                .frame(width: 7, height: 7)
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
            }
        }
        .padding(12)
        .appleGroupedCard(cornerRadius: 18)
        .animation(AppleMotion.fluidSpring, value: viewModel.connectionState)
        .animation(AppleMotion.fluidSpring, value: viewModel.isPS4Connected)
    }

    // MARK: - Mode Complet Portrait (14 touches)

    private var portraitFullGamepadLayout: some View {
        VStack(spacing: 14) {
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

            VStack(spacing: 10) {
                sliderCard(for: .sliderLeft, isCompact: false)
                sliderCard(for: .sliderRight, isCompact: false)
            }

            ViewThatFits(in: .horizontal) {
                HStack(alignment: .center, spacing: 12) {
                    portraitDPadCluster
                    Spacer(minLength: 4)
                    portraitActionCluster
                }

                VStack(spacing: 14) {
                    portraitDPadCluster
                    portraitActionCluster
                }
            }
        }
    }

    // MARK: - Mode Complet Paysage (14 touches)

    private var landscapeFullCockpit: some View {
        VStack(spacing: 6) {
            compactLandscapeStatusBar

            HStack(alignment: .center, spacing: 10) {
                VStack(spacing: 5) {
                    HStack(spacing: 8) {
                        ShoulderPillButton(
                            slotCode: "L1",
                            assignment: viewModel.assignment(for: .shoulderL1),
                            isActive: viewModel.isSlotActive(.shoulderL1),
                            isCompact: true,
                            onDown: { viewModel.handleButtonDown(slot: .shoulderL1) },
                            onUp: { viewModel.handleButtonUp(slot: .shoulderL1) }
                        )
                        .equatable()
                        .frame(width: 60)

                        sliderCard(for: .sliderLeft, isCompact: true)
                    }

                    DPadClusterView(
                        upAssignment: viewModel.assignment(for: .dpadUp),
                        downAssignment: viewModel.assignment(for: .dpadDown),
                        leftAssignment: viewModel.assignment(for: .dpadLeft),
                        rightAssignment: viewModel.assignment(for: .dpadRight),
                        isUpActive: viewModel.isSlotActive(.dpadUp),
                        isDownActive: viewModel.isSlotActive(.dpadDown),
                        isLeftActive: viewModel.isSlotActive(.dpadLeft),
                        isRightActive: viewModel.isSlotActive(.dpadRight),
                        buttonSize: 44,
                        gridSpacing: 4,
                        containerPadding: 7,
                        cornerRadius: 12,
                        isCompact: true,
                        onDown: { viewModel.handleButtonDown(slot: $0) },
                        onUp: { viewModel.handleButtonUp(slot: $0) }
                    )
                    .equatable()
                }
                .frame(maxWidth: .infinity)

                VStack(spacing: 7) {
                    ShoulderPillButton(
                        slotCode: "SEL",
                        assignment: viewModel.assignment(for: .select),
                        isActive: viewModel.isSlotActive(.select),
                        isCompact: true,
                        onDown: { viewModel.handleButtonDown(slot: .select) },
                        onUp: { viewModel.handleButtonUp(slot: .select) }
                    )
                    .equatable()

                    ShoulderPillButton(
                        slotCode: "STA",
                        assignment: viewModel.assignment(for: .start),
                        isActive: viewModel.isSlotActive(.start),
                        isCompact: true,
                        onDown: { viewModel.handleButtonDown(slot: .start) },
                        onUp: { viewModel.handleButtonUp(slot: .start) }
                    )
                    .equatable()

                    EmergencyStopHoldButton(
                        font: .caption.weight(.black),
                        minHeight: 36,
                        onTrigger: { viewModel.triggerEmergencyStop() }
                    )

                    ConsoleSheetButton(logStore: viewModel.logStore) {
                        AppHaptics.soft()
                        showConsoleSheet = true
                    }
                }
                .frame(width: 96)

                VStack(spacing: 5) {
                    HStack(spacing: 8) {
                        sliderCard(for: .sliderRight, isCompact: true)

                        ShoulderPillButton(
                            slotCode: "R1",
                            assignment: viewModel.assignment(for: .shoulderR1),
                            isActive: viewModel.isSlotActive(.shoulderR1),
                            isCompact: true,
                            onDown: { viewModel.handleButtonDown(slot: .shoulderR1) },
                            onUp: { viewModel.handleButtonUp(slot: .shoulderR1) }
                        )
                        .equatable()
                        .frame(width: 60)
                    }

                    ActionButtonsClusterView(
                        buttonY: viewModel.assignment(for: .buttonY),
                        buttonX: viewModel.assignment(for: .buttonX),
                        buttonB: viewModel.assignment(for: .buttonB),
                        buttonA: viewModel.assignment(for: .buttonA),
                        isYActive: viewModel.isSlotActive(.buttonY),
                        isXActive: viewModel.isSlotActive(.buttonX),
                        isBActive: viewModel.isSlotActive(.buttonB),
                        isAActive: viewModel.isSlotActive(.buttonA),
                        buttonSize: 50,
                        middleGap: 44,
                        verticalGap: -6,
                        containerPadding: 8,
                        isCompact: true,
                        onDown: { viewModel.handleButtonDown(slot: $0) },
                        onUp: { viewModel.handleButtonUp(slot: $0) }
                    )
                    .equatable()
                }
                .frame(maxWidth: .infinity)
            }
        }
    }

    private var compactLandscapeStatusBar: some View {
        HStack(spacing: 8) {
            LivePulseBeacon(
                color: statusColor,
                isPulsing: viewModel.connectionState.isBusy,
                dotSize: 8
            )

            Text(viewModel.connectionState.statusText)
                .font(.caption.weight(.semibold))
                .lineLimit(1)

            Text(viewModel.activeTransport.shortBadge)
                .font(.caption2.weight(.bold))
                .foregroundStyle(viewModel.activeTransport == .wifi ? Color.teal : Color.indigo)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background((viewModel.activeTransport == .wifi ? Color.teal : Color.indigo).opacity(0.16))
                .clipShape(Capsule())
                .fixedSize(horizontal: true, vertical: false)

            Text(viewModel.boardCapability.boardType.shortBadge)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color(.tertiarySystemFill))
                .clipShape(Capsule())

            Spacer(minLength: 4)

            TelemetryBadgesView(
                telemetryStore: telemetryStore,
                onRequestTelemetry: {
                    AppHaptics.light()
                    viewModel.requestTelemetry()
                }
            )

            if viewModel.isPS4Connected {
                Button {
                    AppHaptics.selection()
                    showPS4GuideSheet = true
                } label: {
                    HStack(spacing: 4) {
                        Circle()
                            .fill(Color.green)
                            .frame(width: 6, height: 6)
                        if let battery = viewModel.ps4BatteryPercentage {
                            Text("PS4 \(battery)%")
                                .monospacedDigit()
                                .contentTransition(.numericText())
                        } else {
                            Text("PS4")
                        }
                    }
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.primary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color(.tertiarySystemFill))
                    .clipShape(Capsule())
                }
                .buttonStyle(TactileScaleButtonStyle(pressedScale: 0.92))
            }

            if !viewModel.connectionState.isConnected {
                if case .disconnected = viewModel.connectionState,
                   viewModel.lastConnectedDeviceName != nil {
                    Button("Reconnecter") {
                        AppHaptics.medium()
                        viewModel.reconnectLastDevice()
                    }
                    .font(.caption2.weight(.semibold))
                    .buttonStyle(.bordered)
                    .controlSize(.mini)
                }

                Button("Scanner") {
                    AppHaptics.selection()
                    onOpenScan()
                }
                .font(.caption2.weight(.semibold))
                .buttonStyle(.borderedProminent)
                .controlSize(.mini)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .appleGroupedCard(cornerRadius: 14)
        .animation(AppleMotion.fluidSpring, value: viewModel.connectionState)
    }

    private func sliderCard(for slot: GamepadSlot, isCompact: Bool) -> some View {
        AnalogSliderCard(
            slot: slot,
            config: viewModel.assignment(for: slot),
            initialValue: viewModel.initialSliderValue(for: slot),
            isCompact: isCompact,
            externalUpdates: viewModel.externalSliderUpdates,
            onChanged: { value, isFinal in
                viewModel.handleSliderChanged(slot: slot, value: value, isFinal: isFinal)
            }
        )
    }

    private var portraitDPadCluster: some View {
        DPadClusterView(
            upAssignment: viewModel.assignment(for: .dpadUp),
            downAssignment: viewModel.assignment(for: .dpadDown),
            leftAssignment: viewModel.assignment(for: .dpadLeft),
            rightAssignment: viewModel.assignment(for: .dpadRight),
            isUpActive: viewModel.isSlotActive(.dpadUp),
            isDownActive: viewModel.isSlotActive(.dpadDown),
            isLeftActive: viewModel.isSlotActive(.dpadLeft),
            isRightActive: viewModel.isSlotActive(.dpadRight),
            buttonSize: 54,
            gridSpacing: 6,
            containerPadding: 9,
            cornerRadius: 14,
            onDown: { viewModel.handleButtonDown(slot: $0) },
            onUp: { viewModel.handleButtonUp(slot: $0) }
        )
        .equatable()
    }

    private var portraitActionCluster: some View {
        ActionButtonsClusterView(
            buttonY: viewModel.assignment(for: .buttonY),
            buttonX: viewModel.assignment(for: .buttonX),
            buttonB: viewModel.assignment(for: .buttonB),
            buttonA: viewModel.assignment(for: .buttonA),
            isYActive: viewModel.isSlotActive(.buttonY),
            isXActive: viewModel.isSlotActive(.buttonX),
            isBActive: viewModel.isSlotActive(.buttonB),
            isAActive: viewModel.isSlotActive(.buttonA),
            buttonSize: 54,
            middleGap: 34,
            verticalGap: 0,
            containerPadding: 9,
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

/// Bloc d'actions simplifié (A, B et bouton STOP optionnel) pour le Mode Essentiel.
private struct EssentialActionPod: View, Equatable {
    let slotLetterA: String
    let assignmentA: ButtonAssignment
    let isActiveA: Bool

    let slotLetterB: String
    let assignmentB: ButtonAssignment
    let isActiveB: Bool

    let includeStopButton: Bool
    let buttonHeight: CGFloat

    let onDown: (GamepadSlot) -> Void
    let onUp: (GamepadSlot) -> Void
    let onStop: () -> Void

    static func == (lhs: EssentialActionPod, rhs: EssentialActionPod) -> Bool {
        lhs.assignmentA == rhs.assignmentA
            && lhs.isActiveA == rhs.isActiveA
            && lhs.assignmentB == rhs.assignmentB
            && lhs.isActiveB == rhs.isActiveB
            && lhs.includeStopButton == rhs.includeStopButton
            && lhs.buttonHeight == rhs.buttonHeight
    }

    var body: some View {
        VStack(spacing: 10) {
            essentialKey(slotCode: slotLetterA, assignment: assignmentA, isActive: isActiveA) {
                onDown(.buttonA)
            } onUp: {
                onUp(.buttonA)
            }

            essentialKey(slotCode: slotLetterB, assignment: assignmentB, isActive: isActiveB) {
                onDown(.buttonB)
            } onUp: {
                onUp(.buttonB)
            }

            if includeStopButton {
                EmergencyStopHoldButton(
                    font: .subheadline.weight(.black),
                    minHeight: 46,
                    onTrigger: onStop
                )
            }
        }
        .padding(11)
        .appleGroupedCard(cornerRadius: 26)
    }

    private func essentialKey(
        slotCode: String,
        assignment: ButtonAssignment,
        isActive: Bool,
        onDown: @escaping () -> Void,
        onUp: @escaping () -> Void
    ) -> some View {
        let color = assignment.colorToken.color
        let shape = RoundedRectangle(cornerRadius: 16, style: .continuous)

        return TactileHoldControl(
            hitShape: shape,
            isActive: isActive,
            pressedScale: 0.93,
            onDown: onDown,
            onUp: onUp
        ) { highlighted, _ in
            VStack(spacing: 2) {
                Text(slotCode)
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .tracking(0.4)
                    .opacity(highlighted ? 0.85 : 0.72)
                    .frame(maxWidth: .infinity)
                Text(assignment.label)
                    .font(.system(size: 14, weight: .bold))
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .minimumScaleFactor(0.7)
                    .frame(maxWidth: .infinity)
            }
            .foregroundStyle(highlighted ? .white : color)
            .padding(.horizontal, 8)
            .frame(maxWidth: .infinity, minHeight: buttonHeight, alignment: .center)
            .background(
                HardwareKeycapBackground(
                    shape: shape,
                    color: color,
                    highlighted: highlighted
                )
            )
        }
        .accessibilityLabel("\(slotCode) \(assignment.label)")
    }
}

/// Bouton compact isolé affichant le compteur de logs en mode paysage sans redessiner la manette.
private struct ConsoleSheetButton: View {
    @ObservedObject var logStore: BLELogStore
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            Text("Logs (\(logStore.totalCount))")
                .font(.caption2.monospacedDigit().weight(.semibold))
                .contentTransition(.numericText())
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 7)
                .background(Color(.tertiarySystemFill))
                .clipShape(Capsule())
        }
        .buttonStyle(TactileScaleButtonStyle(pressedScale: 0.92))
        .animation(AppleMotion.fluidSpring, value: logStore.totalCount)
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
                        Text(String(format: "%.1f °C", temp))
                            .monospacedDigit()
                            .contentTransition(.numericText())
                        if telemetryStore.isTemperatureSimulated {
                            Text("démo")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 9)
                    .padding(.vertical, 4)
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
                .padding(.vertical, 4)
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
    var isCompact: Bool = false
    let onDown: () -> Void
    let onUp: () -> Void

    static func == (lhs: ShoulderPillButton, rhs: ShoulderPillButton) -> Bool {
        lhs.slotCode == rhs.slotCode
            && lhs.assignment == rhs.assignment
            && lhs.isActive == rhs.isActive
            && lhs.isCompact == rhs.isCompact
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
            VStack(spacing: 1) {
                Text(slotCode)
                    .font(.system(size: isCompact ? 8.5 : 9, weight: .bold))
                    .tracking(0.4)
                    .opacity(highlighted ? 0.85 : 0.72)
                    .frame(maxWidth: .infinity)
                Text(assignment.label)
                    .font(.system(size: isCompact ? 11 : 12, weight: .semibold))
                    .multilineTextAlignment(.center)
                    .lineLimit(1)
                    .minimumScaleFactor(0.68)
                    .frame(maxWidth: .infinity)
            }
            .foregroundStyle(highlighted ? .white : color)
            .frame(maxWidth: .infinity)
            .padding(.vertical, isCompact ? 6 : 8)
            .padding(.horizontal, 8)
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
    let isCompact: Bool
    let onChanged: (Double, Bool) -> Void

    @State private var localValue: Double
    @State private var isDragging: Bool = false

    init(
        slot: GamepadSlot,
        config: ButtonAssignment,
        initialValue: Double,
        isCompact: Bool = false,
        externalUpdates: PassthroughSubject<(slot: GamepadSlot, value: Double), Never>,
        onChanged: @escaping (Double, Bool) -> Void
    ) {
        self.slot = slot
        self.config = config
        self.isCompact = isCompact
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
        let radius: CGFloat = isCompact ? 13 : 16

        VStack(spacing: isCompact ? 2 : 6) {
            HStack(spacing: 6) {
                Text(config.label)
                    .font(isCompact ? .caption2.weight(.semibold) : .subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                if !isCompact {
                    Text("P\(config.primaryPin)")
                        .font(.caption2.weight(.semibold))
                        .tracking(0.3)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color(.tertiarySystemFill))
                        .clipShape(Capsule())
                        .lineLimit(1)
                }

                Spacer(minLength: 4)

                HStack(spacing: 5) {
                    if roundedInt != restInt {
                        Button {
                            AppHaptics.light()
                            withAnimation(AppleMotion.fluidSpring) {
                                localValue = Double(restInt)
                            }
                            onChanged(Double(restInt), true)
                        } label: {
                            Text("RàZ")
                                .font(.system(size: isCompact ? 9 : 10, weight: .semibold))
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color(.tertiarySystemFill))
                                .clipShape(Capsule())
                        }
                        .buttonStyle(TactileScaleButtonStyle(pressedScale: 0.88))
                        .accessibilityLabel("Réinitialiser \(config.label)")
                        .transition(.scale(scale: 0.75).combined(with: .opacity))
                    }

                    Text("\(roundedInt)\(unitSuffix)")
                        .font((isCompact ? Font.caption2 : Font.caption).monospacedDigit().weight(.bold))
                        .contentTransition(.numericText())
                        .padding(.horizontal, isCompact ? 7 : 9)
                        .padding(.vertical, isCompact ? 2 : 3)
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
        .padding(.horizontal, isCompact ? 10 : 14)
        .padding(.vertical, isCompact ? 5 : 10)
        .appleGroupedCard(cornerRadius: radius)
        .overlay(
            RoundedRectangle(cornerRadius: radius, style: .continuous)
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

    private static let defaultMappings: [(ps4: String, slot: String)] = [
        ("Croix / Rond", "Bouton A / Bouton B"),
        ("Carré / Triangle", "Bouton X / Bouton Y"),
        ("L1 / R1", "Gâchettes L1 / R1"),
        ("L2 / R2", "Curseurs L2 / R2"),
        ("Share / Options", "Select / Start")
    ]

    var body: some View {
        NavigationStack {
            List {
                Section("État actuel") {
                    HStack(spacing: 12) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill((viewModel.isPS4Connected ? Color.green : Color.secondary).opacity(0.14))
                                .frame(width: 42, height: 42)
                            Text("PS4")
                                .font(.caption.weight(.black))
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
                    stepRow(number: "1", text: "Maintenez simultanément SHARE + PS pendant 3 secondes jusqu'au clignotement rapide de la barre LED.")
                    stepRow(number: "2", text: "Sur l'iPhone, ouvrez Réglages > Bluetooth et sélectionnez DUALSHOCK 4 Wireless Controller.")
                    stepRow(number: "3", text: "Revenez dans l'application : chaque touche PS4 pilote instantanément l'action assignée.")
                }

                Section("Correspondance PS4 par défaut") {
                    ForEach(Self.defaultMappings, id: \.ps4) { item in
                        LabeledContent(item.ps4, value: item.slot)
                            .font(.subheadline)
                    }

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

    private func stepRow(number: String, text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text(number)
                .font(.caption.weight(.bold))
                .foregroundStyle(Color.accentColor)
                .frame(width: 22, height: 22)
                .background(Color.accentColor.opacity(0.14))
                .clipShape(Circle())
            Text(text)
                .font(.footnote)
                .foregroundStyle(.primary)
        }
        .padding(.vertical, 2)
    }
}

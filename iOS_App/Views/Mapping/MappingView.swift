import SwiftUI

/// Page de configuration permettant d'assigner chaque bouton style manette et d'adapter la carte Arduino.
struct MappingView: View {
    @ObservedObject var viewModel: MappingViewModel
    @State private var didAdaptPinsFeedback = false
    @State private var adaptFeedbackWorkItem: DispatchWorkItem?

    private static let slotGroups: [(title: String, slots: [GamepadSlot])] = [
        ("Croix directionnelle", [.dpadUp, .dpadDown, .dpadLeft, .dpadRight]),
        ("Boutons d'action", [.buttonA, .buttonB, .buttonX, .buttonY]),
        ("Gâchettes & Système", [.shoulderL1, .shoulderR1, .select, .start]),
        ("Curseurs analogiques", [.sliderLeft, .sliderRight])
    ]

    var body: some View {
        NavigationStack {
            List {
                boardAdaptationSection
                ps4ControllerSection
                presetsSection
                interactiveGamepadSection

                ForEach(Self.slotGroups, id: \.title) { group in
                    Section(group.title) {
                        ForEach(group.slots) { slot in
                            let assignment = viewModel.assignment(for: slot)
                            Button {
                                AppHaptics.selection()
                                viewModel.selectedSlotForEditing = slot
                            } label: {
                                AssignmentRowView(slot: slot, assignment: assignment)
                                    .contentShape(Rectangle())
                            }
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Assigner Manette")
            .onDisappear {
                adaptFeedbackWorkItem?.cancel()
                adaptFeedbackWorkItem = nil
            }
            .sheet(item: $viewModel.selectedSlotForEditing) { slot in
                ButtonAssignmentEditorView(
                    assignment: viewModel.assignment(for: slot),
                    boardCapability: viewModel.boardCapability,
                    isConnected: viewModel.isConnected,
                    onSave: { updated in
                        viewModel.saveAssignment(updated)
                    },
                    onTest: { candidate, isActive in
                        viewModel.testAssignment(candidate, isActive: isActive)
                    }
                )
            }
        }
    }

    // MARK: - Sections

    private var boardAdaptationSection: some View {
        Section {
            Picker(
                "Profil Arduino",
                selection: Binding(
                    get: { viewModel.selectedBoardPreference },
                    set: { newPref in
                        AppHaptics.selection()
                        withAnimation(AppleMotion.fluidSpring) {
                            viewModel.selectBoardPreference(newPref)
                        }
                    }
                )
            ) {
                ForEach(ArduinoBoardType.allCases) { board in
                    Text(board.displayName).tag(board)
                }
            }

            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Carte active")
                        .font(.subheadline.weight(.medium))
                    HStack(spacing: 4) {
                        Text(viewModel.boardCapability.boardType.displayName)
                        Text("•")
                        Text("\(viewModel.boardCapability.availablePins.count)")
                            .monospacedDigit()
                            .contentTransition(.numericText())
                        Text("broches")
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
                Spacer()
                Text(viewModel.boardCapability.isAutoDetected ? "Auto" : "Manuel")
                    .font(.caption2.weight(.bold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color.accentColor.opacity(0.15))
                    .foregroundStyle(Color.accentColor)
                    .clipShape(Capsule())
            }
            .animation(AppleMotion.fluidSpring, value: viewModel.boardCapability)

            Button {
                triggerAdaptWithFeedback()
            } label: {
                HStack {
                    Text("Réadapter automatiquement les broches")
                        .font(.subheadline.weight(.medium))
                    Spacer()
                    if didAdaptPinsFeedback {
                        Text("Adapté")
                            .font(.caption2.weight(.bold))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(Color.green.opacity(0.16))
                            .foregroundStyle(.green)
                            .clipShape(Capsule())
                            .transition(.scale(scale: 0.7).combined(with: .opacity))
                    }
                }
                .contentShape(Rectangle())
            }
            .animation(AppleMotion.fluidSpring, value: didAdaptPinsFeedback)
        } header: {
            Text("Adaptation à la carte Arduino")
        } footer: {
            Text("En mode Auto-détection, l'application interroge l'Arduino à la connexion et ajuste les broches disponibles (Uno + HM-10, Uno R4 WiFi, Nano 33 BLE, ESP32, Mega).")
        }
    }

    private var presetsSection: some View {
        Section("Modèles prêts à l'emploi") {
            ForEach(BuiltInPresetKind.allCases) { preset in
                Button {
                    AppHaptics.medium()
                    withAnimation(AppleMotion.fluidSpring) {
                        viewModel.applyPreset(preset)
                    }
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(preset.title)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.primary)
                            Text(preset.subtitle)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        if viewModel.activePreset == preset {
                            Text("Actif")
                                .font(.caption2.weight(.bold))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(Color.accentColor.opacity(0.16))
                                .foregroundStyle(Color.accentColor)
                                .clipShape(Capsule())
                                .transition(.scale(scale: 0.7).combined(with: .opacity))
                        }
                    }
                    .contentShape(Rectangle())
                }
                .animation(AppleMotion.fluidSpring, value: viewModel.activePreset)
            }
        }
    }

    private var ps4ControllerSection: some View {
        Section {
            HStack(spacing: 10) {
                Circle()
                    .fill(viewModel.isPS4Connected ? Color.green : Color.secondary.opacity(0.45))
                    .frame(width: 9, height: 9)

                VStack(alignment: .leading, spacing: 2) {
                    Text(viewModel.isPS4Connected ? viewModel.ps4ControllerName : "Aucune manette PS4 connectée")
                        .font(.subheadline.weight(.medium))
                    if let battery = viewModel.ps4BatteryPercentage {
                        HStack(spacing: 3) {
                            Text("Batterie :")
                            Text("\(battery)%")
                                .monospacedDigit()
                                .contentTransition(.numericText())
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    } else {
                        Text("Appairez la DualShock 4 dans Réglages > Bluetooth")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                Button("Actualiser") {
                    AppHaptics.light()
                    viewModel.refreshPS4Controllers()
                }
                .font(.caption.weight(.semibold))
                .buttonStyle(.bordered)
                .controlSize(.mini)
            }
            .animation(AppleMotion.fluidSpring, value: viewModel.isPS4Connected)

            Toggle(
                "Stick gauche -> Croix directionnelle",
                isOn: Binding(
                    get: { viewModel.ps4LeftStickAsDPad },
                    set: { newVal in
                        AppHaptics.light()
                        viewModel.updatePS4Options(
                            leftStickAsDPad: newVal,
                            rightStickAsSliders: viewModel.ps4RightStickAsSliders
                        )
                    }
                )
            )

            Toggle(
                "Stick droit -> Curseurs L2 / R2",
                isOn: Binding(
                    get: { viewModel.ps4RightStickAsSliders },
                    set: { newVal in
                        AppHaptics.light()
                        viewModel.updatePS4Options(
                            leftStickAsDPad: viewModel.ps4LeftStickAsDPad,
                            rightStickAsSliders: newVal
                        )
                    }
                )
            )
        } header: {
            Text("Manette PS4 / DualShock 4 Bluetooth")
        } footer: {
            Text("Les touches de la manette PS4 (Croix, Rond, Carré, Triangle, L1/R1, L2/R2, Share, Options et croix directionnelle) utilisent directement les assignations ci-dessous.")
        }
    }

    private var interactiveGamepadSection: some View {
        Section {
            VStack(spacing: 12) {
                // Rangée haute : gâchettes et curseurs
                HStack(spacing: 6) {
                    miniSlotPill(.shoulderL1)
                    miniSlotPill(.sliderLeft)
                    miniSlotPill(.select)
                    miniSlotPill(.start)
                    miniSlotPill(.sliderRight)
                    miniSlotPill(.shoulderR1)
                }

                HStack(alignment: .center, spacing: 14) {
                    // Mini D-Pad visuel centré
                    VStack(spacing: 4) {
                        miniSquareButton(.dpadUp)
                        HStack(spacing: 4) {
                            miniSquareButton(.dpadLeft)
                            RoundedRectangle(cornerRadius: 7, style: .continuous)
                                .fill(Color(.tertiarySystemFill))
                                .frame(width: 34, height: 34)
                            miniSquareButton(.dpadRight)
                        }
                        miniSquareButton(.dpadDown)
                    }

                    Spacer(minLength: 4)

                    // Mini losange A/B/X/Y centré
                    VStack(spacing: 2) {
                        miniCircleButton(.buttonY)
                        HStack(spacing: 24) {
                            miniCircleButton(.buttonX)
                            miniCircleButton(.buttonB)
                        }
                        miniCircleButton(.buttonA)
                    }
                }
                .padding(.horizontal, 4)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .animation(AppleMotion.fluidSpring, value: viewModel.assignments)
        } header: {
            Text("Manette interactive (touchez un bouton à configurer)")
        }
    }

    private func triggerAdaptWithFeedback() {
        adaptFeedbackWorkItem?.cancel()
        AppHaptics.success()
        withAnimation(AppleMotion.fluidSpring) {
            viewModel.adaptPresetToCurrentBoard()
            didAdaptPinsFeedback = true
        }
        let item = DispatchWorkItem {
            withAnimation(AppleMotion.fluidSpring) {
                didAdaptPinsFeedback = false
            }
        }
        adaptFeedbackWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.6, execute: item)
    }

    private func miniSlotPill(_ slot: GamepadSlot) -> some View {
        let config = viewModel.assignment(for: slot)
        let color = config.colorToken.color
        let shape = RoundedRectangle(cornerRadius: 8, style: .continuous)
        return Button {
            AppHaptics.selection()
            viewModel.selectedSlotForEditing = slot
        } label: {
            VStack(spacing: 1) {
                Text(slot.shortCode)
                    .font(.system(size: 10, weight: .bold))
                Text(config.label)
                    .font(.system(size: 8, weight: .medium))
                    .multilineTextAlignment(.center)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
            .foregroundStyle(color)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 2)
            .padding(.vertical, 6)
            .background(color.opacity(0.14))
            .overlay(
                shape.strokeBorder(color.opacity(0.45), lineWidth: 1)
            )
            .clipShape(shape)
        }
        .buttonStyle(.borderless)
    }

    private func miniSquareButton(_ slot: GamepadSlot) -> some View {
        let config = viewModel.assignment(for: slot)
        let color = config.colorToken.color
        let shape = RoundedRectangle(cornerRadius: 10, style: .continuous)
        return Button {
            AppHaptics.selection()
            viewModel.selectedSlotForEditing = slot
        } label: {
            VStack(spacing: 1) {
                Text(slot.shortCode)
                    .font(.system(size: 12, weight: .bold))
                Text(config.summaryPinBadge)
                    .font(.system(size: 8, weight: .semibold))
                    .multilineTextAlignment(.center)
                    .lineLimit(1)
            }
            .foregroundStyle(color)
            .frame(width: 42, height: 42, alignment: .center)
            .background(color.opacity(0.15))
            .overlay(
                shape.strokeBorder(color.opacity(0.5), lineWidth: 1)
            )
            .clipShape(shape)
        }
        .buttonStyle(.borderless)
    }

    private func miniCircleButton(_ slot: GamepadSlot) -> some View {
        let config = viewModel.assignment(for: slot)
        let color = config.colorToken.color
        return Button {
            AppHaptics.selection()
            viewModel.selectedSlotForEditing = slot
        } label: {
            VStack(spacing: 1) {
                Text(slot.shortCode)
                    .font(.system(size: 11, weight: .black))
                Text(config.summaryPinBadge)
                    .font(.system(size: 8, weight: .semibold))
                    .multilineTextAlignment(.center)
                    .lineLimit(1)
            }
            .foregroundStyle(color)
            .frame(width: 42, height: 42, alignment: .center)
            .background(color.opacity(0.15))
            .overlay(
                Circle()
                    .strokeBorder(color.opacity(0.55), lineWidth: 1.2)
            )
            .clipShape(Circle())
        }
        .buttonStyle(.borderless)
    }
}

private struct AssignmentRowView: View {
    let slot: GamepadSlot
    let assignment: ButtonAssignment

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(assignment.colorToken.color.opacity(0.16))
                    .frame(width: 40, height: 40)
                Text(slot.shortCode)
                    .font(.caption.weight(.black))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(assignment.colorToken.color)
            }

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(slot.slotDisplayName)
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.secondary)
                    Text("•")
                        .foregroundStyle(.secondary)
                    Text(assignment.label)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                }

                Text(assignment.summaryDescription)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Text(slot.ps4Hint)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            Spacer()

            Text("Modifier")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 2)
    }
}

private extension ButtonAssignment {
    var summaryPinBadge: String {
        switch actionType {
        case .pinDigital, .pinPWM, .pinServo:
            return "P\(primaryPin)"
        case .multiPin:
            return "Multi"
        case .customCommand:
            return "Txt"
        case .emergencyStop:
            return "STOP"
        }
    }
}

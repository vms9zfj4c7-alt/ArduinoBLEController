import SwiftUI

/// Page de configuration simplifiée permettant d'assigner chaque touche en 1 appui.
struct MappingView: View {
    @ObservedObject var viewModel: MappingViewModel
    @State private var didAdaptPinsFeedback = false
    @State private var adaptFeedbackWorkItem: DispatchWorkItem?

    private static let essentialSlotGroups: [(title: String, slots: [GamepadSlot])] = [
        ("Croix directionnelle", [.dpadUp, .dpadDown, .dpadLeft, .dpadRight]),
        ("Actions & Curseur", [.buttonA, .buttonB, .sliderLeft])
    ]

    private static let fullSlotGroups: [(title: String, slots: [GamepadSlot])] = [
        ("Croix directionnelle", [.dpadUp, .dpadDown, .dpadLeft, .dpadRight]),
        ("Boutons d'action", [.buttonA, .buttonB, .buttonX, .buttonY]),
        ("Gâchettes & Système", [.shoulderL1, .shoulderR1, .select, .start]),
        ("Curseurs analogiques", [.sliderLeft, .sliderRight])
    ]

    private var displayedGroups: [(title: String, slots: [GamepadSlot])] {
        viewModel.isSimplifiedMode ? Self.essentialSlotGroups : Self.fullSlotGroups
    }

    var body: some View {
        NavigationStack {
            List {
                quickModeAndPresetSection
                interactiveGamepadSection

                ForEach(displayedGroups, id: \.title) { group in
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

                boardHardwareSection
                ps4ControllerSection
            }
            .listStyle(.insetGrouped)
            .animation(AppleMotion.fluidSpring, value: viewModel.isSimplifiedMode)
            .navigationTitle("Assigner")
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

    private var quickModeAndPresetSection: some View {
        Section {
            Picker(
                "Disposition",
                selection: Binding(
                    get: { viewModel.isSimplifiedMode },
                    set: { enabled in
                        AppHaptics.selection()
                        withAnimation(AppleMotion.fluidSpring) {
                            viewModel.setSimplifiedMode(enabled)
                        }
                    }
                )
            ) {
                Text("Essentiel (7)").tag(true)
                Text("Complet (14)").tag(false)
            }
            .pickerStyle(.segmented)
            .listRowInsets(EdgeInsets(top: 10, leading: 14, bottom: 10, trailing: 14))

            Picker(
                "Modèle prêt à l'emploi",
                selection: Binding(
                    get: { viewModel.activePreset },
                    set: { preset in
                        AppHaptics.medium()
                        withAnimation(AppleMotion.fluidSpring) {
                            viewModel.applyPreset(preset)
                        }
                    }
                )
            ) {
                ForEach(BuiltInPresetKind.allCases) { preset in
                    Text(preset.title).tag(preset)
                }
            }
        } header: {
            Text("Manette & Modèle")
        }
    }

    private var interactiveGamepadSection: some View {
        Section {
            if viewModel.isSimplifiedMode {
                VStack(spacing: 12) {
                    miniWideBar(.sliderLeft)

                    HStack(alignment: .center, spacing: 14) {
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

                        Spacer(minLength: 8)

                        VStack(spacing: 8) {
                            miniWideActionButton(.buttonA)
                            miniWideActionButton(.buttonB)
                        }
                        .frame(maxWidth: 132)
                    }
                }
                .frame(maxWidth: 360)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
                .animation(AppleMotion.fluidSpring, value: viewModel.assignments)
            } else {
                VStack(spacing: 12) {
                    HStack(spacing: 6) {
                        miniSlotPill(.shoulderL1)
                        miniSlotPill(.sliderLeft)
                        miniSlotPill(.select)
                        miniSlotPill(.start)
                        miniSlotPill(.sliderRight)
                        miniSlotPill(.shoulderR1)
                    }

                    HStack(alignment: .center, spacing: 14) {
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
            }
        } header: {
            Text("Touchez un bouton pour le modifier")
        }
    }

    private var boardHardwareSection: some View {
        Section("Carte Arduino") {
            Picker(
                "Profil carte",
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

            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(viewModel.boardCapability.boardType.displayName)
                        .font(.subheadline.weight(.medium))
                    HStack(spacing: 4) {
                        Text("\(viewModel.boardCapability.availablePins.count)")
                            .monospacedDigit()
                            .contentTransition(.numericText())
                        Text("broches")
                        Text("•")
                        Text(viewModel.boardCapability.isAutoDetected ? "Auto" : "Manuel")
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }

                Spacer()

                Button {
                    triggerAdaptWithFeedback()
                } label: {
                    Text(didAdaptPinsFeedback ? "Adapté" : "Réadapter")
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background((didAdaptPinsFeedback ? Color.green : Color.accentColor).opacity(0.15))
                        .foregroundStyle(didAdaptPinsFeedback ? Color.green : Color.accentColor)
                        .clipShape(Capsule())
                }
                .buttonStyle(.borderless)
            }
            .animation(AppleMotion.fluidSpring, value: viewModel.boardCapability)
            .animation(AppleMotion.fluidSpring, value: didAdaptPinsFeedback)
        }
    }

    private var ps4ControllerSection: some View {
        Section("Manette PS4 Bluetooth") {
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

    private func miniWideBar(_ slot: GamepadSlot) -> some View {
        let config = viewModel.assignment(for: slot)
        let color = config.colorToken.color
        let shape = RoundedRectangle(cornerRadius: 10, style: .continuous)
        return Button {
            AppHaptics.selection()
            viewModel.selectedSlotForEditing = slot
        } label: {
            HStack {
                Text(config.label)
                    .font(.caption.weight(.semibold))
                Spacer()
                Text(config.summaryPinBadge)
                    .font(.caption2.weight(.bold))
            }
            .foregroundStyle(color)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity)
            .background(color.opacity(0.14))
            .overlay(
                shape.strokeBorder(color.opacity(0.45), lineWidth: 1)
            )
            .clipShape(shape)
        }
        .buttonStyle(.borderless)
    }

    private func miniWideActionButton(_ slot: GamepadSlot) -> some View {
        let config = viewModel.assignment(for: slot)
        let color = config.colorToken.color
        let shape = RoundedRectangle(cornerRadius: 12, style: .continuous)
        return Button {
            AppHaptics.selection()
            viewModel.selectedSlotForEditing = slot
        } label: {
            VStack(spacing: 2) {
                Text("\(slot.shortCode) • \(config.label)")
                    .font(.caption.weight(.bold))
                    .multilineTextAlignment(.center)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                    .frame(maxWidth: .infinity)
                Text(config.summaryPinBadge)
                    .font(.system(size: 9, weight: .semibold))
                    .tracking(0.3)
                    .opacity(0.8)
                    .frame(maxWidth: .infinity)
            }
            .foregroundStyle(color)
            .frame(maxWidth: .infinity, minHeight: 50)
            .padding(.horizontal, 8)
            .background(color.opacity(0.15))
            .overlay(
                shape.strokeBorder(color.opacity(0.5), lineWidth: 1.1)
            )
            .clipShape(shape)
        }
        .buttonStyle(.borderless)
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
                    .frame(maxWidth: .infinity)
                Text(config.label)
                    .font(.system(size: 8, weight: .medium))
                    .multilineTextAlignment(.center)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                    .frame(maxWidth: .infinity)
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
                    .frame(maxWidth: .infinity)
                Text(config.summaryPinBadge)
                    .font(.system(size: 8, weight: .semibold))
                    .multilineTextAlignment(.center)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity)
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
                    .frame(maxWidth: .infinity)
                Text(config.summaryPinBadge)
                    .font(.system(size: 8, weight: .semibold))
                    .multilineTextAlignment(.center)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity)
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
            }

            Spacer()

            Text("Modifier")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(Color(.tertiarySystemFill))
                .clipShape(Capsule())
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

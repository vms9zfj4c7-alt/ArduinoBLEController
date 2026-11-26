import SwiftUI
import CoreBluetooth

/// Écran de détection BLE avec radar temps réel calibré selon la distance estimée.
struct ScanView: View {
    @ObservedObject var viewModel: ScanViewModel

    private var isConnectingSelected: Bool {
        switch viewModel.connectionState {
        case .connecting, .discoveringServices:
            return true
        default:
            return false
        }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                VStack(spacing: 0) {
                    bluetoothStateBanner
                    activeConnectionBanner
                }
                .clipped()
                .animation(AppleMotion.fluidSpring, value: viewModel.bluetoothState)
                .animation(AppleMotion.fluidSpring, value: viewModel.connectionState)

                ScrollView {
                    VStack(spacing: 14) {
                        // Barre de filtre rapide + reconnexion 1 appui
                        VStack(spacing: 10) {
                            Picker("Filtre", selection: $viewModel.filterMode) {
                                ForEach(ScanViewModel.FilterMode.allCases) { mode in
                                    Text(mode.title).tag(mode)
                                }
                            }
                            .pickerStyle(.segmented)
                            .onChange(of: viewModel.filterMode) { _ in
                                AppHaptics.selection()
                            }

                            if case .disconnected = viewModel.connectionState,
                               let lastName = viewModel.lastConnectedDeviceName {
                                Button {
                                    AppHaptics.medium()
                                    viewModel.reconnectLastDevice()
                                } label: {
                                    HStack {
                                        Text("Reconnecter : \(lastName)")
                                            .font(.subheadline.weight(.semibold))
                                        Spacer()
                                        Text("Rapide")
                                            .font(.caption2.weight(.bold))
                                            .padding(.horizontal, 8)
                                            .padding(.vertical, 3)
                                            .background(Color.accentColor.opacity(0.14))
                                            .clipShape(Capsule())
                                    }
                                    .foregroundStyle(Color.accentColor)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 10)
                                    .appleGroupedCard(cornerRadius: 14)
                                }
                                .buttonStyle(TactileScaleButtonStyle(pressedScale: 0.97))
                            }
                        }

                        // Radar interactif selon la distance estimée
                        BLERadarView(
                            devices: viewModel.filteredDevices,
                            selectedDeviceID: viewModel.selectedDeviceID,
                            isScanning: viewModel.isScanning,
                            isConnecting: isConnectingSelected,
                            onSelectDevice: { device in
                                viewModel.selectDevice(device)
                            },
                            onConnectDevice: { device in
                                viewModel.connect(to: device)
                            },
                            onToggleScan: {
                                viewModel.toggleScan()
                            }
                        )
                        .equatable()

                        // Liste complémentaire triée par proximité
                        if !viewModel.filteredDevices.isEmpty {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Appareils à proximité (\(viewModel.filteredDevices.count))")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.secondary)
                                    .padding(.horizontal, 4)

                                VStack(spacing: 0) {
                                    ForEach(Array(viewModel.filteredDevices.enumerated()), id: \.element.id) { index, device in
                                        DeviceRowView(
                                            device: device,
                                            isSelected: device.id == viewModel.selectedDeviceID,
                                            isConnecting: isConnecting(to: device),
                                            onSelect: {
                                                AppHaptics.selection()
                                                withAnimation(AppleMotion.fluidSpring) {
                                                    viewModel.selectDevice(device)
                                                }
                                            },
                                            onConnect: {
                                                AppHaptics.medium()
                                                viewModel.connect(to: device)
                                            }
                                        )
                                        .equatable()

                                        if index < viewModel.filteredDevices.count - 1 {
                                            Divider()
                                                .padding(.leading, 68)
                                                .opacity(0.5)
                                        }
                                    }
                                }
                                .appleGroupedCard(cornerRadius: 18)
                            }
                            .animation(AppleMotion.fluidSpring, value: viewModel.filteredDevices)
                        } else if !viewModel.searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            VStack(spacing: 10) {
                                Text("Aucun résultat pour « \(viewModel.searchText) »")
                                    .font(.subheadline.weight(.semibold))
                                    .multilineTextAlignment(.center)
                                Button("Effacer la recherche") {
                                    AppHaptics.light()
                                    withAnimation(AppleMotion.fluidSpring) {
                                        viewModel.searchText = ""
                                    }
                                }
                                .buttonStyle(.bordered)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(20)
                            .appleGroupedCard(cornerRadius: 18)
                        }
                    }
                    .frame(maxWidth: 660)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .frame(maxWidth: .infinity)
                }
                .background(Color(.systemGroupedBackground).ignoresSafeArea())
                .scrollDismissesKeyboard(.interactively)
                .refreshable {
                    if !viewModel.isScanning {
                        AppHaptics.medium()
                        viewModel.toggleScan()
                    }
                }
            }
            .navigationTitle("Radar BLE")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $viewModel.searchText, prompt: "Rechercher un appareil...")
            .onAppear {
                viewModel.startAutoScanIfNeeded()
            }
            .onChange(of: viewModel.bluetoothState) { newState in
                if newState == .poweredOn {
                    viewModel.startAutoScanIfNeeded()
                }
            }
            .onDisappear {
                viewModel.stopScanIfActive()
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        AppHaptics.medium()
                        viewModel.toggleScan()
                    } label: {
                        Text(viewModel.isScanning ? "Stop" : "Scanner")
                            .font(.subheadline.weight(.semibold))
                    }
                    .tint(viewModel.isScanning ? .red : .accentColor)
                    .animation(AppleMotion.pressSpring, value: viewModel.isScanning)
                }
            }
            .alert(
                "Bluetooth",
                isPresented: Binding(
                    get: { viewModel.errorMessage != nil },
                    set: { if !$0 { viewModel.clearError() } }
                )
            ) {
                Button("OK", role: .cancel) {
                    viewModel.clearError()
                }
            } message: {
                Text(viewModel.errorMessage ?? "")
            }
        }
    }

    @ViewBuilder
    private var bluetoothStateBanner: some View {
        if viewModel.bluetoothState != .poweredOn && viewModel.bluetoothState != .unknown {
            Text(bluetoothStatusMessage)
                .font(.footnote.weight(.medium))
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(Color.orange)
                .transition(.move(edge: .top).combined(with: .opacity))
        }
    }

    @ViewBuilder
    private var activeConnectionBanner: some View {
        if viewModel.connectionState.isConnected || viewModel.connectionState.isBusy {
            if case .scanning = viewModel.connectionState {
                EmptyView()
            } else {
                HStack(spacing: 10) {
                    LivePulseBeacon(
                        color: viewModel.connectionState.isConnected ? Color.green : Color.orange,
                        isPulsing: viewModel.connectionState.isBusy,
                        dotSize: 9
                    )
                    Text(viewModel.connectionState.statusText)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                    Spacer()
                    Button("Déconnecter", role: .destructive) {
                        AppHaptics.soft()
                        viewModel.disconnect()
                    }
                    .font(.caption.weight(.semibold))
                    .buttonStyle(.bordered)
                    .controlSize(.mini)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(Color(.secondarySystemBackground))
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
    }

    private var bluetoothStatusMessage: String {
        switch viewModel.bluetoothState {
        case .poweredOff:
            return "Bluetooth désactivé. Activez-le dans les Réglages de l'iPhone."
        case .unauthorized:
            return "Accès Bluetooth refusé. Autorisez-le dans Réglages > Confidentialité."
        case .unsupported:
            return "BLE non supporté sur cet appareil (utilisez un iPhone réel)."
        default:
            return "Initialisation Bluetooth en cours..."
        }
    }

    private func isConnecting(to device: BLEDevice) -> Bool {
        switch viewModel.connectionState {
        case .connecting(let name), .discoveringServices(let name):
            return name == device.displayName
        default:
            return false
        }
    }
}

private struct DeviceRowView: View, Equatable {
    let device: BLEDevice
    let isSelected: Bool
    let isConnecting: Bool
    let onSelect: () -> Void
    let onConnect: () -> Void

    static func == (lhs: DeviceRowView, rhs: DeviceRowView) -> Bool {
        lhs.device == rhs.device
            && lhs.isSelected == rhs.isSelected
            && lhs.isConnecting == rhs.isConnecting
    }

    var body: some View {
        let badgeColor: Color = device.isLikelyArduino
            ? .accentColor
            : (device.hasResolvedName ? .blue : .secondary)
        let badgeCode = device.isLikelyArduino ? "ARD" : (device.hasResolvedName ? "NOM" : "BLE")

        return HStack(spacing: 12) {
            Button(action: onSelect) {
                HStack(spacing: 12) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 11, style: .continuous)
                            .fill(badgeColor.opacity(0.14))
                            .frame(width: 44, height: 44)
                        Text(badgeCode)
                            .font(.caption.weight(.black))
                            .tracking(0.3)
                            .foregroundStyle(badgeColor)
                    }

                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 6) {
                            Text(device.displayName)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.primary)
                                .lineLimit(1)
                            if device.isLikelyArduino {
                                Text("Arduino")
                                    .font(.caption2.weight(.bold))
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Color.accentColor.opacity(0.15))
                                    .foregroundStyle(Color.accentColor)
                                    .clipShape(Capsule())
                            }
                        }

                        HStack(spacing: 5) {
                            Text(device.formattedDistance)
                                .fontWeight(.semibold)
                                .foregroundStyle(Color.accentColor)
                                .contentTransition(.numericText())
                            Text("•")
                            Text(device.detectedModuleHint)
                                .lineLimit(1)
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }

                    Spacer(minLength: 4)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isConnecting {
                ProgressView()
                    .padding(.horizontal, 8)
            } else if device.isConnectable {
                Button("Connecter", action: onConnect)
                    .font(.caption.weight(.semibold))
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
            } else {
                Text("Balise")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 5)
                    .background(Color(.tertiarySystemFill))
                    .clipShape(Capsule())
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(isSelected ? Color.accentColor.opacity(0.08) : .clear)
        .animation(AppleMotion.fluidSpring, value: isSelected)
        .animation(AppleMotion.fluidSpring, value: isConnecting)
    }
}

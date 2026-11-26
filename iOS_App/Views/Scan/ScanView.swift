import SwiftUI
import CoreBluetooth

/// Écran de scan et de connexion aux périphériques Arduino Bluetooth Low Energy.
struct ScanView: View {
    @ObservedObject var viewModel: ScanViewModel

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

                List {
                    Section {
                        Toggle("Masquer les balises sans nom", isOn: $viewModel.hideUnnamedBeacons)
                            .onChange(of: viewModel.hideUnnamedBeacons) { _ in
                                AppHaptics.light()
                            }

                        Toggle("Afficher uniquement les cartes Arduino / BLE", isOn: $viewModel.showOnlyArduinoDevices)
                            .onChange(of: viewModel.showOnlyArduinoDevices) { _ in
                                AppHaptics.light()
                            }

                        if case .disconnected = viewModel.connectionState,
                           let lastName = viewModel.lastConnectedDeviceName {
                            Button {
                                AppHaptics.medium()
                                viewModel.reconnectLastDevice()
                            } label: {
                                HStack {
                                    Label("Reconnecter : \(lastName)", systemImage: "bolt.horizontal.circle.fill")
                                        .font(.subheadline.weight(.semibold))
                                    Spacer()
                                    Text("Rapide")
                                        .font(.caption2.weight(.bold))
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 3)
                                        .background(Color.accentColor.opacity(0.14))
                                        .clipShape(Capsule())
                                }
                            }
                        }
                    }

                    Section {
                        if viewModel.filteredDevices.isEmpty {
                            emptyDevicesView
                        } else {
                            ForEach(viewModel.filteredDevices) { device in
                                DeviceRowView(
                                    device: device,
                                    isConnecting: isConnecting(to: device),
                                    onConnect: {
                                        AppHaptics.selection()
                                        viewModel.connect(to: device)
                                    }
                                )
                                .equatable()
                            }
                        }
                    } header: {
                        HStack {
                            HStack(spacing: 3) {
                                Text("Périphériques détectés (")
                                Text("\(viewModel.filteredDevices.count)")
                                    .monospacedDigit()
                                    .contentTransition(.numericText())
                                Text(")")
                            }
                            Spacer()
                            if viewModel.isScanning {
                                ProgressView()
                                    .controlSize(.small)
                                    .transition(.opacity)
                            }
                        }
                    }
                }
                .listStyle(.insetGrouped)
                .scrollDismissesKeyboard(.interactively)
                .animation(AppleMotion.fluidSpring, value: viewModel.filteredDevices)
                .searchable(text: $viewModel.searchText, prompt: "Rechercher un appareil...")
                .refreshable {
                    if !viewModel.isScanning {
                        AppHaptics.medium()
                        viewModel.toggleScan()
                    }
                }
            }
            .navigationTitle("Scanner BLE")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        AppHaptics.medium()
                        viewModel.toggleScan()
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: viewModel.isScanning ? "stop.circle.fill" : "antenna.radiowaves.left.and.right")
                            Text(viewModel.isScanning ? "Stop" : "Scanner")
                        }
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
            HStack(spacing: 10) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.white)
                Text(bluetoothStatusMessage)
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(.white)
                Spacer()
            }
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

    private var emptyDevicesView: some View {
        let hasQuery = !viewModel.searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty

        return VStack(spacing: 14) {
            RadarScanBadge(isScanning: viewModel.isScanning)

            if hasQuery {
                Text("Aucun résultat pour « \(viewModel.searchText) »")
                    .font(.headline)
                    .multilineTextAlignment(.center)
                Button("Effacer la recherche") {
                    AppHaptics.light()
                    withAnimation(AppleMotion.fluidSpring) {
                        viewModel.searchText = ""
                    }
                }
                .buttonStyle(.bordered)
            } else {
                Text(viewModel.isScanning ? "Recherche d'appareils Arduino BLE..." : "Aucun appareil détecté")
                    .font(.headline)
                Text("Vérifiez que la carte Arduino est alimentée et que le sketch BLE est téléversé, puis appuyez sur Scanner.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                if !viewModel.isScanning {
                    Button {
                        AppHaptics.medium()
                        viewModel.toggleScan()
                    } label: {
                        Label("Lancer le scan", systemImage: "antenna.radiowaves.left.and.right")
                    }
                    .buttonStyle(.borderedProminent)
                    .padding(.top, 2)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 28)
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

/// Illustration radar iOS pour l'état vide du scanner BLE.
private struct RadarScanBadge: View {
    let isScanning: Bool

    var body: some View {
        ZStack {
            if isScanning {
                RadarWaveRing(delay: 0.0)
                RadarWaveRing(delay: 0.85)
            }

            Circle()
                .fill(isScanning ? Color.accentColor.opacity(0.14) : Color.secondary.opacity(0.10))
                .frame(width: 68, height: 68)

            Image(systemName: isScanning ? "dot.radiowaves.left.and.right" : "antenna.radiowaves.left.and.right")
                .font(.system(size: 30, weight: .medium))
                .foregroundStyle(isScanning ? Color.accentColor : Color.secondary)
        }
        .frame(width: 112, height: 92)
        .animation(AppleMotion.fluidSpring, value: isScanning)
    }
}

private struct RadarWaveRing: View {
    let delay: Double
    @State private var expanded = false

    var body: some View {
        Circle()
            .stroke(Color.accentColor.opacity(expanded ? 0.0 : 0.45), lineWidth: 1.8)
            .frame(width: 68, height: 68)
            .scaleEffect(expanded ? 1.75 : 1.0)
            .onAppear {
                expanded = false
                withAnimation(.easeOut(duration: 1.7).repeatForever(autoreverses: false).delay(delay)) {
                    expanded = true
                }
            }
    }
}

private struct DeviceRowView: View, Equatable {
    let device: BLEDevice
    let isConnecting: Bool
    let onConnect: () -> Void

    static func == (lhs: DeviceRowView, rhs: DeviceRowView) -> Bool {
        lhs.device == rhs.device && lhs.isConnecting == rhs.isConnecting
    }

    var body: some View {
        Button(action: onConnect) {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .fill(device.isLikelyArduino ? Color.accentColor.opacity(0.15) : Color.secondary.opacity(0.12))
                        .frame(width: 44, height: 44)
                    Image(systemName: device.isLikelyArduino ? "cpu.fill" : "wave.3.right")
                        .font(.title3)
                        .foregroundStyle(device.isLikelyArduino ? Color.accentColor : Color.secondary)
                }

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text(device.displayName)
                            .font(.body.weight(.semibold))
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

                    Text(device.detectedModuleHint)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer()

                if isConnecting {
                    ProgressView()
                        .transition(.scale(scale: 0.8).combined(with: .opacity))
                } else {
                    VStack(alignment: .trailing, spacing: 4) {
                        SignalBarsView(bars: device.signalBars)
                        Text("\(device.rssi) dBm")
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(.secondary)
                            .contentTransition(.numericText())
                    }
                    .transition(.opacity)
                }
            }
            .padding(.vertical, 4)
            .contentShape(Rectangle())
        }
        .animation(AppleMotion.fluidSpring, value: isConnecting)
    }
}

private struct SignalBarsView: View {
    let bars: Int

    var body: some View {
        HStack(alignment: .bottom, spacing: 2) {
            ForEach(1...4, id: \.self) { index in
                RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                    .fill(index <= bars ? barColor : Color.secondary.opacity(0.25))
                    .frame(width: 4, height: CGFloat(index * 4 + 2))
            }
        }
        .animation(.easeInOut(duration: 0.24), value: bars)
    }

    private var barColor: Color {
        switch bars {
        case 4, 3: return .green
        case 2: return .orange
        default: return .red
        }
    }
}

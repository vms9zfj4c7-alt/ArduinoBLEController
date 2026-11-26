import SwiftUI
import CoreBluetooth

/// Écran de scan et de connexion aux périphériques Arduino Bluetooth Low Energy.
struct ScanView: View {
    @ObservedObject var viewModel: ScanViewModel

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                bluetoothStateBanner
                activeConnectionBanner

                List {
                    Section {
                        Toggle("Masquer les balises sans nom", isOn: $viewModel.hideUnnamedBeacons)
                        Toggle("Afficher uniquement les cartes Arduino / BLE", isOn: $viewModel.showOnlyArduinoDevices)

                        if case .disconnected = viewModel.connectionState,
                           let lastName = viewModel.lastConnectedDeviceName {
                            Button {
                                viewModel.reconnectLastDevice()
                            } label: {
                                HStack {
                                    Label("Reconnecter : \(lastName)", systemImage: "bolt.horizontal.circle.fill")
                                        .font(.subheadline.weight(.semibold))
                                    Spacer()
                                    Text("Rapide")
                                        .font(.caption2.weight(.bold))
                                        .padding(.horizontal, 7)
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
                                    onConnect: { viewModel.connect(to: device) }
                                )
                            }
                        }
                    } header: {
                        HStack {
                            Text("Périphériques détectés (\(viewModel.filteredDevices.count))")
                            Spacer()
                            if viewModel.isScanning {
                                ProgressView()
                                    .controlSize(.small)
                            }
                        }
                    }
                }
                .listStyle(.insetGrouped)
                .searchable(text: $viewModel.searchText, prompt: "Rechercher un appareil...")
                .refreshable {
                    if !viewModel.isScanning {
                        viewModel.toggleScan()
                    }
                }
            }
            .navigationTitle("Scanner BLE")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(action: viewModel.toggleScan) {
                        HStack(spacing: 6) {
                            Image(systemName: viewModel.isScanning ? "stop.circle.fill" : "antenna.radiowaves.left.and.right")
                            Text(viewModel.isScanning ? "Stop" : "Scanner")
                        }
                        .font(.subheadline.weight(.semibold))
                    }
                    .tint(viewModel.isScanning ? .red : .accentColor)
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
        }
    }

    @ViewBuilder
    private var activeConnectionBanner: some View {
        if viewModel.connectionState.isConnected || viewModel.connectionState.isBusy {
            if case .scanning = viewModel.connectionState {
                EmptyView()
            } else {
                HStack(spacing: 10) {
                    Circle()
                        .fill(viewModel.connectionState.isConnected ? Color.green : Color.orange)
                        .frame(width: 10, height: 10)
                    Text(viewModel.connectionState.statusText)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                    Spacer()
                    Button("Déconnecter", role: .destructive) {
                        viewModel.disconnect()
                    }
                    .font(.caption.weight(.semibold))
                    .buttonStyle(.bordered)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(Color(.secondarySystemBackground))
            }
        }
    }

    private var emptyDevicesView: some View {
        VStack(spacing: 12) {
            Image(systemName: viewModel.isScanning ? "dot.radiowaves.left.and.right" : "antenna.radiowaves.left.and.right")
                .font(.system(size: 36))
                .foregroundStyle(.secondary)
            Text(viewModel.isScanning ? "Recherche d'appareils Arduino BLE..." : "Aucun appareil détecté")
                .font(.headline)
            Text("Vérifiez que la carte Arduino est alimentée et que le sketch BLE est téléversé, puis appuyez sur Scanner.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            if !viewModel.isScanning {
                Button("Lancer le scan") {
                    viewModel.toggleScan()
                }
                .buttonStyle(.borderedProminent)
                .padding(.top, 4)
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

private struct DeviceRowView: View {
    let device: BLEDevice
    let isConnecting: Bool
    let onConnect: () -> Void

    var body: some View {
        Button(action: onConnect) {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10)
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
                }

                Spacer()

                if isConnecting {
                    ProgressView()
                } else {
                    VStack(alignment: .trailing, spacing: 4) {
                        SignalBarsView(bars: device.signalBars)
                        Text("\(device.rssi) dBm")
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(.vertical, 4)
        }
        .buttonStyle(.plain)
    }
}

private struct SignalBarsView: View {
    let bars: Int

    var body: some View {
        HStack(alignment: .bottom, spacing: 2) {
            ForEach(1...4, id: \.self) { index in
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(index <= bars ? barColor : Color.secondary.opacity(0.25))
                    .frame(width: 4, height: CGFloat(index * 4 + 2))
            }
        }
    }

    private var barColor: Color {
        switch bars {
        case 4, 3: return .green
        case 2: return .orange
        default: return .red
        }
    }
}

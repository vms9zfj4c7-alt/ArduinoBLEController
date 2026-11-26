import SwiftUI
import CoreBluetooth

/// Écran de détection BLE (radar temps réel) et de connexion Wi-Fi TCP locale.
struct ScanView: View {
    @ObservedObject var viewModel: ScanViewModel
    @State private var showCompatibilityHelp = false

    private var isConnectingSelected: Bool {
        switch viewModel.connectionState {
        case .connecting, .discoveringServices:
            return true
        default:
            return false
        }
    }

    private var filteredWiFiDevices: [WiFiDiscoveredDevice] {
        let query = viewModel.searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return viewModel.wifiDevices }
        return viewModel.wifiDevices.filter {
            $0.name.localizedCaseInsensitiveContains(query)
                || $0.inferredBoardType.displayName.localizedCaseInsensitiveContains(query)
        }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                VStack(spacing: 0) {
                    if viewModel.transportTab == .ble {
                        bluetoothStateBanner
                    }
                    activeConnectionBanner
                }
                .clipped()
                .animation(AppleMotion.fluidSpring, value: viewModel.bluetoothState)
                .animation(AppleMotion.fluidSpring, value: viewModel.connectionState)
                .animation(AppleMotion.fluidSpring, value: viewModel.transportTab)

                ScrollView {
                    VStack(spacing: 14) {
                        Picker("Mode de connexion", selection: $viewModel.transportTab) {
                            ForEach(ConnectionTransport.allCases) { transport in
                                Text(transport.title).tag(transport)
                            }
                        }
                        .pickerStyle(.segmented)
                        .onChange(of: viewModel.transportTab) { _ in
                            AppHaptics.selection()
                        }

                        if viewModel.transportTab == .wifi {
                            wifiConnectionContent
                        } else {
                            bleConnectionContent
                        }

                        Button {
                            AppHaptics.selection()
                            showCompatibilityHelp = true
                        } label: {
                            Text(
                                viewModel.transportTab == .wifi
                                    ? "Configuration Wi-Fi Arduino (Mode AP / Routeur)"
                                    : "Module introuvable ? Compatibilité iPhone (BLE vs Bluetooth 3.0)"
                            )
                            .font(.caption.weight(.medium))
                            .multilineTextAlignment(.center)
                            .foregroundStyle(.secondary)
                            .padding(.vertical, 8)
                            .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.plain)
                    }
                    .frame(maxWidth: 660)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .frame(maxWidth: .infinity)
                }
                .background(Color(.systemGroupedBackground).ignoresSafeArea())
                .scrollDismissesKeyboard(.interactively)
                .refreshable {
                    AppHaptics.medium()
                    if viewModel.transportTab == .wifi {
                        viewModel.startWiFiDiscovery()
                    } else if !viewModel.isScanning {
                        viewModel.toggleScan()
                    }
                }
            }
            .navigationTitle(viewModel.transportTab == .wifi ? "Connexion Wi-Fi" : "Radar BLE")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(
                text: $viewModel.searchText,
                prompt: viewModel.transportTab == .wifi ? "Filtrer les cartes Wi-Fi..." : "Rechercher un appareil..."
            )
            .onAppear {
                viewModel.startAutoScanIfNeeded()
            }
            .onChange(of: viewModel.bluetoothState) { newState in
                if newState == .poweredOn && viewModel.transportTab == .ble {
                    viewModel.startAutoScanIfNeeded()
                }
            }
            .onDisappear {
                viewModel.stopScanIfActive()
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    if viewModel.transportTab == .wifi {
                        Button {
                            AppHaptics.medium()
                            viewModel.toggleWiFiDiscovery()
                        } label: {
                            Text(viewModel.isWiFiScanning ? "Stop" : "Chercher")
                                .font(.subheadline.weight(.semibold))
                        }
                        .tint(viewModel.isWiFiScanning ? .red : .accentColor)
                        .animation(AppleMotion.pressSpring, value: viewModel.isWiFiScanning)
                    } else {
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
            }
            .alert(
                viewModel.transportTab == .wifi ? "Wi-Fi" : "Bluetooth",
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
            .sheet(isPresented: $showCompatibilityHelp) {
                NavigationStack {
                    List {
                        Section("Contrôle Wi-Fi (ESP32, Uno R4 WiFi, Nano 33 IoT)") {
                            Text("Dans le sketch Arduino (.ino), décommentez #define CONTROL_MODE_WIFI. En mode Point d'Accès (AP), connectez l'iPhone au réseau « ArduinoBLE-WiFi » (mot de passe 12345678) puis connectez-vous sur 192.168.4.1 port 8888. Sur le même routeur Wi-Fi, la carte apparaît automatiquement ci-dessous via Bonjour.")
                                .font(.footnote)
                        }

                        Section("Pourquoi certains modules Bluetooth n'apparaissent pas ?") {
                            Text("Apple autorise uniquement les modules Bluetooth Low Energy (BLE 4.0 / 5.0) sur iPhone. Les modules Bluetooth Classique 2.0 / 3.0 uniquement (ex: Serial Bluetooth v3.01, HC-05, HC-06, SPP-C) sont bloqués par iOS et invisibles dans CoreBluetooth.")
                                .font(.footnote)
                        }

                        Section("Modules Bluetooth compatibles iPhone") {
                            Text("HM-10, AT-09, HC-08, MLT-BT05, JDY-23 / JDY-33 (mode BLE), DX-BT24, Arduino Uno R4 WiFi, Nano 33 BLE et ESP32.")
                                .font(.footnote)
                        }
                    }
                    .navigationTitle("Compatibilité & Réseau")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Fermer") {
                                showCompatibilityHelp = false
                            }
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var bleConnectionContent: some View {
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
                   let lastName = viewModel.lastBLEDeviceName {
                    Button {
                        AppHaptics.medium()
                        viewModel.reconnectLastDevice()
                    } label: {
                        HStack {
                            Text("Reconnecter : \(lastName)")
                                .font(.subheadline.weight(.semibold))
                            Spacer()
                            Text("BLE")
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
    }

    @ViewBuilder
    private var wifiConnectionContent: some View {
        VStack(spacing: 14) {
            if case .disconnected = viewModel.connectionState,
               let lastWiFi = viewModel.lastWiFiDeviceName {
                Button {
                    AppHaptics.medium()
                    viewModel.reconnectLastWiFi()
                } label: {
                    HStack {
                        Text("Reconnecter : \(lastWiFi)")
                            .font(.subheadline.weight(.semibold))
                        Spacer()
                        Text("Wi-Fi")
                            .font(.caption2.weight(.bold))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(Color.teal.opacity(0.16))
                            .clipShape(Capsule())
                    }
                    .foregroundStyle(Color.teal)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .appleGroupedCard(cornerRadius: 14)
                }
                .buttonStyle(TactileScaleButtonStyle(pressedScale: 0.97))
            }

            // Connexion TCP directe par IP / Port ou Point d'Accès Arduino
            VStack(spacing: 12) {
                Text("Connexion Wi-Fi directe (TCP)")
                    .font(.subheadline.weight(.semibold))
                    .multilineTextAlignment(.center)

                HStack(spacing: 10) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Adresse IP")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.secondary)
                        TextField("192.168.4.1", text: $viewModel.wifiHost)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .keyboardType(.numbersAndPunctuation)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 9)
                            .background(Color(.tertiarySystemFill))
                            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Port")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.secondary)
                        TextField("8888", text: $viewModel.wifiPortText)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 9)
                            .background(Color(.tertiarySystemFill))
                            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    }
                    .frame(width: 82)
                }

                HStack(spacing: 10) {
                    Button {
                        AppHaptics.selection()
                        withAnimation(AppleMotion.fluidSpring) {
                            viewModel.applyWiFiAPPreset()
                        }
                    } label: {
                        Text("Mode AP 192.168.4.1")
                            .font(.caption.weight(.semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .background(Color(.tertiarySystemFill))
                            .foregroundStyle(.primary)
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                    .buttonStyle(TactileScaleButtonStyle(pressedScale: 0.97))

                    Button {
                        AppHaptics.medium()
                        viewModel.connectWiFiManual()
                    } label: {
                        HStack(spacing: 6) {
                            if isConnectingSelected && viewModel.activeTransport == .wifi {
                                ProgressView()
                                    .tint(.white)
                            }
                            Text(
                                isConnectingSelected && viewModel.activeTransport == .wifi
                                    ? "Connexion..."
                                    : "Connecter"
                            )
                            .font(.subheadline.weight(.semibold))
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(Color.accentColor)
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                    .buttonStyle(TactileScaleButtonStyle(pressedScale: 0.97))
                    .disabled(isConnectingSelected)
                }
            }
            .padding(14)
            .appleGroupedCard(cornerRadius: 18)

            // Découverte automatique Bonjour (_arduinowifi._tcp)
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Text("Cartes Wi-Fi détectées (\(filteredWiFiDevices.count))")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    LivePulseBeacon(
                        color: viewModel.isWiFiScanning ? .teal : .secondary,
                        isPulsing: viewModel.isWiFiScanning,
                        dotSize: 7
                    )
                    Spacer()
                }
                .padding(.horizontal, 4)

                if filteredWiFiDevices.isEmpty {
                    VStack(spacing: 10) {
                        Text("Aucune carte Wi-Fi détectée sur le réseau local")
                            .font(.subheadline.weight(.semibold))
                            .multilineTextAlignment(.center)
                        Text("Utilisez l'adresse IP ci-dessus (192.168.4.1 en point d'accès ArduinoBLE-WiFi) ou activez #define CONTROL_MODE_WIFI sur le même routeur.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                        Button(viewModel.isWiFiScanning ? "Recherche en cours..." : "Actualiser") {
                            AppHaptics.light()
                            viewModel.startWiFiDiscovery()
                        }
                        .buttonStyle(.bordered)
                        .disabled(viewModel.isWiFiScanning)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(18)
                    .appleGroupedCard(cornerRadius: 18)
                } else {
                    VStack(spacing: 0) {
                        ForEach(Array(filteredWiFiDevices.enumerated()), id: \.element.id) { index, device in
                            WiFiDeviceRowView(
                                device: device,
                                isConnecting: isConnectingWiFi(to: device),
                                onConnect: {
                                    AppHaptics.medium()
                                    viewModel.connectWiFi(device: device)
                                }
                            )

                            if index < filteredWiFiDevices.count - 1 {
                                Divider()
                                    .padding(.leading, 68)
                                    .opacity(0.5)
                            }
                        }
                    }
                    .appleGroupedCard(cornerRadius: 18)
                }
            }
            .animation(AppleMotion.fluidSpring, value: filteredWiFiDevices)
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

    private func isConnectingWiFi(to device: WiFiDiscoveredDevice) -> Bool {
        switch viewModel.connectionState {
        case .connecting(let name):
            return name == device.name
        default:
            return false
        }
    }
}

private struct WiFiDeviceRowView: View {
    let device: WiFiDiscoveredDevice
    let isConnecting: Bool
    let onConnect: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .fill(Color.teal.opacity(0.16))
                    .frame(width: 44, height: 44)
                Text("WIF")
                    .font(.caption.weight(.black))
                    .tracking(0.3)
                    .foregroundStyle(Color.teal)
            }

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(device.name)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    Text("Wi-Fi")
                        .font(.caption2.weight(.bold))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.teal.opacity(0.16))
                        .foregroundStyle(Color.teal)
                        .clipShape(Capsule())
                }

                Text("Bonjour mDNS • \(device.inferredBoardType.displayName)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 4)

            if isConnecting {
                ProgressView()
                    .padding(.horizontal, 8)
            } else {
                Button("Connecter", action: onConnect)
                    .font(.caption.weight(.semibold))
                    .buttonStyle(.borderedProminent)
                    .tint(.teal)
                    .controlSize(.small)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .animation(AppleMotion.fluidSpring, value: isConnecting)
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

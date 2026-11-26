import SwiftUI

/// Radar interactif temps réel positionnant chaque appareil BLE selon sa distance réelle estimée.
struct BLERadarView: View {
    let devices: [BLEDevice]
    let selectedDeviceID: UUID?
    let isScanning: Bool
    let isConnecting: Bool
    let onSelectDevice: (BLEDevice) -> Void
    let onConnectDevice: (BLEDevice) -> Void
    let onToggleScan: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let radarRingsMeters: [Double] = [1.0, 3.0, 8.0, 15.0]
    private static let ringLabels: [String] = ["1 m", "3 m", "8 m", "15 m"]

    private var selectedDevice: BLEDevice? {
        devices.first { $0.id == selectedDeviceID }
    }

    var body: some View {
        VStack(spacing: 12) {
            // En-tête du radar
            HStack(spacing: 8) {
                LivePulseBeacon(
                    color: isScanning ? .cyan : .secondary,
                    isPulsing: isScanning,
                    dotSize: 8
                )

                Text("Radar BLE")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(.white)

                Text("\(devices.count)")
                    .font(.caption2.monospacedDigit().weight(.bold))
                    .contentTransition(.numericText())
                    .foregroundStyle(.cyan)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2)
                    .background(Color.cyan.opacity(0.18))
                    .clipShape(Capsule())

                Spacer()

                Button {
                    AppHaptics.medium()
                    onToggleScan()
                } label: {
                    Text(isScanning ? "Pause" : "Scanner")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(isScanning ? Color.white : Color.black)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 5)
                        .background(
                            Capsule()
                                .fill(isScanning ? Color.red.opacity(0.85) : Color.cyan)
                        )
                }
                .buttonStyle(TactileScaleButtonStyle(pressedScale: 0.92))
            }

            // Disque radar avec anneaux calibrés en mètres et balayage temps réel
            GeometryReader { geo in
                let diameter = min(geo.size.width, geo.size.height)
                let maxR = diameter * 0.5
                let center = CGPoint(x: geo.size.width * 0.5, y: geo.size.height * 0.5)
                let blips = Self.layoutBlips(devices: devices, center: center, maxRadius: maxR)

                ZStack {
                    // Fond radial du radar
                    Circle()
                        .fill(
                            RadialGradient(
                                colors: [
                                    Color(red: 0.05, green: 0.24, blue: 0.31),
                                    Color(red: 0.03, green: 0.13, blue: 0.20),
                                    Color(red: 0.02, green: 0.08, blue: 0.13)
                                ],
                                center: .center,
                                startRadius: 6,
                                endRadius: maxR
                            )
                        )
                        .frame(width: diameter, height: diameter)

                    // Faisceau rotatif fluide (60/120 Hz quand actif, désactivé si Réduire les animations)
                    if isScanning && !reduceMotion {
                        TimelineView(.animation(minimumInterval: 1.0 / 60.0, paused: !isScanning || reduceMotion)) { context in
                            let angle = Self.sweepAngleDegrees(for: context.date)
                            Circle()
                                .fill(
                                    AngularGradient(
                                        stops: [
                                            .init(color: .clear, location: 0.0),
                                            .init(color: .clear, location: 0.78),
                                            .init(color: Color.cyan.opacity(0.10), location: 0.90),
                                            .init(color: Color.cyan.opacity(0.32), location: 0.995),
                                            .init(color: .clear, location: 1.0)
                                        ],
                                        center: .center,
                                        angle: .degrees(angle)
                                    )
                                )
                                .frame(width: diameter, height: diameter)
                                .allowsHitTesting(false)
                        }
                    }

                    // Axes orthogonaux
                    Rectangle()
                        .fill(Color.cyan.opacity(0.12))
                        .frame(width: 1, height: diameter)
                        .allowsHitTesting(false)
                    Rectangle()
                        .fill(Color.cyan.opacity(0.12))
                        .frame(width: diameter, height: 1)
                        .allowsHitTesting(false)

                    // Anneaux concentriques calibrés en mètres
                    ForEach(Array(Self.radarRingsMeters.enumerated()), id: \.offset) { idx, meters in
                        let ringR = Self.normalizedRadius(forMeters: meters) * maxR
                        Circle()
                            .strokeBorder(
                                Color.cyan.opacity(idx == Self.radarRingsMeters.count - 1 ? 0.34 : 0.20),
                                lineWidth: 1
                            )
                            .frame(width: ringR * 2, height: ringR * 2)
                            .allowsHitTesting(false)

                        Text(Self.ringLabels[idx])
                            .font(.system(size: 9, weight: .semibold, design: .rounded))
                            .tracking(0.3)
                            .foregroundStyle(Color.cyan.opacity(0.78))
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(Color(red: 0.02, green: 0.10, blue: 0.16).opacity(0.85))
                            .clipShape(Capsule())
                            .position(x: center.x, y: center.y - ringR)
                            .allowsHitTesting(false)
                    }

                    // Bordure extérieure
                    Circle()
                        .strokeBorder(Color.cyan.opacity(0.32), lineWidth: 1.4)
                        .frame(width: diameter, height: diameter)
                        .allowsHitTesting(false)

                    // Point central (iPhone)
                    ZStack {
                        Circle()
                            .fill(Color.white.opacity(0.18))
                            .frame(width: 18, height: 18)
                        Circle()
                            .fill(Color.white)
                            .frame(width: 8, height: 8)
                    }
                    .position(center)
                    .allowsHitTesting(false)

                    // Points cliquables représentant chaque appareil BLE détecté
                    ForEach(blips) { blip in
                        let isSelected = (blip.device.id == selectedDeviceID)
                        RadarBlipView(
                            blip: blip,
                            isSelected: isSelected,
                            showLabel: isSelected || (blip.device.isLikelyArduino && blips.count <= 8),
                            containerSize: geo.size,
                            onTap: {
                                if isSelected {
                                    AppHaptics.medium()
                                    onConnectDevice(blip.device)
                                } else {
                                    AppHaptics.selection()
                                    withAnimation(AppleMotion.fluidSpring) {
                                        onSelectDevice(blip.device)
                                    }
                                }
                            }
                        )
                        .zIndex(isSelected ? 10 : (blip.device.isLikelyArduino ? 2 : 0))
                    }
                }
                .frame(width: geo.size.width, height: geo.size.height)
                .animation(
                    AppleMotion.adaptive(AppleMotion.fluidSpring, reduceMotion: reduceMotion),
                    value: blips.map(\.positionSignature)
                )
            }
            .frame(height: 248)

            // Fiche directe sous le radar pour connecter l'appareil choisi en 1 appui
            Group {
                if let device = selectedDevice {
                    HStack(spacing: 12) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(device.isLikelyArduino ? Color.cyan.opacity(0.22) : Color.white.opacity(0.12))
                                .frame(width: 40, height: 40)
                            Text(device.isLikelyArduino ? "ARD" : "BLE")
                                .font(.caption2.weight(.black))
                                .foregroundStyle(device.isLikelyArduino ? Color.cyan : Color.white.opacity(0.85))
                        }

                        VStack(alignment: .leading, spacing: 2) {
                            Text(device.displayName)
                                .font(.subheadline.weight(.bold))
                                .foregroundStyle(.white)
                                .lineLimit(1)

                            HStack(spacing: 5) {
                                Text(device.formattedDistance)
                                    .fontWeight(.bold)
                                    .foregroundStyle(.cyan)
                                    .contentTransition(.numericText())
                                Text("•")
                                Text(device.proximityZoneText)
                                Text("•")
                                Text("\(device.rssi) dBm")
                                    .monospacedDigit()
                            }
                            .font(.caption2)
                            .foregroundStyle(.white.opacity(0.75))
                            .lineLimit(1)
                        }

                        Spacer(minLength: 4)

                        Button {
                            AppHaptics.medium()
                            onConnectDevice(device)
                        } label: {
                            Group {
                                if isConnecting {
                                    ProgressView()
                                        .tint(.black)
                                } else {
                                    Text("Connecter")
                                        .font(.caption.weight(.bold))
                                }
                            }
                            .foregroundStyle(.black)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background(Capsule().fill(Color.cyan))
                        }
                        .buttonStyle(TactileScaleButtonStyle(pressedScale: 0.92))
                        .disabled(isConnecting)
                    }
                    .padding(10)
                    .background(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(Color.white.opacity(0.08))
                            .overlay(
                                RoundedRectangle(cornerRadius: 16, style: .continuous)
                                    .strokeBorder(Color.cyan.opacity(0.35), lineWidth: 1)
                            )
                    )
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                } else {
                    Text(
                        devices.isEmpty
                            ? (isScanning ? "Détection des appareils Bluetooth autour de vous..." : "Appuyez sur Scanner pour repérer les appareils")
                            : "Touchez un point sur le radar pour choisir un appareil"
                    )
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.white.opacity(0.72))
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .transition(.opacity)
                }
            }
            .animation(AppleMotion.fluidSpring, value: selectedDevice?.id)
            .animation(AppleMotion.fluidSpring, value: isConnecting)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color(red: 0.04, green: 0.14, blue: 0.22),
                            Color(red: 0.03, green: 0.09, blue: 0.15)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .strokeBorder(Color.cyan.opacity(0.24), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.18), radius: 12, y: 4)
    }

    // MARK: - Géométrie du radar

    private static func sweepAngleDegrees(for date: Date) -> Double {
        let cycle = 3.2
        let phase = date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: cycle) / cycle
        return phase * 360.0
    }

    /// Mapping logarithmique continu [0.2 m .. 25 m] aligné sur les anneaux 1m / 3m / 8m / 15m.
    private static func normalizedRadius(forMeters meters: Double) -> CGFloat {
        let clamped = min(max(meters, 0.2), 25.0)
        let norm = log10(clamped / 0.2) / log10(25.0 / 0.2)
        return CGFloat(0.14 + norm * 0.78)
    }

    private struct PositionedBlip: Identifiable {
        let device: BLEDevice
        let point: CGPoint

        var id: UUID { device.id }

        var positionSignature: String {
            "\(device.id.uuidString)-\(Int(point.x.rounded()))-\(Int(point.y.rounded()))"
        }
    }

    private static func layoutBlips(
        devices: [BLEDevice],
        center: CGPoint,
        maxRadius: CGFloat
    ) -> [PositionedBlip] {
        guard maxRadius > 20 else { return [] }
        let limited = Array(devices.prefix(24)).sorted { $0.id.uuidString < $1.id.uuidString }
        var placed: [PositionedBlip] = []
        placed.reserveCapacity(limited.count)

        let minSeparation: CGFloat = 28.0
        let angleOffsets: [Double] = [
            0.0, 0.42, -0.42, 0.84, -0.84, 1.26, -1.26, 1.68, -1.68, 2.1, -2.1, 2.52, -2.52
        ]

        for device in limited {
            let baseR = normalizedRadius(forMeters: device.estimatedDistanceMeters) * maxRadius
            let baseAngle = device.baseRadarAngle

            var chosenPoint = CGPoint(
                x: center.x + baseR * CGFloat(cos(baseAngle)),
                y: center.y + baseR * CGFloat(sin(baseAngle))
            )

            outer: for rShift in [CGFloat(0), CGFloat(10), CGFloat(-10), CGFloat(18)] {
                let candidateR = min(max(baseR + rShift, maxRadius * 0.14), maxRadius * 0.93)
                for offset in angleOffsets {
                    let candidateAngle = baseAngle + offset
                    let candidate = CGPoint(
                        x: center.x + candidateR * CGFloat(cos(candidateAngle)),
                        y: center.y + candidateR * CGFloat(sin(candidateAngle))
                    )
                    let overlaps = placed.contains { existing in
                        hypot(existing.point.x - candidate.x, existing.point.y - candidate.y) < minSeparation
                    }
                    if !overlaps {
                        chosenPoint = candidate
                        break outer
                    }
                }
            }

            placed.append(PositionedBlip(device: device, point: chosenPoint))
        }

        return placed
    }

    private struct RadarBlipView: View {
        let blip: PositionedBlip
        let isSelected: Bool
        let showLabel: Bool
        let containerSize: CGSize
        let onTap: () -> Void

        var body: some View {
            let isArduino = blip.device.isLikelyArduino
            let dotColor: Color = isArduino ? .cyan : Color(red: 0.62, green: 0.78, blue: 0.86)
            let dotSize: CGFloat = isArduino ? 14 : 10
            let showBelow = blip.point.y < 38
            let clampedLabelX = min(max(blip.point.x, 54), max(54, containerSize.width - 54))
            let labelY = showBelow ? (blip.point.y + 22) : (blip.point.y - 22)

            ZStack {
                if showLabel {
                    Text(isSelected ? "\(blip.device.displayName) • \(blip.device.formattedDistance)" : blip.device.formattedDistance)
                        .font(.system(size: isSelected ? 10 : 9, weight: isSelected ? .bold : .semibold))
                        .lineLimit(1)
                        .foregroundStyle(isSelected ? .black : .white)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(
                            Capsule()
                                .fill(isSelected ? Color.cyan : Color.black.opacity(0.68))
                        )
                        .position(x: clampedLabelX, y: labelY)
                        .allowsHitTesting(false)
                }

                Button(action: onTap) {
                    ZStack {
                        if isSelected {
                            Circle()
                                .strokeBorder(Color.white, lineWidth: 2)
                                .frame(width: dotSize + 14, height: dotSize + 14)
                        }

                        if isArduino {
                            Circle()
                                .fill(dotColor.opacity(0.28))
                                .frame(width: dotSize + 10, height: dotSize + 10)
                        }

                        Circle()
                            .fill(isSelected ? Color.white : dotColor)
                            .frame(width: dotSize, height: dotSize)
                            .shadow(color: dotColor.opacity(0.75), radius: 5)
                    }
                    .frame(width: 44, height: 44)
                    .contentShape(Circle())
                }
                .buttonStyle(TactileScaleButtonStyle(pressedScale: 0.84))
                .scaleEffect(isSelected ? 1.2 : 1.0)
                .position(blip.point)
                .accessibilityLabel("\(blip.device.displayName), \(blip.device.formattedDistance)")
            }
        }
    }
}

import SwiftUI

/// Radar interactif plein écran positionnant tous les appareils BLE selon leur distance réelle estimée.
struct BLERadarView: View {
    let devices: [BLEDevice]
    let selectedDeviceID: UUID?
    let isScanning: Bool
    let isConnecting: Bool
    let onSelectDevice: (BLEDevice) -> Void
    let onConnectDevice: (BLEDevice) -> Void
    let onToggleScan: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.verticalSizeClass) private var verticalSizeClass

    private static let radarRingsMeters: [Double] = [1.0, 3.0, 8.0, 15.0]
    private static let ringLabels: [String] = ["1 m", "3 m", "8 m", "15 m"]

    private var selectedDevice: BLEDevice? {
        devices.first { $0.id == selectedDeviceID }
    }

    private var radarHeight: CGFloat {
        (verticalSizeClass == .compact) ? 268 : 338
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
                    .font(.headline.weight(.bold))
                    .foregroundStyle(.white)

                Text("\(devices.count)")
                    .font(.caption.monospacedDigit().weight(.bold))
                    .contentTransition(.numericText())
                    .foregroundStyle(.cyan)
                    .padding(.horizontal, 8)
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
                        .padding(.horizontal, 13)
                        .padding(.vertical, 6)
                        .background(
                            Capsule()
                                .fill(isScanning ? Color.red.opacity(0.85) : Color.cyan)
                        )
                }
                .buttonStyle(TactileScaleButtonStyle(pressedScale: 0.92))
            }

            // Grand disque radar animé à 60/120 Hz avec échos sonar synchronisés au faisceau
            GeometryReader { geo in
                let diameter = min(geo.size.width, geo.size.height)
                let maxR = diameter * 0.5
                let center = CGPoint(x: geo.size.width * 0.5, y: geo.size.height * 0.5)
                let blips = Self.layoutBlips(devices: devices, center: center, maxRadius: maxR)

                ZStack {
                    // Fond sphérique océan profond
                    Circle()
                        .fill(
                            RadialGradient(
                                colors: [
                                    Color(red: 0.05, green: 0.25, blue: 0.34),
                                    Color(red: 0.03, green: 0.14, blue: 0.22),
                                    Color(red: 0.015, green: 0.07, blue: 0.12)
                                ],
                                center: .center,
                                startRadius: 6,
                                endRadius: maxR
                            )
                        )
                        .frame(width: diameter, height: diameter)
                        .allowsHitTesting(false)

                    // Couche vectorielle haute fluidité : grille, graduations, onde sonar, faisceau et échos de passage
                    TimelineView(.animation(minimumInterval: 1.0 / 60.0, paused: !isScanning || reduceMotion)) { context in
                        let sweepDeg = Self.sweepAngleDegrees(for: context.date)
                        let sonarPhase = Self.sonarWavePhase(for: context.date)

                        ZStack {
                            if isScanning && !reduceMotion {
                                Circle()
                                    .fill(
                                        AngularGradient(
                                            stops: [
                                                .init(color: .clear, location: 0.0),
                                                .init(color: .clear, location: 0.76),
                                                .init(color: Color.cyan.opacity(0.06), location: 0.86),
                                                .init(color: Color.cyan.opacity(0.28), location: 0.996),
                                                .init(color: .clear, location: 1.0)
                                            ],
                                            center: .center,
                                            angle: .degrees(sweepDeg)
                                        )
                                    )
                                    .frame(width: diameter, height: diameter)
                                    .allowsHitTesting(false)
                            }

                            Canvas { gc, canvasSize in
                                let c = CGPoint(x: canvasSize.width * 0.5, y: canvasSize.height * 0.5)
                                let rMax = min(canvasSize.width, canvasSize.height) * 0.5

                                // 8 axes radiaux discrets
                                for i in 0..<8 {
                                    let ang = Double(i) * (.pi / 4.0)
                                    var spoke = Path()
                                    spoke.move(to: c)
                                    spoke.addLine(to: CGPoint(x: c.x + rMax * CGFloat(cos(ang)), y: c.y + rMax * CGFloat(sin(ang))))
                                    gc.stroke(spoke, with: .color(Color.cyan.opacity(i % 2 == 0 ? 0.14 : 0.07)), lineWidth: 0.9)
                                }

                                // 24 graduations périphériques style compas
                                for tick in 0..<24 {
                                    let ang = Double(tick) * (.pi / 12.0)
                                    let isCardinal = (tick % 6 == 0)
                                    let tickLen: CGFloat = isCardinal ? 9.0 : 4.5
                                    let rIn = rMax - tickLen
                                    var p = Path()
                                    p.move(to: CGPoint(x: c.x + rIn * CGFloat(cos(ang)), y: c.y + rIn * CGFloat(sin(ang))))
                                    p.addLine(to: CGPoint(x: c.x + rMax * CGFloat(cos(ang)), y: c.y + rMax * CGFloat(sin(ang))))
                                    gc.stroke(p, with: .color(Color.cyan.opacity(isCardinal ? 0.45 : 0.22)), lineWidth: isCardinal ? 1.4 : 0.9)
                                }

                                // Anneaux intermédiaires pointillés (0.5 m, 2 m, 5.5 m)
                                for subMeters in [0.5, 2.0, 5.5] {
                                    let subR = Self.normalizedRadius(forMeters: subMeters) * rMax
                                    let rect = CGRect(x: c.x - subR, y: c.y - subR, width: subR * 2, height: subR * 2)
                                    gc.stroke(
                                        Path(ellipseIn: rect),
                                        with: .color(Color.cyan.opacity(0.09)),
                                        style: StrokeStyle(lineWidth: 0.8, dash: [3, 5])
                                    )
                                }

                                // Anneaux principaux calibrés en mètres
                                for (idx, meters) in Self.radarRingsMeters.enumerated() {
                                    let ringR = Self.normalizedRadius(forMeters: meters) * rMax
                                    let rect = CGRect(x: c.x - ringR, y: c.y - ringR, width: ringR * 2, height: ringR * 2)
                                    let isOuter = (idx == Self.radarRingsMeters.count - 1)
                                    gc.stroke(
                                        Path(ellipseIn: rect),
                                        with: .color(Color.cyan.opacity(isOuter ? 0.34 : 0.22)),
                                        lineWidth: isOuter ? 1.4 : 1.0
                                    )
                                }

                                if isScanning && !reduceMotion {
                                    // Onde sonar concentrique sortante
                                    let waveR = max(6.0, CGFloat(sonarPhase) * rMax)
                                    let waveAlpha = (1.0 - sonarPhase) * 0.46
                                    let waveRect = CGRect(x: c.x - waveR, y: c.y - waveR, width: waveR * 2, height: waveR * 2)
                                    gc.stroke(
                                        Path(ellipseIn: waveRect),
                                        with: .color(Color.cyan.opacity(waveAlpha)),
                                        lineWidth: CGFloat(2.0 - sonarPhase)
                                    )

                                    // Aiguille lumineuse du faisceau
                                    let sweepRad = sweepDeg * .pi / 180.0
                                    var needle = Path()
                                    needle.move(to: c)
                                    needle.addLine(to: CGPoint(
                                        x: c.x + rMax * CGFloat(cos(sweepRad)),
                                        y: c.y + rMax * CGFloat(sin(sweepRad))
                                    ))
                                    gc.stroke(needle, with: .color(Color.cyan.opacity(0.88)), lineWidth: 2.0)

                                    // Écho radar lumineux sur chaque point traversé par le faisceau
                                    for blip in blips {
                                        let diff = Self.positiveAngleDiff(sweepDeg: sweepDeg, blipDeg: blip.angleDeg)
                                        if diff < 62.0 {
                                            let p = diff / 62.0
                                            let echoR = CGFloat(6.0 + p * 22.0)
                                            let echoRect = CGRect(
                                                x: blip.point.x - echoR,
                                                y: blip.point.y - echoR,
                                                width: echoR * 2,
                                                height: echoR * 2
                                            )
                                            let echoColor: Color = blip.device.isLikelyArduino ? .cyan : Color(red: 0.48, green: 0.78, blue: 1.0)
                                            gc.stroke(
                                                Path(ellipseIn: echoRect),
                                                with: .color(echoColor.opacity((1.0 - p) * 0.78)),
                                                lineWidth: 1.6
                                            )
                                        }
                                    }
                                }
                            }
                            .frame(width: geo.size.width, height: geo.size.height)
                            .allowsHitTesting(false)
                        }
                    }

                    // Étiquettes de portée calibrées
                    ForEach(Array(Self.radarRingsMeters.enumerated()), id: \.offset) { idx, meters in
                        let ringR = Self.normalizedRadius(forMeters: meters) * maxR
                        Text(Self.ringLabels[idx])
                            .font(.system(size: 9.5, weight: .semibold, design: .rounded))
                            .tracking(0.3)
                            .foregroundStyle(Color.cyan.opacity(0.86))
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1.5)
                            .background(Color(red: 0.02, green: 0.10, blue: 0.16).opacity(0.88))
                            .clipShape(Capsule())
                            .position(x: center.x, y: center.y - ringR)
                            .allowsHitTesting(false)
                    }

                    // Point central (iPhone / origine 0 m)
                    ZStack {
                        Circle()
                            .fill(Color.white.opacity(0.20))
                            .frame(width: 20, height: 20)
                        Circle()
                            .fill(Color.white)
                            .frame(width: 9, height: 9)
                            .shadow(color: .white.opacity(0.75), radius: 4)
                    }
                    .position(center)
                    .allowsHitTesting(false)

                    // Points interactifs pour chaque appareil BLE
                    ForEach(blips) { blip in
                        let isSelected = (blip.device.id == selectedDeviceID)
                        RadarBlipView(
                            blip: blip,
                            isSelected: isSelected,
                            showLabel: isSelected || (blip.device.isLikelyArduino && blips.count <= 10),
                            containerSize: geo.size,
                            onTap: {
                                if isSelected && blip.device.isConnectable {
                                    AppHaptics.medium()
                                    onConnectDevice(blip.device)
                                } else {
                                    AppHaptics.selection()
                                    withAnimation(AppleMotion.adaptive(AppleMotion.fluidSpring, reduceMotion: reduceMotion)) {
                                        onSelectDevice(blip.device)
                                    }
                                }
                            }
                        )
                        .zIndex(isSelected ? 10 : (blip.device.isLikelyArduino ? 3 : (blip.device.hasResolvedName ? 2 : 1)))
                    }
                }
                .frame(width: geo.size.width, height: geo.size.height)
                .animation(
                    AppleMotion.adaptive(AppleMotion.fluidSpring, reduceMotion: reduceMotion),
                    value: blips.map(\.positionSignature)
                )
            }
            .frame(height: radarHeight)

            // Légende discrète des catégories détectées
            HStack(spacing: 14) {
                legendItem(color: .cyan, label: "Arduino")
                legendItem(color: Color(red: 0.32, green: 0.68, blue: 1.0), label: "Nommé")
                legendItem(color: Color(red: 0.62, green: 0.66, blue: 0.96), label: "Balise BLE")
            }
            .frame(maxWidth: .infinity)

            // Fiche de l'appareil choisi sous le radar
            Group {
                if let device = selectedDevice {
                    HStack(spacing: 12) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(badgeColor(for: device).opacity(0.20))
                                .frame(width: 42, height: 42)
                            Text(badgeCode(for: device))
                                .font(.caption2.weight(.black))
                                .tracking(0.3)
                                .foregroundStyle(badgeColor(for: device))
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
                            .foregroundStyle(.white.opacity(0.78))
                            .lineLimit(1)
                        }

                        Spacer(minLength: 4)

                        if device.isConnectable {
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
                        } else {
                            Text("Balise")
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(.white.opacity(0.72))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(Capsule().fill(Color.white.opacity(0.12)))
                        }
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
                    .transition(reduceMotion ? .opacity : .move(edge: .bottom).combined(with: .opacity))
                } else {
                    Text(
                        devices.isEmpty
                            ? (isScanning ? "Détection de tous les appareils BLE à proximité..." : "Appuyez sur Scanner pour repérer les appareils")
                            : "Touchez un point sur le radar pour voir sa distance et vous connecter"
                    )
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.white.opacity(0.75))
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .transition(.opacity)
                }
            }
            .animation(AppleMotion.adaptive(AppleMotion.fluidSpring, reduceMotion: reduceMotion), value: selectedDevice?.id)
            .animation(AppleMotion.adaptive(AppleMotion.fluidSpring, reduceMotion: reduceMotion), value: isConnecting)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color(red: 0.04, green: 0.14, blue: 0.22),
                            Color(red: 0.025, green: 0.08, blue: 0.14)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .strokeBorder(Color.cyan.opacity(0.28), lineWidth: 1.1)
        )
        .shadow(color: Color.black.opacity(0.22), radius: 14, y: 5)
    }

    private func legendItem(color: Color, label: String) -> some View {
        HStack(spacing: 5) {
            Circle()
                .fill(color)
                .frame(width: 7, height: 7)
            Text(label)
                .font(.caption2.weight(.medium))
                .foregroundStyle(.white.opacity(0.72))
        }
    }

    private func badgeColor(for device: BLEDevice) -> Color {
        if device.isLikelyArduino { return .cyan }
        if device.hasResolvedName { return Color(red: 0.38, green: 0.72, blue: 1.0) }
        return Color(red: 0.65, green: 0.70, blue: 0.98)
    }

    private func badgeCode(for device: BLEDevice) -> String {
        if device.isLikelyArduino { return "ARD" }
        if device.hasResolvedName { return "NOM" }
        return "BLE"
    }

    // MARK: - Géométrie du radar

    private static func sweepAngleDegrees(for date: Date) -> Double {
        let cycle = 3.0
        let phase = date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: cycle) / cycle
        return phase * 360.0
    }

    private static func sonarWavePhase(for date: Date) -> Double {
        let cycle = 2.6
        return date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: cycle) / cycle
    }

    private static func positiveAngleDiff(sweepDeg: Double, blipDeg: Double) -> Double {
        var diff = (sweepDeg - blipDeg).truncatingRemainder(dividingBy: 360.0)
        if diff < 0 { diff += 360.0 }
        return diff
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
        let angleDeg: Double

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
        let limited = Array(devices.prefix(36)).sorted { $0.id.uuidString < $1.id.uuidString }
        var placed: [PositionedBlip] = []
        placed.reserveCapacity(limited.count)

        let minSeparation: CGFloat = 26.0
        let angleOffsets: [Double] = [
            0.0, 0.36, -0.36, 0.72, -0.72, 1.08, -1.08, 1.44, -1.44, 1.80, -1.80, 2.20, -2.20, 2.65, -2.65
        ]

        for device in limited {
            let baseR = normalizedRadius(forMeters: device.estimatedDistanceMeters) * maxRadius
            let baseAngle = device.baseRadarAngle

            var chosenPoint = CGPoint(
                x: center.x + baseR * CGFloat(cos(baseAngle)),
                y: center.y + baseR * CGFloat(sin(baseAngle))
            )
            var chosenAngle = baseAngle

            outer: for rShift in [CGFloat(0), CGFloat(10), CGFloat(-10), CGFloat(20), CGFloat(-18)] {
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
                        chosenAngle = candidateAngle
                        break outer
                    }
                }
            }

            placed.append(
                PositionedBlip(
                    device: device,
                    point: chosenPoint,
                    angleDeg: chosenAngle * 180.0 / .pi
                )
            )
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
            let dotColor: Color = isArduino
                ? .cyan
                : (blip.device.hasResolvedName ? Color(red: 0.32, green: 0.68, blue: 1.0) : Color(red: 0.64, green: 0.68, blue: 0.96))
            let dotSize: CGFloat = isArduino ? 15 : (blip.device.hasResolvedName ? 12 : 9.5)
            let showBelow = blip.point.y < 38
            let clampedLabelX = min(max(blip.point.x, 56), max(56, containerSize.width - 56))
            let labelY = showBelow ? (blip.point.y + 23) : (blip.point.y - 23)

            ZStack {
                if showLabel {
                    Text(isSelected ? "\(blip.device.displayName) • \(blip.device.formattedDistance)" : blip.device.formattedDistance)
                        .font(.system(size: isSelected ? 10 : 9, weight: isSelected ? .bold : .semibold))
                        .multilineTextAlignment(.center)
                        .lineLimit(1)
                        .foregroundStyle(isSelected ? .black : .white)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(
                            Capsule()
                                .fill(isSelected ? Color.cyan : Color.black.opacity(0.72))
                        )
                        .position(x: clampedLabelX, y: labelY)
                        .allowsHitTesting(false)
                }

                Button(action: onTap) {
                    ZStack {
                        if isSelected {
                            Circle()
                                .strokeBorder(Color.white, lineWidth: 2)
                                .frame(width: dotSize + 15, height: dotSize + 15)
                        }

                        if isArduino || blip.device.hasResolvedName {
                            Circle()
                                .fill(dotColor.opacity(isArduino ? 0.32 : 0.20))
                                .frame(width: dotSize + 10, height: dotSize + 10)
                        }

                        Circle()
                            .fill(isSelected ? Color.white : dotColor)
                            .frame(width: dotSize, height: dotSize)
                            .shadow(color: dotColor.opacity(0.80), radius: isArduino ? 6 : 3)
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

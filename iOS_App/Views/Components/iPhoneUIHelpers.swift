import SwiftUI
import UIKit

/// Courbes d'animation inspirées d'iOS pour une fluidité 120 Hz naturelle.
enum AppleMotion {
    static let pressSpring = Animation.interactiveSpring(response: 0.16, dampingFraction: 0.66)
    static let fluidSpring = Animation.spring(response: 0.34, dampingFraction: 0.82)
    static let gentleSpring = Animation.spring(response: 0.42, dampingFraction: 0.86)
}

/// Générateurs haptiques préchauffés sans allocation lors des interactions UI.
enum AppHaptics {
    private static let lightGenerator = UIImpactFeedbackGenerator(style: .light)
    private static let softGenerator = UIImpactFeedbackGenerator(style: .soft)
    private static let mediumGenerator = UIImpactFeedbackGenerator(style: .medium)
    private static let selectionGenerator = UISelectionFeedbackGenerator()
    private static let notificationGenerator = UINotificationFeedbackGenerator()

    static func light() {
        lightGenerator.impactOccurred()
        lightGenerator.prepare()
    }

    static func soft() {
        softGenerator.impactOccurred()
        softGenerator.prepare()
    }

    static func medium() {
        mediumGenerator.impactOccurred()
        mediumGenerator.prepare()
    }

    static func selection() {
        selectionGenerator.selectionChanged()
        selectionGenerator.prepare()
    }

    static func success() {
        notificationGenerator.notificationOccurred(.success)
        notificationGenerator.prepare()
    }

    static func warning() {
        notificationGenerator.notificationOccurred(.warning)
        notificationGenerator.prepare()
    }
}

/// Style de bouton tactile avec rebond à la pression façon iOS (pour contrôles hors List).
struct TactileScaleButtonStyle: ButtonStyle {
    var pressedScale: CGFloat = 0.93
    var pressedOpacity: Double = 0.88

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? pressedScale : 1.0)
            .opacity(configuration.isPressed ? pressedOpacity : 1.0)
            .animation(AppleMotion.pressSpring, value: configuration.isPressed)
    }
}

/// Voyant d'état lumineux avec onde pulsée active pendant le scan ou la connexion.
struct LivePulseBeacon: View {
    let color: Color
    let isPulsing: Bool
    var dotSize: CGFloat = 10

    var body: some View {
        ZStack {
            if isPulsing {
                PulseHaloRing(color: color, baseSize: dotSize)
            }
            Circle()
                .fill(color.opacity(0.24))
                .frame(width: dotSize * 1.75, height: dotSize * 1.75)
            Circle()
                .fill(color)
                .frame(width: dotSize, height: dotSize)
                .shadow(color: color.opacity(0.45), radius: 3, y: 1)
        }
        .frame(width: dotSize * 2.2, height: dotSize * 2.2)
        .animation(AppleMotion.fluidSpring, value: color)
    }
}

private struct PulseHaloRing: View {
    let color: Color
    let baseSize: CGFloat

    @State private var expanded = false

    var body: some View {
        Circle()
            .stroke(color.opacity(expanded ? 0.0 : 0.65), lineWidth: 2)
            .frame(width: baseSize, height: baseSize)
            .scaleEffect(expanded ? 2.4 : 1.0)
            .onAppear {
                expanded = false
                withAnimation(.easeOut(duration: 1.35).repeatForever(autoreverses: false)) {
                    expanded = true
                }
            }
    }
}

/// Enveloppe tactile réactive pour les touches de manette (déclenchement instantané à l'appui).
struct TactileHoldControl<S: InsettableShape, Content: View>: View {
    let hitShape: S
    let isActive: Bool
    var pressedScale: CGFloat = 0.91
    let onDown: () -> Void
    let onUp: () -> Void
    @ViewBuilder let content: (_ highlighted: Bool, _ isPressed: Bool) -> Content

    @State private var isPressedLocally = false

    private var highlighted: Bool {
        isPressedLocally || isActive
    }

    var body: some View {
        content(highlighted, isPressedLocally)
            .scaleEffect(isPressedLocally ? pressedScale : 1.0)
            .brightness(isPressedLocally ? -0.04 : 0.0)
            .animation(AppleMotion.pressSpring, value: isPressedLocally)
            .animation(.easeOut(duration: 0.16), value: isActive)
            .contentShape(hitShape)
            .highPriorityGesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in
                        if !isPressedLocally {
                            isPressedLocally = true
                            onDown()
                        }
                    }
                    .onEnded { _ in
                        if isPressedLocally {
                            isPressedLocally = false
                            onUp()
                        }
                    }
            )
            .onDisappear {
                if isPressedLocally {
                    isPressedLocally = false
                    onUp()
                }
            }
    }
}

/// Surface de touche matérielle façon iPhone (reflet supérieur subtil, bordure et halo coloré).
struct HardwareKeycapBackground<S: InsettableShape>: View {
    let shape: S
    let color: Color
    let highlighted: Bool
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let idleOpacity: Double = (colorScheme == .dark) ? 0.22 : 0.13
        let specularTop: Double = highlighted ? 0.26 : (colorScheme == .dark ? 0.10 : 0.45)

        shape
            .fill(highlighted ? color : color.opacity(idleOpacity))
            .overlay(
                shape
                    .fill(
                        LinearGradient(
                            colors: [Color.white.opacity(specularTop), .clear],
                            startPoint: .top,
                            endPoint: .center
                        )
                    )
            )
            .overlay(
                shape
                    .strokeBorder(
                        highlighted ? Color.white.opacity(0.32) : color.opacity(0.45),
                        lineWidth: highlighted ? 1.6 : 1.25
                    )
            )
            .shadow(
                color: highlighted ? color.opacity(0.38) : Color.black.opacity(colorScheme == .dark ? 0.25 : 0.05),
                radius: highlighted ? 9 : 3,
                y: highlighted ? 3 : 1
            )
    }
}

/// Style de carte groupée native iOS (fond surélevé avec bordure fine et ombre douce).
struct AppleGroupedCardModifier: ViewModifier {
    var cornerRadius: CGFloat = 18
    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(Color(.secondarySystemGroupedBackground))
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(
                        Color.primary.opacity(colorScheme == .dark ? 0.09 : 0.05),
                        lineWidth: 0.75
                    )
            )
            .shadow(
                color: Color.black.opacity(colorScheme == .dark ? 0.26 : 0.045),
                radius: 8,
                y: 2
            )
    }
}

extension View {
    func appleGroupedCard(cornerRadius: CGFloat = 18) -> some View {
        modifier(AppleGroupedCardModifier(cornerRadius: cornerRadius))
    }
}

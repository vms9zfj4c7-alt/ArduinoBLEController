import SwiftUI
import UIKit

/// Courbes physiques calibrées selon Apple Designing Fluid Interfaces :
/// amortissement critique (1.0) par défaut, léger rebond (~0.8) uniquement au relâchement tactile.
enum AppleMotion {
    static let pressSpring = Animation.interactiveSpring(response: 0.20, dampingFraction: 0.80)
    static let fluidSpring = Animation.spring(response: 0.34, dampingFraction: 1.0)
    static let gentleSpring = Animation.spring(response: 0.42, dampingFraction: 1.0)
    static let reducedMotionFallback = Animation.easeInOut(duration: 0.16)

    static func adaptive(_ animation: Animation, reduceMotion: Bool) -> Animation {
        reduceMotion ? reducedMotionFallback : animation
    }
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

/// Style de bouton tactile avec retour immédiat au toucher (hors List/Form) et respect de Réduire les animations.
struct TactileScaleButtonStyle: ButtonStyle {
    var pressedScale: CGFloat = 0.94
    var pressedOpacity: Double = 0.86
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect((configuration.isPressed && !reduceMotion) ? pressedScale : 1.0)
            .opacity(configuration.isPressed ? pressedOpacity : 1.0)
            .animation(
                AppleMotion.adaptive(AppleMotion.pressSpring, reduceMotion: reduceMotion),
                value: configuration.isPressed
            )
    }
}

/// Voyant d'état lumineux avec onde pulsée active pendant le scan ou la connexion (respecte Réduire les animations).
struct LivePulseBeacon: View {
    let color: Color
    let isPulsing: Bool
    var dotSize: CGFloat = 10
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            if isPulsing && !reduceMotion {
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
        .animation(AppleMotion.adaptive(AppleMotion.fluidSpring, reduceMotion: reduceMotion), value: color)
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

/// Enveloppe tactile réactive : déclenche l'action dès le contact (touch-down) sans latence.
struct TactileHoldControl<S: InsettableShape, Content: View>: View {
    let hitShape: S
    let isActive: Bool
    var pressedScale: CGFloat = 0.92
    let onDown: () -> Void
    let onUp: () -> Void
    @ViewBuilder let content: (_ highlighted: Bool, _ isPressed: Bool) -> Content

    @State private var isPressedLocally = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var highlighted: Bool {
        isPressedLocally || isActive
    }

    var body: some View {
        content(highlighted, isPressedLocally)
            .scaleEffect((isPressedLocally && !reduceMotion) ? pressedScale : 1.0)
            .brightness(isPressedLocally ? -0.05 : 0.0)
            .animation(
                AppleMotion.adaptive(AppleMotion.pressSpring, reduceMotion: reduceMotion),
                value: isPressedLocally
            )
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

/// Bouton d'arrêt d'urgence réactif dès l'appui (latence minimale) avec texte centré.
struct EmergencyStopHoldButton: View {
    var font: Font = .subheadline.weight(.black)
    var minHeight: CGFloat = 46
    let onTrigger: () -> Void

    var body: some View {
        let capsule = Capsule()

        TactileHoldControl(
            hitShape: capsule,
            isActive: false,
            pressedScale: 0.94,
            onDown: onTrigger,
            onUp: {}
        ) { highlighted, _ in
            Text("STOP")
                .font(font)
                .tracking(0.6)
                .multilineTextAlignment(.center)
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, minHeight: minHeight, alignment: .center)
                .background(
                    capsule
                        .fill(Color.red)
                        .overlay(
                            capsule.fill(
                                LinearGradient(
                                    colors: [Color.white.opacity(highlighted ? 0.10 : 0.24), .clear],
                                    startPoint: .top,
                                    endPoint: .center
                                )
                            )
                        )
                        .shadow(color: Color.red.opacity(0.35), radius: highlighted ? 3 : 6, y: highlighted ? 1 : 3)
                )
        }
        .accessibilityLabel("Arrêt d'urgence STOP")
    }
}

/// Surface de touche matérielle façon iPhone (reflet supérieur subtil, contraste adaptatif et halo coloré).
struct HardwareKeycapBackground<S: InsettableShape>: View {
    let shape: S
    let color: Color
    let highlighted: Bool
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var colorContrast

    var body: some View {
        let highContrast = (colorContrast == .increased)
        let idleOpacity: Double = (colorScheme == .dark) ? (highContrast ? 0.28 : 0.22) : (highContrast ? 0.18 : 0.13)
        let specularTop: Double = highlighted ? 0.24 : (colorScheme == .dark ? 0.10 : 0.42)
        let strokeWidth: CGFloat = highlighted ? 1.8 : (highContrast ? 1.7 : 1.25)

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
                        highlighted ? Color.white.opacity(0.34) : color.opacity(highContrast ? 0.72 : 0.45),
                        lineWidth: strokeWidth
                    )
            )
            .shadow(
                color: highlighted ? color.opacity(0.38) : Color.black.opacity(colorScheme == .dark ? 0.24 : 0.05),
                radius: highlighted ? 9 : 3,
                y: highlighted ? 3 : 1
            )
    }
}

/// Style de carte groupée native iOS (fond surélevé avec bordure adaptative au contraste et ombre douce).
struct AppleGroupedCardModifier: ViewModifier {
    var cornerRadius: CGFloat = 18
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var colorContrast

    func body(content: Content) -> some View {
        let highContrast = (colorContrast == .increased)

        content
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(Color(.secondarySystemGroupedBackground))
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(
                        Color.primary.opacity(colorScheme == .dark ? (highContrast ? 0.22 : 0.10) : (highContrast ? 0.16 : 0.055)),
                        lineWidth: highContrast ? 1.2 : 0.75
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

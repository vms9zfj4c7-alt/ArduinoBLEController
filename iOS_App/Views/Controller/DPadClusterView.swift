import SwiftUI

/// Croix directionnelle tactile épurée sans icône, centrée et optimisée portrait / paysage.
struct DPadClusterView: View, Equatable {
    let upAssignment: ButtonAssignment
    let downAssignment: ButtonAssignment
    let leftAssignment: ButtonAssignment
    let rightAssignment: ButtonAssignment

    let isUpActive: Bool
    let isDownActive: Bool
    let isLeftActive: Bool
    let isRightActive: Bool

    var buttonSize: CGFloat = 62
    var gridSpacing: CGFloat = 8
    var containerPadding: CGFloat = 11
    var cornerRadius: CGFloat = 16
    var isCompact: Bool = false

    let onDown: (GamepadSlot) -> Void
    let onUp: (GamepadSlot) -> Void

    static func == (lhs: DPadClusterView, rhs: DPadClusterView) -> Bool {
        lhs.upAssignment == rhs.upAssignment
            && lhs.downAssignment == rhs.downAssignment
            && lhs.leftAssignment == rhs.leftAssignment
            && lhs.rightAssignment == rhs.rightAssignment
            && lhs.isUpActive == rhs.isUpActive
            && lhs.isDownActive == rhs.isDownActive
            && lhs.isLeftActive == rhs.isLeftActive
            && lhs.isRightActive == rhs.isRightActive
            && lhs.buttonSize == rhs.buttonSize
            && lhs.isCompact == rhs.isCompact
    }

    var body: some View {
        let hubOuter = max(36, buttonSize - 8)
        let hubInner = max(14, hubOuter * 0.40)

        VStack(spacing: gridSpacing) {
            GamepadTactileButton(
                directionGlyph: "↑",
                assignment: upAssignment,
                isActive: isUpActive,
                size: buttonSize,
                cornerRadius: cornerRadius,
                isCompact: isCompact,
                onDown: { onDown(.dpadUp) },
                onUp: { onUp(.dpadUp) }
            )

            HStack(spacing: gridSpacing) {
                GamepadTactileButton(
                    directionGlyph: "←",
                    assignment: leftAssignment,
                    isActive: isLeftActive,
                    size: buttonSize,
                    cornerRadius: cornerRadius,
                    isCompact: isCompact,
                    onDown: { onDown(.dpadLeft) },
                    onUp: { onUp(.dpadLeft) }
                )

                ZStack {
                    RoundedRectangle(cornerRadius: isCompact ? 11 : 14, style: .continuous)
                        .fill(Color(.tertiarySystemFill))
                        .frame(width: hubOuter, height: hubOuter)
                        .overlay(
                            RoundedRectangle(cornerRadius: isCompact ? 11 : 14, style: .continuous)
                                .strokeBorder(Color.primary.opacity(0.06), lineWidth: 1)
                        )
                    Circle()
                        .fill(Color(.quaternarySystemFill))
                        .frame(width: hubInner, height: hubInner)
                        .overlay(
                            Circle()
                                .strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.75)
                        )
                }

                GamepadTactileButton(
                    directionGlyph: "→",
                    assignment: rightAssignment,
                    isActive: isRightActive,
                    size: buttonSize,
                    cornerRadius: cornerRadius,
                    isCompact: isCompact,
                    onDown: { onDown(.dpadRight) },
                    onUp: { onUp(.dpadRight) }
                )
            }

            GamepadTactileButton(
                directionGlyph: "↓",
                assignment: downAssignment,
                isActive: isDownActive,
                size: buttonSize,
                cornerRadius: cornerRadius,
                isCompact: isCompact,
                onDown: { onDown(.dpadDown) },
                onUp: { onUp(.dpadDown) }
            )
        }
        .padding(containerPadding)
        .appleGroupedCard(cornerRadius: isCompact ? 22 : 28)
    }
}

/// Bouton tactile réutilisable répondant à l'appui immédiat et au relâchement, avec texte parfaitement centré.
struct GamepadTactileButton: View {
    var directionGlyph: String = ""
    let assignment: ButtonAssignment
    let isActive: Bool
    let size: CGFloat
    let cornerRadius: CGFloat
    var isCompact: Bool = false
    let onDown: () -> Void
    let onUp: () -> Void

    var body: some View {
        let baseColor = assignment.colorToken.color
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)

        TactileHoldControl(
            hitShape: shape,
            isActive: isActive,
            pressedScale: 0.91,
            onDown: onDown,
            onUp: onUp
        ) { highlighted, _ in
            VStack(spacing: isCompact ? 1 : 2) {
                if !directionGlyph.isEmpty {
                    Text(directionGlyph)
                        .font(.system(size: isCompact ? 13 : 16, weight: .bold))
                }
                Text(assignment.label)
                    .font(.system(size: isCompact ? 9.5 : 10.5, weight: .semibold))
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .minimumScaleFactor(0.65)
            }
            .foregroundStyle(highlighted ? .white : baseColor)
            .padding(.horizontal, 4)
            .frame(width: size, height: size, alignment: .center)
            .background(
                HardwareKeycapBackground(
                    shape: shape,
                    color: baseColor,
                    highlighted: highlighted
                )
            )
        }
        .accessibilityLabel(assignment.label)
    }
}

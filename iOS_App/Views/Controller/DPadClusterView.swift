import SwiftUI

/// Croix directionnelle tactile de style manette avec détection d'appui maintenu / relâchement.
struct DPadClusterView: View, Equatable {
    let upAssignment: ButtonAssignment
    let downAssignment: ButtonAssignment
    let leftAssignment: ButtonAssignment
    let rightAssignment: ButtonAssignment

    let isUpActive: Bool
    let isDownActive: Bool
    let isLeftActive: Bool
    let isRightActive: Bool

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
    }

    var body: some View {
        VStack(spacing: 8) {
            GamepadTactileButton(
                assignment: upAssignment,
                isActive: isUpActive,
                size: 62,
                cornerRadius: 16,
                onDown: { onDown(.dpadUp) },
                onUp: { onUp(.dpadUp) }
            )

            HStack(spacing: 8) {
                GamepadTactileButton(
                    assignment: leftAssignment,
                    isActive: isLeftActive,
                    size: 62,
                    cornerRadius: 16,
                    onDown: { onDown(.dpadLeft) },
                    onUp: { onUp(.dpadLeft) }
                )

                ZStack {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Color(.tertiarySystemFill))
                        .frame(width: 54, height: 54)
                        .overlay(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .strokeBorder(Color.primary.opacity(0.06), lineWidth: 1)
                        )
                    Circle()
                        .fill(Color(.quaternarySystemFill))
                        .frame(width: 22, height: 22)
                        .overlay(
                            Circle()
                                .strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.75)
                        )
                }

                GamepadTactileButton(
                    assignment: rightAssignment,
                    isActive: isRightActive,
                    size: 62,
                    cornerRadius: 16,
                    onDown: { onDown(.dpadRight) },
                    onUp: { onUp(.dpadRight) }
                )
            }

            GamepadTactileButton(
                assignment: downAssignment,
                isActive: isDownActive,
                size: 62,
                cornerRadius: 16,
                onDown: { onDown(.dpadDown) },
                onUp: { onUp(.dpadDown) }
            )
        }
        .padding(11)
        .appleGroupedCard(cornerRadius: 28)
    }
}

/// Bouton tactile réutilisable répondant à l'appui immédiat et au relâchement.
struct GamepadTactileButton: View {
    let assignment: ButtonAssignment
    let isActive: Bool
    let size: CGFloat
    let cornerRadius: CGFloat
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
            VStack(spacing: 3) {
                Image(systemName: assignment.symbolName)
                    .font(.system(size: size * 0.30, weight: .bold))
                Text(assignment.label)
                    .font(.system(size: 10, weight: .semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .padding(.horizontal, 4)
            }
            .foregroundStyle(highlighted ? .white : baseColor)
            .frame(width: size, height: size)
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

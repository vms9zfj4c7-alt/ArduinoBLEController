import SwiftUI

/// Groupe de 4 boutons d'action en losange (Y, X, B, A) sans icône, avec texte centré.
struct ActionButtonsClusterView: View, Equatable {
    let buttonY: ButtonAssignment
    let buttonX: ButtonAssignment
    let buttonB: ButtonAssignment
    let buttonA: ButtonAssignment

    let isYActive: Bool
    let isXActive: Bool
    let isBActive: Bool
    let isAActive: Bool

    var buttonSize: CGFloat = 64
    var middleGap: CGFloat = 46
    var verticalGap: CGFloat = -2
    var containerPadding: CGFloat = 12
    var isCompact: Bool = false

    let onDown: (GamepadSlot) -> Void
    let onUp: (GamepadSlot) -> Void

    static func == (lhs: ActionButtonsClusterView, rhs: ActionButtonsClusterView) -> Bool {
        lhs.buttonY == rhs.buttonY
            && lhs.buttonX == rhs.buttonX
            && lhs.buttonB == rhs.buttonB
            && lhs.buttonA == rhs.buttonA
            && lhs.isYActive == rhs.isYActive
            && lhs.isXActive == rhs.isXActive
            && lhs.isBActive == rhs.isBActive
            && lhs.isAActive == rhs.isAActive
            && lhs.buttonSize == rhs.buttonSize
            && lhs.isCompact == rhs.isCompact
    }

    var body: some View {
        VStack(spacing: verticalGap) {
            DiamondFaceButton(
                slotLetter: "Y",
                assignment: buttonY,
                isActive: isYActive,
                buttonSize: buttonSize,
                isCompact: isCompact,
                onDown: { onDown(.buttonY) },
                onUp: { onUp(.buttonY) }
            )

            HStack(spacing: middleGap) {
                DiamondFaceButton(
                    slotLetter: "X",
                    assignment: buttonX,
                    isActive: isXActive,
                    buttonSize: buttonSize,
                    isCompact: isCompact,
                    onDown: { onDown(.buttonX) },
                    onUp: { onUp(.buttonX) }
                )

                DiamondFaceButton(
                    slotLetter: "B",
                    assignment: buttonB,
                    isActive: isBActive,
                    buttonSize: buttonSize,
                    isCompact: isCompact,
                    onDown: { onDown(.buttonB) },
                    onUp: { onUp(.buttonB) }
                )
            }

            DiamondFaceButton(
                slotLetter: "A",
                assignment: buttonA,
                isActive: isAActive,
                buttonSize: buttonSize,
                isCompact: isCompact,
                onDown: { onDown(.buttonA) },
                onUp: { onUp(.buttonA) }
            )
        }
        .padding(containerPadding)
        .appleGroupedCard(cornerRadius: isCompact ? 22 : 28)
    }
}

private struct DiamondFaceButton: View {
    let slotLetter: String
    let assignment: ButtonAssignment
    let isActive: Bool
    let buttonSize: CGFloat
    let isCompact: Bool
    let onDown: () -> Void
    let onUp: () -> Void

    var body: some View {
        let baseColor = assignment.colorToken.color
        let circle = Circle()

        TactileHoldControl(
            hitShape: circle,
            isActive: isActive,
            pressedScale: 0.90,
            onDown: onDown,
            onUp: onUp
        ) { highlighted, _ in
            VStack(spacing: isCompact ? 0.5 : 2) {
                Text(slotLetter)
                    .font(.system(size: isCompact ? 14 : 17, weight: .black, design: .rounded))
                    .tracking(-0.2)
                    .frame(maxWidth: .infinity)
                Text(assignment.label)
                    .font(.system(size: isCompact ? 8.5 : 10, weight: .semibold))
                    .tracking(0.1)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .minimumScaleFactor(0.62)
                    .frame(maxWidth: .infinity)
            }
            .foregroundStyle(highlighted ? .white : baseColor)
            .padding(.horizontal, isCompact ? 5 : 7)
            .frame(width: buttonSize, height: buttonSize, alignment: .center)
            .background(
                HardwareKeycapBackground(
                    shape: circle,
                    color: baseColor,
                    highlighted: highlighted
                )
            )
        }
        .accessibilityLabel("\(slotLetter) - \(assignment.label)")
    }
}

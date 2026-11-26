import SwiftUI

/// Groupe de 4 boutons d'action disposés en losange (Y, X, B, A) façon manette de jeu.
struct ActionButtonsClusterView: View, Equatable {
    let buttonY: ButtonAssignment
    let buttonX: ButtonAssignment
    let buttonB: ButtonAssignment
    let buttonA: ButtonAssignment

    let isYActive: Bool
    let isXActive: Bool
    let isBActive: Bool
    let isAActive: Bool

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
    }

    var body: some View {
        VStack(spacing: 6) {
            DiamondFaceButton(
                slotLetter: "Y",
                assignment: buttonY,
                isActive: isYActive,
                onDown: { onDown(.buttonY) },
                onUp: { onUp(.buttonY) }
            )

            HStack(spacing: 38) {
                DiamondFaceButton(
                    slotLetter: "X",
                    assignment: buttonX,
                    isActive: isXActive,
                    onDown: { onDown(.buttonX) },
                    onUp: { onUp(.buttonX) }
                )

                DiamondFaceButton(
                    slotLetter: "B",
                    assignment: buttonB,
                    isActive: isBActive,
                    onDown: { onDown(.buttonB) },
                    onUp: { onUp(.buttonB) }
                )
            }

            DiamondFaceButton(
                slotLetter: "A",
                assignment: buttonA,
                isActive: isAActive,
                onDown: { onDown(.buttonA) },
                onUp: { onUp(.buttonA) }
            )
        }
        .padding(12)
        .appleGroupedCard(cornerRadius: 28)
    }
}

private struct DiamondFaceButton: View {
    let slotLetter: String
    let assignment: ButtonAssignment
    let isActive: Bool
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
            ZStack(alignment: .topTrailing) {
                VStack(spacing: 2) {
                    Image(systemName: assignment.symbolName)
                        .font(.system(size: 18, weight: .bold))
                    Text(assignment.label)
                        .font(.system(size: 10, weight: .semibold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .padding(.horizontal, 5)
                }
                .foregroundStyle(highlighted ? .white : baseColor)
                .frame(width: 64, height: 64)
                .background(
                    HardwareKeycapBackground(
                        shape: circle,
                        color: baseColor,
                        highlighted: highlighted
                    )
                )

                Text(slotLetter)
                    .font(.system(size: 9, weight: .black))
                    .foregroundStyle(.white)
                    .frame(width: 18, height: 18)
                    .background(
                        Circle()
                            .fill(baseColor)
                            .shadow(color: baseColor.opacity(0.35), radius: 2, y: 1)
                    )
                    .overlay(
                        Circle()
                            .strokeBorder(Color(.secondarySystemGroupedBackground), lineWidth: 1.5)
                    )
                    .offset(x: 2, y: -2)
            }
        }
        .accessibilityLabel("\(slotLetter) - \(assignment.label)")
    }
}

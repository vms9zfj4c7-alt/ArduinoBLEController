import SwiftUI

/// Groupe de 4 boutons d'action disposés en losange (Y, X, B, A) façon manette de jeu.
struct ActionButtonsClusterView: View {
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
        .background(
            RoundedRectangle(cornerRadius: 28)
                .fill(Color(.secondarySystemBackground))
        )
    }
}

private struct DiamondFaceButton: View {
    let slotLetter: String
    let assignment: ButtonAssignment
    let isActive: Bool
    let onDown: () -> Void
    let onUp: () -> Void

    @State private var isPressedLocally = false

    private var highlighted: Bool {
        isPressedLocally || isActive
    }

    var body: some View {
        let baseColor = assignment.colorToken.color

        ZStack(alignment: .topTrailing) {
            VStack(spacing: 2) {
                Image(systemName: assignment.symbolName)
                    .font(.system(size: 18, weight: .bold))
                Text(assignment.label)
                    .font(.system(size: 10, weight: .semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .padding(.horizontal, 4)
            }
            .foregroundStyle(highlighted ? .white : baseColor)
            .frame(width: 64, height: 64)
            .background(
                Circle()
                    .fill(highlighted ? baseColor : baseColor.opacity(0.16))
            )
            .overlay(
                Circle()
                    .strokeBorder(baseColor.opacity(highlighted ? 0.95 : 0.50), lineWidth: 2)
            )
            .shadow(color: highlighted ? baseColor.opacity(0.4) : .clear, radius: 7, y: 2)

            Text(slotLetter)
                .font(.system(size: 9, weight: .black))
                .foregroundStyle(.white)
                .frame(width: 18, height: 18)
                .background(Circle().fill(baseColor.opacity(0.9)))
                .offset(x: 2, y: -2)
        }
        .scaleEffect(isPressedLocally ? 0.91 : 1.0)
        .animation(.easeOut(duration: 0.10), value: isPressedLocally)
        .contentShape(Circle())
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
        .accessibilityLabel("\(slotLetter) - \(assignment.label)")
    }
}

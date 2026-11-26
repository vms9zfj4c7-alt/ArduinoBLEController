import SwiftUI

/// Croix directionnelle tactile de style manette avec détection d'appui maintenu / relâchement.
struct DPadClusterView: View {
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
                    RoundedRectangle(cornerRadius: 14)
                        .fill(Color(.tertiarySystemFill))
                        .frame(width: 54, height: 54)
                    Circle()
                        .fill(Color(.quaternarySystemFill))
                        .frame(width: 24, height: 24)
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
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 28)
                .fill(Color(.secondarySystemBackground))
        )
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

    @State private var isPressedLocally = false

    private var highlighted: Bool {
        isPressedLocally || isActive
    }

    var body: some View {
        let baseColor = assignment.colorToken.color

        VStack(spacing: 3) {
            Image(systemName: assignment.symbolName)
                .font(.system(size: size * 0.30, weight: .bold))
            Text(assignment.label)
                .font(.system(size: 10, weight: .semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .foregroundStyle(highlighted ? .white : baseColor)
        .frame(width: size, height: size)
        .background(
            RoundedRectangle(cornerRadius: cornerRadius)
                .fill(highlighted ? baseColor : baseColor.opacity(0.16))
        )
        .overlay(
            RoundedRectangle(cornerRadius: cornerRadius)
                .strokeBorder(baseColor.opacity(highlighted ? 0.95 : 0.45), lineWidth: 1.5)
        )
        .shadow(color: highlighted ? baseColor.opacity(0.35) : .clear, radius: 6, y: 2)
        .scaleEffect(isPressedLocally ? 0.92 : 1.0)
        .animation(.easeOut(duration: 0.10), value: isPressedLocally)
        .contentShape(RoundedRectangle(cornerRadius: cornerRadius))
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
        .accessibilityLabel(assignment.label)
    }
}

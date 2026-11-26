import SwiftUI

/// Console de logs BLE pliable (émissions, réceptions et envoi de commandes manuelles).
struct LogConsoleView: View {
    @ObservedObject var logStore: BLELogStore
    let isConnected: Bool
    let onSendRawCommand: (String) -> Void
    let onClearLogs: () -> Void

    @State private var isExpanded: Bool = false
    @State private var rawCommandText: String = ""

    private var canSendCommand: Bool {
        isConnected && !rawCommandText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Button(action: toggleExpanded) {
                    HStack(spacing: 10) {
                        Image(systemName: "terminal.fill")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Color.accentColor)
                            .frame(width: 26, height: 26)
                            .background(Color.accentColor.opacity(0.12))
                            .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))

                        Text("Console BLE")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.primary)

                        Text("\(logStore.totalCount)")
                            .font(.caption2.weight(.bold).monospacedDigit())
                            .contentTransition(.numericText())
                            .padding(.horizontal, 7)
                            .padding(.vertical, 2)
                            .background(Color.secondary.opacity(0.16))
                            .foregroundStyle(.secondary)
                            .clipShape(Capsule())
                            .animation(AppleMotion.fluidSpring, value: logStore.totalCount)

                        Spacer()
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                if isExpanded && logStore.totalCount > 0 {
                    Button("Effacer", role: .destructive) {
                        AppHaptics.soft()
                        withAnimation(AppleMotion.fluidSpring) {
                            onClearLogs()
                        }
                    }
                    .font(.caption.weight(.semibold))
                    .buttonStyle(.borderless)
                    .transition(.scale(scale: 0.85).combined(with: .opacity))
                }

                Button(action: toggleExpanded) {
                    Image(systemName: "chevron.down")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.secondary)
                        .rotationEffect(.degrees(isExpanded ? 180 : 0))
                        .padding(6)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(isExpanded ? "Réduire la console" : "Déplier la console")
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)

            if isExpanded {
                VStack(spacing: 0) {
                    Divider()
                        .opacity(0.5)

                    ScrollViewReader { proxy in
                        ScrollView {
                            LazyVStack(alignment: .leading, spacing: 4) {
                                if logStore.entries.isEmpty {
                                    Text("Aucun échange BLE enregistré pour le moment.")
                                        .font(.caption.monospaced())
                                        .foregroundStyle(.secondary)
                                        .padding(.vertical, 20)
                                        .frame(maxWidth: .infinity, alignment: .center)
                                } else {
                                    ForEach(logStore.entries) { entry in
                                        HStack(alignment: .top, spacing: 6) {
                                            Text(entry.formattedTime)
                                                .foregroundStyle(.secondary)
                                            Text(entry.prefixSymbol)
                                                .fontWeight(.bold)
                                                .foregroundStyle(color(for: entry.direction))
                                            Text(entry.message)
                                                .foregroundStyle(color(for: entry.direction))
                                                .textSelection(.enabled)
                                        }
                                        .font(.system(size: 11, design: .monospaced))
                                        .id(entry.id)
                                    }
                                }
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                        }
                        .frame(height: 155)
                        .background(Color(.tertiarySystemGroupedBackground).opacity(0.65))
                        .onChange(of: logStore.entries.last?.id) { lastID in
                            if let lastID {
                                withAnimation(.easeOut(duration: 0.18)) {
                                    proxy.scrollTo(lastID, anchor: .bottom)
                                }
                            }
                        }
                    }

                    Divider()
                        .opacity(0.5)

                    HStack(spacing: 8) {
                        TextField("Commande brute (ex: I?, D:13:1, PING)", text: $rawCommandText)
                            .font(.system(size: 13, design: .monospaced))
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(
                                Capsule()
                                    .fill(Color(.tertiarySystemFill))
                            )
                            .onSubmit {
                                submitRawCommand()
                            }

                        Button {
                            submitRawCommand()
                        } label: {
                            Image(systemName: "arrow.up.circle.fill")
                                .font(.system(size: 28))
                                .foregroundStyle(canSendCommand ? Color.accentColor : Color.secondary.opacity(0.35))
                                .scaleEffect(canSendCommand ? 1.0 : 0.92)
                                .animation(AppleMotion.pressSpring, value: canSendCommand)
                        }
                        .buttonStyle(TactileScaleButtonStyle(pressedScale: 0.88))
                        .disabled(!canSendCommand)
                        .accessibilityLabel("Envoyer la commande")
                    }
                    .padding(10)
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .appleGroupedCard(cornerRadius: 18)
        .clipped()
        .onAppear {
            if isExpanded { logStore.setExpanded(true) }
        }
        .onDisappear {
            logStore.setExpanded(false)
        }
    }

    private func submitRawCommand() {
        guard isConnected else { return }
        let trimmed = rawCommandText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        AppHaptics.light()
        rawCommandText = ""
        onSendRawCommand(trimmed)
    }

    private func toggleExpanded() {
        AppHaptics.soft()
        let next = !isExpanded
        withAnimation(AppleMotion.fluidSpring) {
            isExpanded = next
        }
        logStore.setExpanded(next)
    }

    private func color(for direction: BLELogEntry.Direction) -> Color {
        switch direction {
        case .tx: return .blue
        case .rx: return .green
        case .info: return .secondary
        case .error: return .red
        }
    }
}

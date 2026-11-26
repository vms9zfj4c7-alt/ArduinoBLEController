import SwiftUI

/// Console de logs BLE pliable (émissions, réceptions et envoi de commandes manuelles).
struct LogConsoleView: View {
    @ObservedObject var logStore: BLELogStore
    let isConnected: Bool
    var alwaysExpanded: Bool = false
    let onSendRawCommand: (String) -> Void
    let onClearLogs: () -> Void

    @State private var isExpanded: Bool = false
    @State private var rawCommandText: String = ""
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var showBody: Bool {
        alwaysExpanded || isExpanded
    }

    private var canSendCommand: Bool {
        isConnected && !rawCommandText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                if alwaysExpanded {
                    headerLabel
                } else {
                    Button(action: toggleExpanded) {
                        headerLabel
                    }
                    .buttonStyle(.plain)
                }

                if showBody && logStore.totalCount > 0 {
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

                if !alwaysExpanded {
                    Button(action: toggleExpanded) {
                        Text(isExpanded ? "Masquer" : "Afficher")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 9)
                            .padding(.vertical, 4)
                            .background(Color(.tertiarySystemFill))
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)

            if showBody {
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
                                        .multilineTextAlignment(.center)
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
                        .frame(height: alwaysExpanded ? 210 : 155)
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
                            Text("Envoyer")
                                .font(.caption.weight(.bold))
                                .foregroundStyle(canSendCommand ? .white : .secondary)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background(
                                    Capsule()
                                        .fill(canSendCommand ? Color.accentColor : Color(.tertiarySystemFill))
                                )
                                .animation(AppleMotion.pressSpring, value: canSendCommand)
                        }
                        .buttonStyle(TactileScaleButtonStyle(pressedScale: 0.92))
                        .disabled(!canSendCommand)
                    }
                    .padding(10)
                }
                .transition(reduceMotion ? .opacity : .opacity.combined(with: .move(edge: .top)))
            }
        }
        .appleGroupedCard(cornerRadius: 18)
        .clipped()
        .onAppear {
            if alwaysExpanded || isExpanded {
                logStore.setExpanded(true)
            }
        }
        .onDisappear {
            logStore.setExpanded(false)
        }
    }

    private var headerLabel: some View {
        HStack(spacing: 8) {
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
        withAnimation(AppleMotion.adaptive(AppleMotion.fluidSpring, reduceMotion: reduceMotion)) {
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

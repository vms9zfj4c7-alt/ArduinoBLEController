import SwiftUI

/// Console de logs BLE pliable (émissions, réceptions et envoi de commandes manuelles).
struct LogConsoleView: View {
    @ObservedObject var logStore: BLELogStore
    let isConnected: Bool
    let onSendRawCommand: (String) -> Void
    let onClearLogs: () -> Void

    @State private var isExpanded: Bool = false
    @State private var rawCommandText: String = ""

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Button(action: toggleExpanded) {
                    HStack(spacing: 10) {
                        Image(systemName: "terminal.fill")
                            .foregroundStyle(Color.accentColor)
                        Text("Console BLE")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.primary)

                        Text("\(logStore.totalCount)")
                            .font(.caption2.weight(.bold).monospacedDigit())
                            .padding(.horizontal, 7)
                            .padding(.vertical, 2)
                            .background(Color.secondary.opacity(0.2))
                            .clipShape(Capsule())

                        Spacer()
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                if isExpanded && logStore.totalCount > 0 {
                    Button("Effacer", role: .destructive) {
                        onClearLogs()
                    }
                    .font(.caption.weight(.semibold))
                    .buttonStyle(.borderless)
                }

                Button(action: toggleExpanded) {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.up")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.secondary)
                        .padding(.leading, 4)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)

            if isExpanded {
                Divider()

                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 4) {
                            if logStore.entries.isEmpty {
                                Text("Aucun échange BLE enregistré pour le moment.")
                                    .font(.caption.monospaced())
                                    .foregroundStyle(.secondary)
                                    .padding(.vertical, 16)
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
                    .frame(height: 150)
                    .background(Color(.systemBackground).opacity(0.6))
                    .onChange(of: logStore.entries.last?.id) { lastID in
                        if let lastID {
                            proxy.scrollTo(lastID, anchor: .bottom)
                        }
                    }
                }

                Divider()

                HStack(spacing: 8) {
                    TextField("Commande brute (ex: I?, D:13:1, PING)", text: $rawCommandText)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 13, design: .monospaced))
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                        .onSubmit {
                            submitRawCommand()
                        }

                    Button("Envoyer") {
                        submitRawCommand()
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .disabled(!isConnected || rawCommandText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                .padding(10)
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(.secondarySystemBackground))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(Color(.separator).opacity(0.4), lineWidth: 1)
        )
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
        rawCommandText = ""
        onSendRawCommand(trimmed)
    }

    private func toggleExpanded() {
        withAnimation(.easeInOut(duration: 0.2)) {
            isExpanded.toggle()
        }
        logStore.setExpanded(isExpanded)
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

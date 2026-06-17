import SwiftUI

struct OnboardingView: View {
    @EnvironmentObject private var session: WatchViewState
    @StateObject private var bridge = WatchBridgeClient.shared

    @State private var code = ""
    @State private var ipAddress = ""
    @State private var isSearching = false
    @State private var isConnecting = false
    @State private var error: String?
    @State private var bridgeURL: URL?
    @FocusState private var codeFocused: Bool
    @FocusState private var ipFocused: Bool

    var body: some View {
        VStack(spacing: 6) {
            // Compact header — one line
            HStack(spacing: 4) {
                AppLogo(size: 22)
                Text("Agent Watch")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(Theme.Text.primary)
            }

            if isSearching {
                Spacer()
                ProgressView()
                    .tint(Theme.Text.secondary)
                Text("Searching...")
                    .font(.system(size: 11))
                    .foregroundColor(Theme.Text.secondary)
                Spacer()

            } else if bridgeURL != nil {
                // Bridge found — code entry
                Text("Enter code from Mac")
                    .font(.system(size: 11))
                    .foregroundColor(Theme.Text.secondary)

                TextField("000000", text: $code)
                    .font(.system(size: 22, weight: .bold, design: .monospaced))
                    .foregroundColor(Theme.Text.primary)
                    .multilineTextAlignment(.center)
                    .textContentType(.oneTimeCode)
                    .focused($codeFocused)
                    .onChange(of: code) { _, newValue in
                        let filtered = String(newValue.filter { $0.isNumber }.prefix(6))
                        if filtered != newValue { code = filtered }
                        if filtered.count == 6 { submitCode(filtered) }
                    }

                if isConnecting {
                    ProgressView()
                        .tint(Theme.Text.primary)
                        .scaleEffect(0.7)
                }

            } else {
                // Not found — manual entry: LAN IP or a public tunnel URL
                Text("Enter IP or tunnel URL")
                    .font(.system(size: 11))
                    .foregroundColor(Theme.Text.secondary)

                Text("LAN IP, or paste the https tunnel URL")
                    .font(.system(size: 9))
                    .foregroundColor(Theme.Text.dimmed)

                TextField("192.168.1.x or xxx.trycloudflare.com", text: $ipAddress)
                    .font(.system(size: 16, weight: .bold, design: .monospaced))
                    .foregroundColor(Theme.Text.primary)
                    .multilineTextAlignment(.center)
                    .focused($ipFocused)

                Button { connectManual() } label: {
                    Text("Connect")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.black)
                        .frame(maxWidth: .infinity)
                        .frame(height: 36)
                        .background(Theme.Text.primary)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain)
                .disabled(ipAddress.isEmpty)

                Button("Retry auto") { searchForBridge() }
                    .font(.system(size: 10))
                    .foregroundColor(Theme.Text.secondary)
            }

            if let error {
                Text(error)
                    .font(.system(size: 10))
                    .foregroundColor(Theme.Accent.error)
                    .lineLimit(2)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.Background.primary)
        .onAppear {
            searchForBridge()
        }
    }

    private func connectManual() {
        let raw = ipAddress.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty else { return }
        isSearching = true
        error = nil

        Task {
            // Full URL or DNS hostname (e.g. a cloudflared tunnel) → connect directly.
            if let base = Self.directBaseURL(from: raw) {
                if await Self.probe(base) {
                    await MainActor.run {
                        isSearching = false
                        bridgeURL = base
                        codeFocused = true
                    }
                } else {
                    await MainActor.run {
                        isSearching = false
                        self.error = "Can't reach \(base.host ?? raw)"
                    }
                }
                return
            }

            // Bare IP → scan the LAN port range over http.
            for port in 7860...7869 {
                let base = URL(string: "http://\(raw):\(port)")!
                if await Self.probe(base) {
                    await MainActor.run {
                        isSearching = false
                        bridgeURL = base
                        codeFocused = true
                    }
                    return
                }
            }
            await MainActor.run {
                isSearching = false
                self.error = "Can't reach \(raw)"
            }
        }
    }

    /// A base URL when the input is a full URL or a DNS hostname (tunnel),
    /// or nil when it's a bare IP that still needs a LAN port scan.
    private static func directBaseURL(from raw: String) -> URL? {
        if raw.hasPrefix("http://") || raw.hasPrefix("https://") {
            let trimmed = raw.hasSuffix("/") ? String(raw.dropLast()) : raw
            return URL(string: trimmed)
        }
        // Hostnames contain letters; bare IPv4 addresses are digits and dots only.
        if raw.contains(where: { $0.isLetter }) {
            return URL(string: "https://\(raw)")
        }
        return nil
    }

    /// True when `<base>/status` answers 200.
    private static func probe(_ base: URL) async -> Bool {
        var request = URLRequest(url: base.appendingPathComponent("status"))
        request.timeoutInterval = 4
        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            return (response as? HTTPURLResponse)?.statusCode == 200
        } catch {
            return false
        }
    }

    private func searchForBridge() {
        isSearching = true
        error = nil
        Task {
            let url = await bridge.discover()
            await MainActor.run {
                isSearching = false
                bridgeURL = url
                if url != nil { codeFocused = true }
                else { ipFocused = true }
            }
        }
    }

    private func submitCode(_ code: String) {
        guard let url = bridgeURL, !isConnecting else { return }
        isConnecting = true
        error = nil

        Task {
            do {
                try await bridge.pair(baseURL: url, code: code)
                await MainActor.run {
                    session.isPaired = true
                    session.sessionState = SessionState(
                        connection: .connected, activity: .idle,
                        machineName: "Mac", modelName: nil,
                        workingDirectory: nil,
                        elapsedSeconds: 0, filesChanged: 0, linesAdded: 0,
                        transportMode: .lan
                    )
                    session.appendLine(TerminalLine(text: "Connected to bridge", type: .system))
                    session.startEventStream()
                }
            } catch {
                await MainActor.run {
                    self.isConnecting = false
                    self.error = error.localizedDescription
                    self.code = ""
                }
            }
        }
    }
}

#Preview { OnboardingView().environmentObject(WatchViewState.shared) }

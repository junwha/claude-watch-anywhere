import SwiftUI

struct OnboardingView: View {
    @EnvironmentObject private var session: WatchViewState
    @StateObject private var bridge = WatchBridgeClient.shared

    @State private var code = ""
    @State private var ipAddress = ""
    @State private var isConnecting = false
    @State private var error: String?
    @State private var bridgeURL: URL?       // set by Bonjour (LAN fast path) or manual entry
    @State private var showManual = false
    @FocusState private var codeFocused: Bool
    @FocusState private var ipFocused: Bool

    private var hasRelay: Bool { WatchBridgeClient.relayURL != nil }

    var body: some View {
        VStack(spacing: 6) {
            HStack(spacing: 4) {
                AppLogo(size: 22)
                Text("Agent Watch")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(Theme.Text.primary)
            }

            if showManual {
                manualEntry
            } else {
                codeEntry
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
            discoverInBackground()
            codeFocused = true
        }
    }

    // MARK: - Code entry (primary path: just type the 6 digits)

    private var codeEntry: some View {
        VStack(spacing: 6) {
            Text(subtitle)
                .font(.system(size: 11))
                .foregroundColor(Theme.Text.secondary)
                .multilineTextAlignment(.center)

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
                ProgressView().tint(Theme.Text.primary).scaleEffect(0.7)
            }

            Button("Enter URL manually") { showManual = true; ipFocused = true }
                .font(.system(size: 10))
                .foregroundColor(Theme.Text.secondary)
        }
    }

    private var subtitle: String {
        if bridgeURL != nil { return "Bridge found — enter code" }
        if hasRelay { return "Enter the 6-digit code" }
        return "Enter code (searching LAN…)"
    }

    // MARK: - Manual entry (fallback: IP or tunnel URL)

    private var manualEntry: some View {
        VStack(spacing: 6) {
            Text("Enter IP or tunnel URL")
                .font(.system(size: 11))
                .foregroundColor(Theme.Text.secondary)

            TextField("192.168.1.x or xxx.trycloudflare.com", text: $ipAddress)
                .font(.system(size: 16, weight: .bold, design: .monospaced))
                .foregroundColor(Theme.Text.primary)
                .multilineTextAlignment(.center)
                .focused($ipFocused)

            Button { connectManual() } label: {
                Text(isConnecting ? "Connecting…" : "Connect")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.black)
                    .frame(maxWidth: .infinity).frame(height: 36)
                    .background(Theme.Text.primary)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            }
            .buttonStyle(.plain)
            .disabled(ipAddress.isEmpty || isConnecting)

            Button("Back to code") { showManual = false; codeFocused = true }
                .font(.system(size: 10))
                .foregroundColor(Theme.Text.secondary)
        }
    }

    // MARK: - Pairing

    /// Silently look for a LAN bridge via Bonjour; sets bridgeURL if found.
    private func discoverInBackground() {
        Task {
            if let url = await bridge.discover() {
                await MainActor.run { if bridgeURL == nil { bridgeURL = url } }
            }
        }
    }

    /// Pair using only the 6-digit code: LAN bridge first, then the relay.
    private func submitCode(_ code: String) {
        guard !isConnecting else { return }
        isConnecting = true
        error = nil

        Task {
            // 1. LAN bridge discovered via Bonjour.
            if let url = bridgeURL, await tryPair(url, code) { return }

            // 2. Resolve the code to the current public URL via the relay.
            do {
                if let url = try await bridge.resolve(code: code) {
                    if await tryPair(url, code) { return }
                    await fail("Found bridge but pairing failed — check the code")
                    return
                }
                // No relay configured and no LAN bridge reachable.
                await fail(bridgeURL == nil
                           ? "No bridge found. Tap “Enter URL manually”."
                           : "Pairing failed — check the code")
            } catch {
                await fail(error.localizedDescription)
            }
        }
    }

    private func connectManual() {
        let raw = ipAddress.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty, !isConnecting else { return }
        isConnecting = true
        error = nil

        Task {
            // Full URL or DNS hostname (e.g. a cloudflared tunnel) → connect directly.
            if let base = Self.directBaseURL(from: raw) {
                if await Self.probe(base) { await foundManual(base) }
                else { await fail("Can't reach \(base.host ?? raw)") }
                return
            }
            // Bare IP → scan the LAN port range over http.
            for port in 7860...7869 {
                let base = URL(string: "http://\(raw):\(port)")!
                if await Self.probe(base) { await foundManual(base); return }
            }
            await fail("Can't reach \(raw)")
        }
    }

    @MainActor private func foundManual(_ base: URL) {
        isConnecting = false
        bridgeURL = base
        showManual = false
        codeFocused = true
        error = nil
    }

    /// Returns true on success.
    private func tryPair(_ url: URL, _ code: String) async -> Bool {
        do {
            try await bridge.pair(baseURL: url, code: code)
            await MainActor.run { applyPaired() }
            return true
        } catch {
            return false
        }
    }

    @MainActor private func applyPaired() {
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

    @MainActor private func fail(_ msg: String) {
        isConnecting = false
        error = msg
        code = ""
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
}

#Preview { OnboardingView().environmentObject(WatchViewState.shared) }

import SwiftUI

/// How an agent looks everywhere in the app: a monogram in a colour derived
/// from its name. Never a company logo, since the names are the user's own.
enum AgentStyle {
    static let palette: [Color] = [.indigo, .teal, .orange, .pink, .mint, .purple, .cyan, .brown]

    /// Colours by the agents' order on the board, so the first eight agents
    /// never share a colour. (Hashing names collided: "muse", "duet" and
    /// "dots" all landed on the same one.)
    static func colors(for agents: [Agent]) -> [String: Color] {
        Dictionary(agents.enumerated().map { ($1.name, palette[$0 % palette.count]) }, uniquingKeysWith: { first, _ in first })
    }

    /// For a name the board doesn't list (a revoked agent): a stable FNV-1a hash.
    /// Not hashValue, which Swift randomises on every launch.
    static func fallbackColor(for name: String) -> Color {
        var hash: UInt32 = 2_166_136_261
        for byte in name.utf8 { hash = (hash ^ UInt32(byte)) &* 16_777_619 }
        return palette[Int(hash % UInt32(palette.count))]
    }

    /// "muse" → "Muse"; no agent → "Auto".
    static func displayName(_ name: String?) -> String {
        guard let name, !name.isEmpty else { return "Auto" }
        if name == "owner" { return "You" }
        return name.prefix(1).uppercased() + name.dropFirst()
    }
}

extension EnvironmentValues {
    @Entry var agentColors: [String: Color] = [:]
}

extension View {
    /// The colour an agent is drawn in, set once for the whole app from the board's agent list.
    func agentColors(_ agents: [Agent]) -> some View { environment(\.agentColors, AgentStyle.colors(for: agents)) }
}

struct AgentTint {
    let colors: [String: Color]
    func callAsFunction(_ name: String?) -> Color {
        guard let name else { return .secondary }
        return colors[name] ?? AgentStyle.fallbackColor(for: name)
    }
}

struct AgentAvatar: View {
    @Environment(\.agentColors) private var colors
    let name: String?
    var size: CGFloat = 28

    var body: some View {
        let tint = AgentTint(colors: colors)(name)
        ZStack {
            Circle().fill(tint.opacity(0.18))
            if let name {
                Text(name.prefix(1).uppercased())
                    .font(.system(size: size * 0.46, weight: .semibold, design: .rounded))
                    .foregroundStyle(tint)
            } else {
                Image(systemName: "sparkles")
                    .font(.system(size: size * 0.42, weight: .semibold))
                    .foregroundStyle(tint)
            }
        }
        .frame(width: size, height: size)
        .accessibilityLabel(AgentStyle.displayName(name))
    }
}

/// Plain-language presence, worked out from the board's call log. The point is
/// to set expectations before a message is sent, not apologise after.
enum Presence {
    static func seen(_ date: Date?, now: Date = .now) -> String {
        guard let date else { return "Hasn't checked in yet" }
        let s = now.timeIntervalSince(date)
        if s < 120 { return "Active now" }
        if s < 3600 { return "Active \(Int(s / 60))m ago" }
        if s < 86_400 { return "Active \(Int(s / 3600))h ago" }
        let days = Int(s / 86_400)
        return "Last seen \(days) day\(days == 1 ? "" : "s") ago"
    }

    static func pickup(_ seconds: Int?) -> String? {
        guard let seconds else { return nil }
        if seconds < 60 { return "usually picks up in under a minute" }
        if seconds < 3600 { return "usually picks up in ~\(max(1, Int((Double(seconds) / 60).rounded()))) min" }
        return "usually picks up in ~\(Int((Double(seconds) / 3600).rounded())) h"
    }

    static func summary(_ agent: Agent) -> String {
        [seen(agent.lastSeen), pickup(agent.typicalPickupSeconds)].compactMap { $0 }.joined(separator: " · ")
    }

    static func short(since date: Date, now: Date = .now) -> String {
        let s = max(0, now.timeIntervalSince(date))
        if s < 60 { return "just now" }
        if s < 3600 { return "\(Int(s / 60))m" }
        if s < 86_400 { return "\(Int(s / 3600))h" }
        return "\(Int(s / 86_400))d"
    }

    /// Quiet long enough that the user should be offered a nudge, reassign or cancel.
    static func isOverdue(since opened: Date, typical: Int?, now: Date = .now) -> Bool {
        let waited = now.timeIntervalSince(opened)
        guard let typical else { return waited > 30 * 60 }
        return waited > max(3 * Double(typical), 10 * 60)
    }

    /// Not seen for a day: worth a warning before sending it anything.
    static func isAsleep(_ agent: Agent?, now: Date = .now) -> Bool {
        guard let agent else { return false }
        guard let seen = agent.lastSeen else { return true }
        return now.timeIntervalSince(seen) > 86_400
    }
}

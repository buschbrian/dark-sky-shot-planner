import SkyCore
import SwiftUI

/// Go / marginal / no-go, always with the limiting factor, its value, source
/// and age (PLAN.md §Verdict), and where the conditions came from.
struct VerdictCard: View {
    let verdict: Verdict?
    let conditions: TonightModel.ConditionsState
    let refreshing: Bool
    let now: Date
    let showFactors: () -> Void
    let refresh: () -> Void
    @Environment(\.palette) private var palette

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let verdict {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(verdict.level.word)
                            .font(.title.bold())
                            .foregroundStyle(verdict.level.color(palette))
                        if !flagText(verdict).isEmpty {
                            Text(flagText(verdict))
                                .font(.subheadline)
                                .foregroundStyle(palette.secondary)
                        }
                    }
                    Text(limitingLine(verdict))
                        .foregroundStyle(palette.primary)
                    Text(provenanceLine(verdict.limiting, now: now))
                        .font(.footnote)
                        .foregroundStyle(palette.secondary)
                }
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("tonight.verdict")
            } else {
                Text("No verdict: the thresholds file could not be read.")
                    .foregroundStyle(palette.poor)
            }
            Text(originLine)
                .font(.footnote)
                .foregroundStyle(palette.secondary)
                .accessibilityIdentifier("tonight.conditionsOrigin")
            HStack {
                Button("Every factor", action: showFactors)
                    .buttonStyle(PaletteButtonStyle(palette: palette))
                    .disabled(verdict == nil)
                    .accessibilityHint("Shows every factor with its source and age")
                    .accessibilityIdentifier("tonight.factors")
                Button("Refresh", action: refresh)
                    .buttonStyle(PaletteButtonStyle(palette: palette))
                    .accessibilityHint("Fetches conditions again")
            }
        }
        .card(palette)
    }

    private func flagText(_ v: Verdict) -> String {
        var flags: [String] = []
        if v.flags.contains(.incompleteData) { flags.append("incomplete data") }
        if v.flags.contains(.staleData) { flags.append("stale data") }
        if v.flags.contains(.auroraPossible) { flags.append("aurora possible") }
        return flags.joined(separator: " · ")
    }

    private func limitingLine(_ v: Verdict) -> String {
        let f = v.limiting
        switch v.cause {
        case .rating:
            return "\(v.level == .go ? "Closest to its limit" : "Limited by") \(f.factor.label): \(FactorText.value(f))"
        case .incompleteData:
            return "\(f.factor.label) is unavailable\(FactorText.reason(f).map { " (\($0))" } ?? "")"
        case .staleData:
            return "\(f.factor.label) data is stale: \(FactorText.value(f))"
        }
    }

    private var originLine: String {
        switch conditions {
        case .idle, .loading:
            return "Conditions: fetching…"
        case .none(let reason):
            return "Conditions: \(reason)"
        case .loaded(let s, let cached):
            let age = Format.age(now.timeIntervalSince(s.fetchedUTC)).replacingOccurrences(of: " old", with: " ago")
            if cached {
                return refreshing
                    ? "Conditions: saved copy from \(age), refreshing…"
                    : "Conditions: offline, showing the copy fetched \(age)"
            }
            if s.response.isDirectFallback {
                return "Conditions: Worker unreachable, so clouds come straight from Open-Meteo; the other factors are unavailable"
            }
            return "Conditions: from the conditions Worker, fetched \(Format.clock(s.fetchedUTC, .current))"
        }
    }
}

/// Every factor with its value, rating, source and age, gating factors first.
struct FactorsSheet: View {
    let verdict: Verdict
    let now: Date
    @Environment(\.dismiss) private var dismiss
    @Environment(\.palette) private var palette
    @Environment(AppState.self) private var state

    private var ordered: [FactorAssessment] {
        verdict.factors.filter(\.gatesVerdict) + verdict.factors.filter { !$0.gatesVerdict }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Text("\(verdict.level.word): the worst factor that gates the verdict, over the moon-free dark window. Advisories are shown but never decide it.")
                        .font(.footnote)
                        .foregroundStyle(palette.secondary)
                    ForEach(ordered, id: \.key) { factor in
                        FactorRow(factor: factor, isLimiting: factor.key == verdict.limiting.key, now: now)
                    }
                }
                .padding()
            }
            .background(palette.background)
            .navigationTitle("Every factor")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(palette.background, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("Every factor").font(.headline).foregroundStyle(palette.primary)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(palette.accent)
                        .accessibilityIdentifier("factors.done")
                }
                .sharedBackgroundVisibility(state.fieldMode ? .hidden : .automatic)
            }
        }
        .presentationBackground(palette.background)
        .presentationDragIndicator(.hidden)
        .fieldSafe(state.fieldMode)
    }
}

private struct FactorRow: View {
    let factor: FactorAssessment
    let isLimiting: Bool
    let now: Date
    @Environment(\.palette) private var palette

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                Text(factor.factor.label)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(palette.primary)
                Spacer()
                Text(ratingText)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(palette.color(factor.rating))
            }
            Text(FactorText.value(factor))
                .foregroundStyle(factor.isUnavailable ? palette.secondary : palette.primary)
            if let reason = FactorText.reason(factor) {
                Text(reason).font(.footnote).foregroundStyle(palette.secondary)
            }
            Text(provenanceLine(factor, now: now))
                .font(.footnote)
                .foregroundStyle(palette.secondary)
            if factor.readings.count > 1 && !factor.isUnavailable {
                Text(FactorText.perModel(factor))
                    .font(.footnote)
                    .foregroundStyle(palette.secondary)
            }
            Text(factor.gatesVerdict ? "Gates the verdict" : "Advisory")
                .font(.caption)
                .foregroundStyle(palette.secondary)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.surface, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(isLimiting ? palette.accent : .clear, lineWidth: 1.5))
        .accessibilityElement(children: .combine)
        .accessibilityHint(isLimiting ? "Limiting factor" : "")
    }

    private var ratingText: String {
        switch factor.status {
        case .rated(let r): r.word
        case .shownOnly: "not rated"
        case .unavailable: "unavailable"
        }
    }
}

enum FactorText {
    /// The value with its unit and, when models disagree, their spread.
    static func value(_ f: FactorAssessment) -> String {
        guard let v = f.value else { return "unavailable" }
        var s = Format.value(v, unit: f.factor.unit)
        if let band = f.band, band.upperBound - band.lowerBound > 1e-9 {
            s += " (models \(Format.value(band.lowerBound, unit: f.factor.unit)) to \(Format.value(band.upperBound, unit: f.factor.unit)))"
        }
        return s
    }

    static func reason(_ f: FactorAssessment) -> String? {
        if case .unavailable(let reason) = f.status { reason } else { nil }
    }

    static func perModel(_ f: FactorAssessment) -> String {
        f.readings.map { r in
            let name = Format.model(r.model) ?? "value"
            if let v = r.value, case .unavailable = r.status {
                return "\(name) \(Format.value(v, unit: f.factor.unit)) (not used)"
            }
            if let v = r.value { return "\(name) \(Format.value(v, unit: f.factor.unit))" }
            return "\(name) unavailable"
        }.joined(separator: " · ")
    }
}

/// "HRRR via Open-Meteo · 2 h old · fresh"; on-device values say so.
func provenanceLine(_ f: FactorAssessment, now: Date) -> String {
    guard let p = f.provenance else { return "Source: none · unavailable" }
    if p.source.contains("on device") { return "Source: computed on this phone" }
    var parts = ["Source: " + (Format.model(p.model).map { "\($0) via \(p.source)" } ?? p.source)]
    if let asOf = p.asOfUTC { parts.append(Format.age(now.timeIntervalSince(asOf))) }
    parts.append(p.freshness.label)
    return parts.joined(separator: " · ")
}

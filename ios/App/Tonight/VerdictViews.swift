import SkyCore
import SwiftUI

/// Go / marginal / no-go, always with the limiting factor, its value, source
/// and age (PLAN.md §Verdict).
struct VerdictBlock: View {
    let verdict: Verdict?
    let now: Date
    let workerConfigured: Bool
    @Environment(\.palette) private var palette

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.s) {
            if let verdict {
                HStack(spacing: DS.Space.s) {
                    StatusBadge(level: StatusLevel(verdict.level), qualifier: qualifier(verdict), large: true)
                    if verdict.flags.contains(.auroraPossible) {
                        Label("Aurora possible", systemImage: "sparkles")
                            .font(.dsFootnote.weight(.semibold))
                            .foregroundStyle(palette.primary)
                    }
                }
                Text(FactorText.limiting(verdict, workerConfigured: workerConfigured))
                    .font(.dsBody)
                    .foregroundStyle(palette.primary)
                    .fixedSize(horizontal: false, vertical: true)
                ProvenanceChip(info: FactorText.source(verdict.limiting), now: now)
            } else {
                StatusBadge(level: .unavailable, large: true)
                Text("No verdict: the thresholds file could not be read.")
                    .font(.dsBody)
                    .foregroundStyle(palette.primary)
                ProvenanceChip(info: SourceInfo(source: "conditions-thresholds.json", freshness: .unavailable))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("tonight.verdict")
    }

    private func qualifier(_ v: Verdict) -> String? {
        if v.flags.contains(.incompleteData) { return "incomplete data" }
        if v.flags.contains(.staleData) { return "stale data" }
        return nil
    }
}

/// Every factor with its value, rating, source and age, gating factors first.
struct FactorsSheet: View {
    let verdict: Verdict
    let now: Date
    let workerConfigured: Bool
    @Environment(\.dismiss) private var dismiss
    @Environment(\.palette) private var palette

    private var gating: [FactorAssessment] { verdict.shownFactors.filter(\.gatesVerdict) }
    private var advisories: [FactorAssessment] { verdict.shownFactors.filter { !$0.gatesVerdict } }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: DS.Space.cardGap) {
                    StatusBadge(level: StatusLevel(verdict.level), large: true)
                    Text(verdict.headline.map { "\($0). Conditions don't matter tonight." }
                        ?? "The worst factor that gates the verdict, over the moon-free dark window. Advisories are shown but never decide it.")
                        .font(.dsFootnote)
                        .foregroundStyle(palette.secondary)
                    group("Gates the verdict", gating)
                    if !advisories.isEmpty { group("Advisory", advisories) }
                }
                .padding(DS.Space.screen)
            }
            .background(palette.background)
            .sheetChrome("Every factor", confirm: SheetAction(title: "Done", id: "factors.done") { dismiss() })
        }
        .presentationDragIndicator(.hidden)
        .sheetPresentation(palette)
    }

    private func group(_ title: String, _ factors: [FactorAssessment]) -> some View {
        VStack(alignment: .leading, spacing: DS.Space.s) {
            Text(title).eyebrow(palette).padding(.top, DS.Space.s)
            ForEach(factors, id: \.key) { factor in
                FactorRow(factor: factor, isLimiting: factor.key == verdict.limiting.key, now: now,
                          workerConfigured: workerConfigured)
            }
        }
    }
}

private struct FactorRow: View {
    let factor: FactorAssessment
    let isLimiting: Bool
    let now: Date
    let workerConfigured: Bool
    @Environment(\.palette) private var palette

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.xs) {
            HStack(alignment: .firstTextBaseline) {
                Text(factor.factor.label)
                    .font(.dsCallout.weight(.semibold))
                    .foregroundStyle(palette.primary)
                Spacer()
                HStack(spacing: DS.Space.xs) {
                    Image(systemName: ratingSymbol).imageScale(.small)
                    Text(ratingText)
                }
                .font(.dsFootnote.weight(.semibold))
                .foregroundStyle(palette.color(factor.rating))
            }
            if factor.value == nil {
                UnavailableValue(reason: FactorText.reason(factor, workerConfigured: workerConfigured))
            } else {
                Text(FactorText.value(factor))
                    .font(.dsMetric)
                    .foregroundStyle(palette.primary)
            }
            ProvenanceChip(info: FactorText.source(factor), now: now)
            if factor.readings.count > 1 || factor.readings.contains(where: \.isLastGood) {
                Text(FactorText.perModel(factor))
                    .font(.dsData)
                    .foregroundStyle(palette.tertiary)
            }
        }
        .padding(DS.Space.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.surface, in: RoundedRectangle(cornerRadius: DS.Radius.control + 2, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: DS.Radius.control + 2, style: .continuous)
            .strokeBorder(isLimiting ? palette.accent : .clear, lineWidth: DS.Stroke.focus))
        .accessibilityElement(children: .combine)
        .accessibilityHint(isLimiting ? "Limiting factor" : "")
    }

    private var ratingText: String {
        switch factor.status {
        case .rated(let r): r.word
        case .shownOnly: "not rated"
        case .unavailable: Voice.unavailable
        case .notApplicable: "not applicable"
        }
    }

    private var ratingSymbol: String {
        switch factor.status {
        case .rated(.good): StatusLevel.go.symbol
        case .rated(.marginal): StatusLevel.marginal.symbol
        case .rated(.poor): StatusLevel.noGo.symbol
        case .shownOnly: "info.circle"
        case .unavailable: "circle.dashed"
        case .notApplicable: "moon"
        }
    }
}

enum FactorText {
    /// The value with its unit and, when models disagree, their spread.
    static func value(_ f: FactorAssessment) -> String {
        guard let v = f.value else { return Voice.unavailable }
        var s = Format.value(v, unit: f.factor.unit)
        if let band = f.band, band.upperBound - band.lowerBound > 1e-9 {
            s += " (models \(Format.value(band.lowerBound, unit: f.factor.unit)) to \(Format.value(band.upperBound, unit: f.factor.unit)))"
        }
        return s
    }

    static func reason(_ f: FactorAssessment, workerConfigured: Bool) -> String? {
        if case .unavailable(let reason) = f.status { Voice.reason(reason, workerConfigured: workerConfigured) } else { nil }
    }

    /// The limiting factor, always next to the verdict (ios/AGENTS.md).
    static func limiting(_ v: Verdict, workerConfigured: Bool) -> String {
        let f = v.limiting
        switch v.cause {
        case .rating:
            return "\(v.level == .go ? "Closest to its limit" : "Limited by") \(f.factor.label): \(value(f))"
        case .incompleteData:
            return "\(f.factor.label) is unavailable\(reason(f, workerConfigured: workerConfigured).map { " (\($0))" } ?? "")"
        case .staleData:
            return "\(f.factor.label) is stale: \(value(f))"
        case .noMoonFreeDarkness:
            return v.reasonLine ?? "No moon-free darkness"
        }
    }

    static func source(_ f: FactorAssessment) -> SourceInfo {
        guard let p = f.provenance else { return SourceInfo(source: "no source", freshness: .unavailable) }
        return SourceInfo(p, lastGood: f.readings.contains(where: \.isLastGood) && f.value != nil && f.isUnavailable)
    }

    static func perModel(_ f: FactorAssessment) -> String {
        f.readings.map { r in
            let name = Format.model(r.model) ?? "value"
            if let v = r.value, case .unavailable = r.status {
                return "\(name) \(Format.value(v, unit: f.factor.unit)) (\(r.isLastGood ? Voice.lastGood : "not used"))"
            }
            if let v = r.value { return "\(name) \(Format.value(v, unit: f.factor.unit))" }
            return "\(name) \(Voice.unavailable)"
        }.joined(separator: " · ")
    }
}

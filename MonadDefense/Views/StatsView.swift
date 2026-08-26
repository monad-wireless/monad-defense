import Charts
import SwiftUI

struct StatsView: View {
    @Environment(StudyStore.self) private var store

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    activityChart
                    trackMastery
                    recentSessions
                    bankInfo
                }
                .padding()
            }
            .background(.background.secondary.opacity(0.4))
            .navigationTitle("Stats")
        }
    }

    private var activityChart: some View {
        let activity = store.activity(days: 42)
        return VStack(alignment: .leading, spacing: 10) {
            Label("Reviews — last 6 weeks", systemImage: "calendar")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
            Chart(activity) { day in
                BarMark(
                    x: .value("Day", day.id, unit: .day),
                    y: .value("Reviews", day.count)
                )
                .foregroundStyle(Theme.accent.gradient)
                .cornerRadius(2)
            }
            .frame(height: 140)
            .chartXAxis {
                AxisMarks(values: .stride(by: .weekOfYear)) { _ in
                    AxisGridLine()
                    AxisValueLabel(format: .dateTime.day().month(.abbreviated))
                }
            }
        }
        .padding(16)
        .background(.background, in: .rect(cornerRadius: 20))
    }

    private var trackMastery: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Mastery by track", systemImage: "chart.bar")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
            Chart(Track.allCases.filter { store.stats(for: $0).total > 0 }) { track in
                let stats = store.stats(for: track)
                BarMark(
                    x: .value("Mastery", stats.mastery * 100),
                    y: .value("Track", track.code)
                )
                .foregroundStyle(track.tint.gradient)
                .cornerRadius(4)
                .annotation(position: .trailing) {
                    Text("\(Int((stats.mastery * 100).rounded()))%")
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
            .chartXScale(domain: 0...100)
            .frame(height: CGFloat(Track.allCases.count) * 34)
        }
        .padding(16)
        .background(.background, in: .rect(cornerRadius: 20))
    }

    @ViewBuilder
    private var recentSessions: some View {
        let sessions = store.recentSessions
        if !sessions.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Label("Recent sessions", systemImage: "clock.arrow.circlepath")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                ForEach(sessions.prefix(8)) { result in
                    HStack {
                        Text(result.modeRaw)
                            .font(.subheadline)
                        if let track = result.trackRaw {
                            Text(track)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text("\(result.correct)/\(result.total)")
                            .font(.subheadline.monospacedDigit().weight(.semibold))
                            .foregroundStyle(
                                result.total > 0 && Double(result.correct) / Double(result.total) >= 0.7
                                    ? .green : .orange)
                        Text(result.date, format: .dateTime.day().month(.abbreviated))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 2)
                }
            }
            .padding(16)
            .background(.background, in: .rect(cornerRadius: 20))
        }
    }

    private var bankInfo: some View {
        let stats = store.overallStats
        return VStack(alignment: .leading, spacing: 6) {
            Label("Card bank", systemImage: "archivebox")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
            Text("\(store.bank.cards.count) cards · \(store.bank.decks.count) decks · \(stats.seen) seen")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text("bank \(store.bank.bankVersion) · compiled \(store.bank.generatedAt)")
                .font(.caption2.monospaced())
                .foregroundStyle(.tertiary)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.background, in: .rect(cornerRadius: 20))
    }
}

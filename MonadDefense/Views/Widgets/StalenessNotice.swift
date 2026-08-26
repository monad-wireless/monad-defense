import SwiftUI

// MARK: - StalenessNotice
//
// The card bank is compiled from the vault by an explicit command, not by an
// Xcode build phase. That keeps the build fast, offline and independent of the
// parent repo — but it means a bank can quietly fall behind the deck notes it
// came from.
//
// So the app states its content's age rather than hiding it. Silence below the
// threshold; one quiet line above it. Never a modal: a stale bank is still a
// usable bank, and interrupting a study session to say so would be worse than
// the staleness.

struct StalenessNotice: View {
    let ageInDays: Int?
    /// Days after which the notice appears at all.
    var threshold: Int = 14

    var body: some View {
        if let ageInDays, ageInDays >= threshold {
            Label {
                Text("Cards compiled \(ageInDays) days ago — run `edu deck compile` to refresh.")
                    .font(.caption)
            } icon: {
                Image(systemName: "clock.badge.exclamationmark")
            }
            .foregroundStyle(.secondary)
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.background.secondary, in: .rect(cornerRadius: 12))
        }
    }
}

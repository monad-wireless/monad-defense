import SwiftUI

/// Dispatch a widget id to its native view. The id set is
/// `monad_knowledge/edu/guide.py:WIDGETS`; the decks implement the same ids in
/// Vue. An id this build does not know renders as a placeholder, so a guide
/// compiled by a newer pipeline degrades instead of failing.
struct GuideWidgetView: View {
    let ref: GuideWidgetRef

    var body: some View {
        switch ref.id {
        case "saturation": SaturationWidget()
        case "octaves": OctavesWidget()
        case "wave-phase": WavePhaseWidget()
        case "phasor": PhasorWidget(initialMode: ref.string("mode") ?? "sum")
        case "spread": SpreadWidget(windows: ref.string("preset") == "windows")
        case "gaussian": GaussianWidget()
        case "count-dist": CountDistWidget(devices: ref.string("preset") == "devices")
        case "bayes-grid": BayesGridWidget()
        case "rank-2d": Rank2DWidget()
        case "equivalence": EquivalenceWidget(preset: ref.string("preset") ?? "trigger")
        case "multipath": MultipathWidget()
        case "impairments": ImpairmentsWidget(initialView: ref.string("view") ?? "raw")
        case "phasor-power": PhasorPowerWidget()
        case "response": ResponseWidget(initialView: ref.string("view") ?? "level")
        case "spectral": SpectralWidget()
        case "pooling": PoolingWidget()
        case "scale-symmetry": ScaleSymmetryWidget()
        case "anchor-family": AnchorFamilyWidget()
        case "anchor-rank": AnchorRankWidget()
        case "null-space": NullSpaceWidget()
        case "coverage-greedy": CoverageGreedyWidget()
        case "path-loss": PathLossWidget()
        case "scores": ScoresWidget()
        case "support-posterior": SupportPosteriorWidget()
        case "continuity-room": ContinuityRoomWidget()
        case "correlated-receivers": CorrelatedReceiversWidget()
        case "resolution": ResolutionWidget()
        case "conformal-rank": ConformalRankWidget()
        default:
            Label("This widget (\(ref.id)) needs a newer app build.", systemImage: "puzzlepiece")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }
}

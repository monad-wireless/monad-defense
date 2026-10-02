import Foundation

// MARK: - The thesis models behind the guide widgets
//
// A line-by-line port of `publications/thesis-math/components/models.js`, which
// `tools/check_models.mjs` asserts against the companion notebook's pinned
// results (notebooks/studies/2026-09-10-calibration-identifiability). Keep the
// two files in step: a widget default on the phone must print the number the
// thesis prints. Pure functions, no SwiftUI.

enum GuideMath {
    static let ln2 = log(2.0)

    // MARK: Response model (thesis Eq. 3.1, reduced form of §3.9)

    /// L(N) = b + ½ log₂[1 + A(1 − e^(−sN/K))], in octaves.
    static func level(_ n: Double, A: Double, K: Double, b: Double = 0, s: Double = 1) -> Double {
        b + 0.5 * log2(1 + A * -expm1(-s * n / K))
    }

    /// dL/dN at fixed movement.
    static func levelSlope(_ n: Double, A: Double, K: Double, s: Double = 1) -> Double {
        let e = exp(-s * n / K)
        return A * e * s / (2 * ln2 * K * (1 + A * (1 - e)))
    }

    static func variability(_ n: Double, V0: Double, A: Double, K: Double) -> Double {
        V0 + A * -expm1(-n / K)
    }

    static func variabilitySlope(_ n: Double, A: Double, K: Double) -> Double {
        A * exp(-n / K) / K
    }

    /// Sensitivity of L to θ = (b, log A, log K), as in the companion notebook.
    static func sensitivityRow(_ n: Double, A: Double, K: Double) -> [Double] {
        let e = exp(-n / K)
        let den = 1 + A * (1 - e)
        return [1, A * (1 - e) / (2 * ln2 * den), -A * e * (n / K) / (2 * ln2 * den)]
    }

    /// The amplitude that puts the curve with knee K through one positive anchor.
    static func amplitudeThroughAnchor(_ K: Double, Na: Double = 3, La: Double = 1.12, b: Double = 0) -> Double {
        expm1(2 * ln2 * (La - b)) / -expm1(-Na / K)
    }

    static func geomspace(_ a: Double, _ b: Double, _ n: Int) -> [Double] {
        (0..<n).map { exp(log(a) + (log(b) - log(a)) * Double($0) / Double(n - 1)) }
    }

    /// The declared knee range of the thesis: 161 log-spaced values, 0.5–20 people.
    static let kneeGrid = geomspace(0.5, 20, 161)

    /// The anchor designs of thesis Table 3.4 and Fig. 3.5 (A = 4, K = 3).
    static let anchorDesigns: [(name: String, counts: [Double])] = [
        ("empty only", [0, 0, 0]),
        ("+1 positive", [0, 3, 3]),
        ("nearby", [0, 2, 3]),
        ("staircase", [0, 2, 4, 6, 8]),
    ]

    // MARK: Linear algebra

    /// One-sided Jacobi (Hestenes) SVD. Working on J itself rather than JᵀJ keeps
    /// a near-zero singular value at the scale of rounding in J, so a repeated
    /// anchor row gives rank 2 exactly as numpy does.
    static func singularValues(_ J: [[Double]]) -> [Double] {
        guard let n = J.first?.count else { return [] }
        let m = J.count
        var U = J
        for _ in 0..<80 {
            var rotated = false
            for p in 0..<(n - 1) {
                for q in (p + 1)..<n {
                    var alpha = 0.0, beta = 0.0, gamma = 0.0
                    for i in 0..<m {
                        alpha += U[i][p] * U[i][p]
                        beta += U[i][q] * U[i][q]
                        gamma += U[i][p] * U[i][q]
                    }
                    if gamma == 0 || abs(gamma) <= 1e-15 * (alpha * beta).squareRoot() { continue }
                    rotated = true
                    let zeta = (beta - alpha) / (2 * gamma)
                    let t = (zeta >= 0 ? 1.0 : -1.0) / (abs(zeta) + (1 + zeta * zeta).squareRoot())
                    let c = 1 / (1 + t * t).squareRoot()
                    let s = c * t
                    for i in 0..<m {
                        let up = U[i][p], uq = U[i][q]
                        U[i][p] = c * up - s * uq
                        U[i][q] = s * up + c * uq
                    }
                }
            }
            if !rotated { break }
        }
        return (0..<n).map { j in (0..<m).reduce(0.0) { $0 + U[$1][j] * U[$1][j] }.squareRoot() }
            .sorted(by: >)
    }

    /// Numerical rank with numpy's default tolerance, s_max · max(m, n) · ε.
    static func numericalRank(_ J: [[Double]]) -> Int {
        let s = singularValues(J)
        guard let top = s.first else { return 0 }
        let tol = top * Double(max(J.count, J[0].count)) * Double.ulpOfOne
        return s.filter { $0 > tol }.count
    }

    // MARK: Probability

    static func normPdf(_ x: Double, mu: Double = 0, sd: Double = 1) -> Double {
        exp(-0.5 * pow((x - mu) / sd, 2)) / (sd * (2 * Double.pi).squareRoot())
    }

    static func normCdf(_ x: Double) -> Double { 0.5 * erfc(-x / 2.0.squareRoot()) }

    /// Inverse standard normal CDF: Acklam's approximation and one Newton step.
    static func normPpf(_ p: Double) -> Double {
        let a = [-3.969683028665376e1, 2.209460984245205e2, -2.759285104469687e2, 1.38357751867269e2, -3.066479806614716e1, 2.506628277459239]
        let b = [-5.447609879822406e1, 1.615858368580409e2, -1.556989798598866e2, 6.680131188771972e1, -1.328068155288572e1]
        let c = [-7.784894002430293e-3, -3.223964580411365e-1, -2.400758277161838, -2.549732539343734, 4.374664141464968, 2.938163982698783]
        let d = [7.784695709041462e-3, 3.224671290700398e-1, 2.445134137142996, 3.754408661907416]
        let pl = 0.02425
        var x: Double
        if p < pl {
            let q = (-2 * log(p)).squareRoot()
            x = (((((c[0] * q + c[1]) * q + c[2]) * q + c[3]) * q + c[4]) * q + c[5]) / ((((d[0] * q + d[1]) * q + d[2]) * q + d[3]) * q + 1)
        } else if p <= 1 - pl {
            let q = p - 0.5, r = q * q
            x = (((((a[0] * r + a[1]) * r + a[2]) * r + a[3]) * r + a[4]) * r + a[5]) * q / (((((b[0] * r + b[1]) * r + b[2]) * r + b[3]) * r + b[4]) * r + 1)
        } else {
            let q = (-2 * log(1 - p)).squareRoot()
            x = -(((((c[0] * q + c[1]) * q + c[2]) * q + c[3]) * q + c[4]) * q + c[5]) / ((((d[0] * q + d[1]) * q + d[2]) * q + d[3]) * q + 1)
        }
        let e = normCdf(x) - p
        let u = e * (2 * Double.pi).squareRoot() * exp(x * x / 2)
        return x - u / (1 + x * u / 2)
    }

    static func poissonPmf(_ k: Int, _ lambda: Double) -> Double {
        if lambda <= 0 { return k == 0 ? 1 : 0 }
        return exp(Double(k) * log(lambda) - lambda - lgamma(Double(k) + 1))
    }

    /// Negative binomial with mean μ and dispersion φ: Var = μ + μ²/φ (the NB2 form).
    static func negBinPmf(_ k: Int, mu: Double, phi: Double) -> Double {
        if mu <= 0 { return k == 0 ? 1 : 0 }
        let p = phi / (phi + mu)
        let kd = Double(k)
        return exp(lgamma(kd + phi) - lgamma(phi) - lgamma(kd + 1) + phi * log(p) + kd * log(1 - p))
    }

    // MARK: Support sensitivity (thesis §6.1.1)

    /// Posterior over 0…maxCount when the observation equals the three-person
    /// anchor and the knee is averaged over the declared grid. σ = 0.23 octaves
    /// is the companion notebook's illustrative noise.
    static func conditionalPmf(maxCount: Int, geometric: Bool, sigma: Double = 0.23, Na: Double = 3, La: Double = 1.12) -> [Double] {
        let amps = kneeGrid.map { amplitudeThroughAnchor($0, Na: Na, La: La) }
        var p: [Double] = []
        for n in 0...maxCount {
            var like = 0.0
            for (i, k) in kneeGrid.enumerated() {
                like += normPdf(La, mu: level(Double(n), A: amps[i], K: k), sd: sigma)
            }
            like /= Double(kneeGrid.count)
            let prior = geometric ? 0.2 * pow(0.8, Double(n)) : 1
            p.append(like * prior)
        }
        let z = p.reduce(0, +)
        return p.map { $0 / z }
    }

    struct PmfSummary {
        let mean: Double
        let lo: Int
        let hi: Int
    }

    static func summary(_ p: [Double]) -> PmfSummary {
        var mean = 0.0, cdf = 0.0
        var lo: Int?, hi: Int?
        for (n, v) in p.enumerated() {
            mean += Double(n) * v
            cdf += v
            if lo == nil, cdf >= 0.05 { lo = n }
            if hi == nil, cdf >= 0.95 { hi = n }
        }
        return PmfSummary(mean: mean, lo: lo ?? 0, hi: hi ?? p.count - 1)
    }

    // MARK: Resolution and horizon (thesis Eqs. 6.6–6.8)

    /// The companion notebook's planning scenario: A = 4, K = 3, observation SD
    /// 0.05 octaves, Σ₀ = diag(0.03², 0.10², 0.15²), Q = diag(0.01², 0.02², 0.03²)
    /// per hour, target full width 2 people at 90 %.
    struct Plan {
        var A = 4.0
        var K = 3.0
        var sigma = 0.05
        var s0 = [0.03, 0.10, 0.15]
        var q = [0.01, 0.02, 0.03]
        var target = 2.0
        var coverage = 0.9
    }

    struct Resolution {
        let width: Double
        let budget: Double
        /// nil when the target is missed at calibration (B < 0); +∞ with no drift.
        let horizon: Double?
        let slope: Double
        let calib: Double
        let drift: Double
        let z: Double
    }

    static func resolution(_ n: Double, hours: Double, plan: Plan = Plan()) -> Resolution {
        let J = sensitivityRow(n, A: plan.A, K: plan.K)
        let calib = (0..<3).reduce(0.0) { $0 + J[$1] * J[$1] * plan.s0[$1] * plan.s0[$1] }
        let drift = (0..<3).reduce(0.0) { $0 + J[$1] * J[$1] * plan.q[$1] * plan.q[$1] }
        let slope = levelSlope(n, A: plan.A, K: plan.K)
        let z = normPpf(1 - (1 - plan.coverage) / 2)
        let v0 = plan.sigma * plan.sigma + calib
        let width = 2 * z * (v0 + hours * drift).squareRoot() / slope
        let budget = pow(plan.target * slope / (2 * z), 2) - v0
        let horizon: Double? = budget > 0 ? (drift > 0 ? budget / drift : .infinity) : nil
        return Resolution(width: width, budget: budget, horizon: horizon, slope: slope, calib: calib, drift: drift, z: z)
    }

    // MARK: Small utilities

    /// Split-conformal rank ⌈(m + 1)(1 − α)⌉, finite only when it is ≤ m.
    static func conformalRank(m: Int, alpha: Double) -> (rank: Int, finite: Bool) {
        let level = (1 - alpha) * 100
        let r = Int((Double(m + 1) * level.rounded() / 100 - 1e-12).rounded(.up))
        return (r, r <= m)
    }

    /// Variance of the mean of n equally correlated errors relative to one, and the effective n.
    static func correlatedMean(n: Int, rho: Double) -> (factor: Double, nEff: Double) {
        let f = (1 + Double(n - 1) * rho) / Double(n)
        return (f, 1 / f)
    }
}

/// Seeded uniform generator (mulberry32, as in the decks), so one setting shows one draw.
struct SeededRandom {
    private var state: UInt32

    init(seed: UInt32) { state = seed }

    mutating func uniform() -> Double {
        state = state &+ 0x6D2B_79F5
        var t = state
        t = (t ^ (t >> 15)) &* (t | 1)
        t ^= t &+ ((t ^ (t >> 7)) &* (t | 61))
        return Double(t ^ (t >> 14)) / 4_294_967_296
    }

    mutating func normal() -> Double {
        let u1 = max(uniform(), 1e-12)
        return (-2 * log(u1)).squareRoot() * cos(2 * Double.pi * uniform())
    }
}

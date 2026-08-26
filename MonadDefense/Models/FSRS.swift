import Foundation

// MARK: - FSRS-5 scheduler (no dependencies)
//
// Free Spaced Repetition Scheduler, default parameter vector, desired
// retention 0.9. Reference: open-spaced-repetition FSRS-5.

enum FSRSRating: Int, CaseIterable, Codable {
    case again = 1, hard = 2, good = 3, easy = 4

    var label: String {
        switch self {
        case .again: "Again"
        case .hard: "Hard"
        case .good: "Good"
        case .easy: "Easy"
        }
    }
}

enum FSRSState: Int, Codable {
    case new = 0, learning = 1, review = 2, relearning = 3
}

struct FSRSSnapshot {
    var state: FSRSState
    var stability: Double
    var difficulty: Double
    var due: Date
    var lastReview: Date?
    var reps: Int
    var lapses: Int
    var learningStep: Int
}

enum FSRS {
    // FSRS-5 default weights.
    static let w: [Double] = [
        0.40255, 1.18385, 3.173, 15.69105, 7.1949, 0.5345, 1.4604, 0.0046,
        1.54575, 0.1192, 1.01925, 1.9395, 0.11, 0.29605, 2.2698, 0.2315,
        2.9898, 0.51655, 0.6621,
    ]
    static let desiredRetention = 0.9
    static let decay = -0.5
    static let factor: Double = pow(0.9, 1.0 / -0.5) - 1.0  // 19/81

    static let learningSteps: [TimeInterval] = [60, 10 * 60]
    static let relearningSteps: [TimeInterval] = [10 * 60]
    static let maxIntervalDays = 365.0

    static func retrievability(elapsedDays: Double, stability: Double) -> Double {
        guard stability > 0 else { return 0 }
        return pow(1 + factor * elapsedDays / stability, decay)
    }

    static func interval(forStability stability: Double) -> Double {
        let days = stability / factor * (pow(desiredRetention, 1 / decay) - 1)
        return min(max(days.rounded(), 1), maxIntervalDays)
    }

    static func initialStability(_ rating: FSRSRating) -> Double {
        max(w[rating.rawValue - 1], 0.1)
    }

    static func initialDifficulty(_ rating: FSRSRating) -> Double {
        let d = w[4] - exp(w[5] * Double(rating.rawValue - 1)) + 1
        return min(max(d, 1), 10)
    }

    static func nextDifficulty(_ difficulty: Double, rating: FSRSRating) -> Double {
        let delta = -w[6] * Double(rating.rawValue - 3)
        let damped = difficulty + delta * (10 - difficulty) / 9
        let target = initialDifficulty(.easy)
        let reverted = w[7] * target + (1 - w[7]) * damped
        return min(max(reverted, 1), 10)
    }

    static func recallStability(
        difficulty: Double, stability: Double, retrievability: Double, rating: FSRSRating
    ) -> Double {
        let hardPenalty = rating == .hard ? w[15] : 1
        let easyBonus = rating == .easy ? w[16] : 1
        let growth =
            exp(w[8]) * (11 - difficulty) * pow(stability, -w[9])
            * (exp(w[10] * (1 - retrievability)) - 1) * hardPenalty * easyBonus
        return stability * (1 + growth)
    }

    static func forgetStability(
        difficulty: Double, stability: Double, retrievability: Double
    ) -> Double {
        let s =
            w[11] * pow(difficulty, -w[12]) * (pow(stability + 1, w[13]) - 1)
            * exp(w[14] * (1 - retrievability))
        return min(max(s, 0.1), stability)
    }

    static func shortTermStability(_ stability: Double, rating: FSRSRating) -> Double {
        stability * exp(w[17] * (Double(rating.rawValue) - 3 + w[18]))
    }

    /// Advance a card's scheduling state for one review.
    static func review(_ s: FSRSSnapshot, rating: FSRSRating, now: Date = .now) -> FSRSSnapshot {
        var next = s
        next.reps += 1
        next.lastReview = now

        switch s.state {
        case .new:
            next.stability = initialStability(rating)
            next.difficulty = initialDifficulty(rating)
            if rating == .easy {
                next.state = .review
                next.due = now.addingTimeInterval(interval(forStability: next.stability) * 86400)
            } else {
                next.state = .learning
                next.learningStep = rating == .good ? 1 : 0
                let step = min(next.learningStep, learningSteps.count - 1)
                next.due = now.addingTimeInterval(learningSteps[step])
            }

        case .learning, .relearning:
            let steps = s.state == .learning ? learningSteps : relearningSteps
            next.difficulty = nextDifficulty(s.difficulty, rating: rating)
            next.stability = shortTermStability(max(s.stability, 0.1), rating: rating)
            switch rating {
            case .again:
                next.learningStep = 0
                next.due = now.addingTimeInterval(steps[0])
            case .hard:
                let step = min(s.learningStep, steps.count - 1)
                next.due = now.addingTimeInterval(steps[step] * 1.5)
            case .good:
                let step = s.learningStep + 1
                if step < steps.count {
                    next.learningStep = step
                    next.due = now.addingTimeInterval(steps[step])
                } else {
                    next.state = .review
                    next.learningStep = 0
                    next.due = now.addingTimeInterval(interval(forStability: next.stability) * 86400)
                }
            case .easy:
                next.state = .review
                next.learningStep = 0
                next.due = now.addingTimeInterval(interval(forStability: next.stability) * 86400)
            }

        case .review:
            let elapsed = max((now.timeIntervalSince(s.lastReview ?? now)) / 86400, 0)
            let r = retrievability(elapsedDays: elapsed, stability: s.stability)
            next.difficulty = nextDifficulty(s.difficulty, rating: rating)
            if rating == .again {
                next.lapses += 1
                next.stability = forgetStability(
                    difficulty: s.difficulty, stability: s.stability, retrievability: r)
                next.state = .relearning
                next.learningStep = 0
                next.due = now.addingTimeInterval(relearningSteps[0])
            } else {
                next.stability = recallStability(
                    difficulty: s.difficulty, stability: s.stability, retrievability: r,
                    rating: rating)
                var days = interval(forStability: next.stability)
                if rating == .hard { days = max(days * 0.8, 1).rounded() }
                next.due = now.addingTimeInterval(days * 86400)
            }
        }
        return next
    }

    /// Human preview of the interval each rating would produce ("10m", "3d").
    static func intervalPreview(_ s: FSRSSnapshot, rating: FSRSRating, now: Date = .now) -> String {
        let next = review(s, rating: rating, now: now)
        let seconds = next.due.timeIntervalSince(now)
        if seconds < 3600 { return "\(max(Int(seconds / 60), 1))m" }
        if seconds < 86400 { return "\(Int(seconds / 3600))h" }
        return "\(Int((seconds / 86400).rounded()))d"
    }
}

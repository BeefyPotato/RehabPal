struct SymptomEvaluator: Sendable {
    let reviewThreshold: Int

    nonisolated func needsPhysiotherapistReview(_ result: SymptomResult) -> Bool {
        result.discomfort >= reviewThreshold
            || result.difficulty >= reviewThreshold
            || result.catchingOrLocking
            || (result.increasedSinceStart && result.stiffness >= 4)
    }
}

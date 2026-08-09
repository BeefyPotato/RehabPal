import SwiftUI

struct WristAssessmentView: View {
    let state: AppState
    let useDemoFallback: Bool

    var body: some View {
        VStack(spacing: 24) {
            Text("Daily assessment")
                .font(.largeTitle.bold())
            Text("Fixed conditions every demo day")
                .font(.title2)
            InstructionMediaCard(kind: .wristAssessment)
            Text("Two attempts each: centre, forward, backward, left, and right.")
                .multilineTextAlignment(.center)
            Label(useDemoFallback ? "Demo fallback active" : "Live hand tracking", systemImage: "hand.raised")
                .foregroundStyle(useDemoFallback ? .orange : .green)
            Button("Complete fixed wrist checks") { _ = state.completeWristAssessment(AssessmentResult.fixture.wrist) }
            .buttonStyle(.borderedProminent)
            .controlSize(.extraLarge)
            Text("App-estimated movement measures; not clinical goniometer or strength measurements.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .padding(60)
    }
}

struct HandROMAssessmentView: View {
    let state: AppState
    let useDemoFallback: Bool
    let liveObservation: MovementObservation
    @State private var digitIndex = 0
    @State private var attempt = 1
    @State private var results: [HandDigit: DigitROMSummary] = [:]
    @State private var captureAccumulator = FingerROMCaptureAccumulator()
    @State private var recordedAttempts: [HandDigit: [FingerROMAttempt]] = [:]

    private var digit: HandDigit { HandDigit.allCases[digitIndex] }

    var body: some View {
        VStack(spacing: 22) {
            Text("Hand range of motion").font(.largeTitle.bold())
            InstructionMediaCard(kind: .fingerROM)
            Text(digit == .thumb ? "Touch your thumb toward your little finger, then return." : "Bend and straighten your \(digit.title.lowercased()) finger.")
                .font(.title2).multilineTextAlignment(.center)
            Text("\(digit.title) • Attempt \(attempt) of 2")
                .font(.headline).foregroundStyle(.secondary)
            ProgressView(value: Double(digitIndex * 2 + attempt), total: 10)
                .frame(maxWidth: 420)
            Label(useDemoFallback ? "Demo values active" : "HandTrackingProvider joint tracking", systemImage: "hand.raised")
                .foregroundStyle(useDemoFallback ? .orange : .green)
            Button("Capture full motion") { capture() }
                .buttonStyle(.borderedProminent).controlSize(.extraLarge)
            Text("App-estimated joint excursion for comparison; not a clinical goniometer measurement.")
                .font(.footnote).foregroundStyle(.secondary)
        }
        .padding(50)
        .onChange(of: liveObservation) { _, observation in
            guard !useDemoFallback, observation.isTracked, let sample = observation.digits[digit], sample.isTracked else { return }
            let angles = SIMD3<Float>(sample.mcpAngle, sample.pipAngle, sample.dipAngle)
            captureAccumulator.record(angles)
        }
    }

    private func capture() {
        if !useDemoFallback {
            let confidence = liveObservation.quality == .good ? 0.95 : 0.65
            guard let captured = captureAccumulator.finish(trackingConfidence: confidence) else { return }
            recordedAttempts[digit, default: []].append(captured)
        }
        if attempt == 1 { attempt = 2; return }
        var completedResults = results
        if useDemoFallback {
            completedResults[digit] = AssessmentResult.fixture.handROM[digit]
        } else {
            var session = HandROMAssessmentSession()
            for captured in recordedAttempts[digit, default: []] { _ = session.record(captured, for: digit) }
            completedResults[digit] = session.summary(for: digit)
        }
        results = completedResults
        attempt = 1
        if digitIndex < HandDigit.allCases.count - 1 {
            digitIndex += 1
        } else {
            _ = state.completeHandROMAssessment(completedResults)
        }
    }
}

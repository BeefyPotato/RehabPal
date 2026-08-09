import Charts
import SwiftUI

struct AfterCareReportView: View {
    enum Metric: String, CaseIterable { case wrist = "Wrist", hand = "Hand ROM" }
    let state: AppState
    @State private var metric: Metric = .wrist
    @State private var digit: HandDigit = .index

    private var report: AfterCareReport {
        AfterCareReport.make(history: state.history, assessment: state.assessmentResult ?? .fixture, gameplay: Array(state.exerciseResults.values), symptoms: state.symptomResult ?? .comfortable, reviewThreshold: state.prescription.symptomReviewThreshold)
    }

    private var chartPoints: [(Date, Double, Bool)] {
        var points = state.history.romSessions.map { session in
            (session.date, metric == .wrist ? Double(session.wristScore) : session.digitExcursions[digit, default: 0], false)
        }
        let today = metric == .wrist
            ? Double(state.assessmentResult?.wristControlScore ?? AssessmentResult.fixture.wristControlScore)
            : state.assessmentResult?.handROM[digit]?.totalExcursion ?? AssessmentResult.fixture.handROM[digit]!.totalExcursion
        points.append((.now, today, true))
        return points
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("Today’s progress").font(.largeTitle.bold())
                Picker("Metric", selection: $metric) {
                    ForEach(Metric.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }.pickerStyle(.segmented)
                if metric == .hand {
                    Picker("Finger", selection: $digit) {
                        ForEach(HandDigit.allCases, id: \.self) { Text($0.title).tag($0) }
                    }.pickerStyle(.segmented)
                }
                reportCard(metric == .wrist ? "Wrist control trend" : "\(digit.title) range trend") {
                    Chart(Array(chartPoints.enumerated()), id: \.offset) { _, point in
                        LineMark(x: .value("Date", point.0), y: .value("Measure", point.1))
                            .foregroundStyle(.teal)
                        PointMark(x: .value("Date", point.0), y: .value("Measure", point.1))
                            .foregroundStyle(point.2 ? .orange : .teal)
                            .symbolSize(point.2 ? 110 : 45)
                    }
                    .chartYScale(domain: 0...max(120, (chartPoints.map(\.1).max() ?? 100) + 10))
                    .frame(height: 240)
                    Text("The orange point is today. Earlier points are fixed demo history.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                reportCard("Today compared") {
                    if metric == .wrist {
                        metricRow("Baseline", report.assessment.baselineWristControl)
                        metricRow("Previous", report.assessment.previousWristControl)
                        metricRow("Today", report.assessment.currentWristControl)
                    } else if let summary = state.assessmentResult?.handROM[digit] ?? AssessmentResult.fixture.handROM[digit] {
                        metricRow("Total joint excursion", summary.isAvailable ? Int(summary.totalExcursion) : nil, suffix: "°")
                        metricRow("Consistency", summary.isAvailable ? Int(summary.consistency) : nil, suffix: "%")
                    }
                    Text(report.assessment.trackingNote).foregroundStyle(.secondary)
                }
                reportCard("Exercises") { Text("\(report.gameplay.completedExercises)/2 completed at the prescribed dose") }
                reportCard("Your check-in") {
                    Text("Discomfort \(report.patientReported.discomfort)/10 • Stiffness \(report.patientReported.stiffness)/10 • Difficulty \(report.patientReported.difficulty)/10")
                    if report.patientReported.reviewWithPhysiotherapist {
                        Label("Review with physiotherapist", systemImage: "person.crop.circle.badge.exclamationmark").foregroundStyle(.orange)
                    }
                }
                Text("App-estimated movement trends are for comparison only. RehabPal does not diagnose, measure strength, or change your prescription.")
                    .font(.footnote).foregroundStyle(.secondary)
                Button("Continue to RehabPal") { _ = state.viewReport() }
                    .buttonStyle(.borderedProminent).controlSize(.extraLarge)
            }.padding(50).frame(maxWidth: 820)
        }
    }

    private func metricRow(_ title: String, _ value: Int?, suffix: String = "") -> some View {
        HStack { Text(title); Spacer(); Text(value.map { "\($0)\(suffix)" } ?? "Unavailable").bold() }
    }

    private func reportCard<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) { Text(title).font(.title2.bold()); content() }
            .padding(22).frame(maxWidth: .infinity, alignment: .leading).glassBackgroundEffect()
    }
}

import SwiftUI

struct AfterCareReportView: View {
    let state: AppState

    private var report: AfterCareReport {
        AfterCareReport.make(
            history: state.history,
            assessment: state.assessmentResult ?? .fixture,
            gameplay: Array(state.exerciseResults.values),
            symptoms: state.symptomResult ?? .comfortable,
            reviewThreshold: state.prescription.symptomReviewThreshold
        )
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("After-care report").font(.largeTitle.bold())
                reportCard("Fixed assessment") {
                    metric("Wrist control", baseline: report.assessment.baselineWristControl, previous: report.assessment.previousWristControl, current: report.assessment.currentWristControl)
                    metric("Closure consistency", baseline: report.assessment.baselineClosureConsistency, previous: report.assessment.previousClosureConsistency, current: report.assessment.currentClosureConsistency)
                    Text(report.assessment.trackingNote).foregroundStyle(.secondary)
                }
                reportCard("Gameplay evidence") {
                    Text("\(report.gameplay.completedExercises)/2 exercises completed at the prescribed dose")
                }
                reportCard("Patient-reported check-in") {
                    Text("Discomfort \(report.patientReported.discomfort)/10 • Stiffness \(report.patientReported.stiffness)/10 • Difficulty \(report.patientReported.difficulty)/10")
                    if report.patientReported.reviewWithPhysiotherapist {
                        Label("Review with physiotherapist", systemImage: "person.crop.circle.badge.exclamationmark")
                            .foregroundStyle(.orange)
                    }
                }
                Text("Movement range is described for comparison only. RehabPal does not diagnose or change your prescription.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Button("I have viewed my report") { _ = state.viewReport() }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.extraLarge)
            }
            .padding(50)
            .frame(maxWidth: 800)
        }
    }

    private func metric(_ title: String, baseline: Int, previous: Int, current: Int?) -> some View {
        Text("\(title): baseline \(baseline) • previous \(previous) • today \(current.map(String.init) ?? "unavailable")")
    }

    private func reportCard<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.title2.bold())
            content()
        }
        .padding(22)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassBackgroundEffect()
    }
}

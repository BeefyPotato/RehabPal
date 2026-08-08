# RehabPal Demo Walkthrough

## Simulator / demo fallback

1. Open `RehabPal.xcodeproj`, select the `RehabPal` scheme, and run on Apple Vision Pro Simulator.
2. Confirm Home appears first with the Recovery Pet and streak; select **Start Daily Routine**.
3. Select **Not yet** at the medication check. Confirm the neutral reminder appears and exercises stay locked. Select **Yes, I have** to continue.
4. Open either exercise first. Read its seated safety introduction, then begin.
5. Balance Platform: use **Hold centre (demo tracking)** four times. The platform, ball, and target are RealityKit primitives.
6. Squeeze Buddy: use **Complete close–hold–open (demo tracking)** five times. Confirm the UI states that Vision Pro does not measure grip force.
7. Repeat with the opposite exercise order after **Reset Demo Day**; assessment must unlock only after the second exercise.
8. Complete both fixed assessment sections, then submit the symptom check.
9. Review the separate fixed-assessment, gameplay, and patient-reported report sections. Select **I have viewed my report**.
10. Feed the CC0 placeholder pet. Confirm **Full for today** prevents additional reward and celebrates stopping at the prescribed dose.
11. Select **Reset Demo Day** and confirm medication, exercises, assessment, symptoms, report, and pet reset while fixture history remains.

The orange **DEMO FALLBACK** disclosure means synthetic observations are entering the same wrist and squeeze detectors used by live hand tracking. It never bypasses `AppState` gates.

## Vision Pro device / live tracking

1. In **Demo settings**, turn off demo fallback and grant the hand-tracking permission requested by visionOS.
2. Keep the prescribed hand in view and remain seated. Balance uses the world-space wrist transform; Squeeze Buddy uses the thumb/index joint distance as one input to normalized closure.
3. Move through the directions shown by Balance Platform and perform close–hold–open repetitions around a physical stress ball for Squeeze Buddy.
4. Briefly hide the hand mid-repetition. Confirm **Hands temporarily not visible** appears and progress does not advance until valid samples resume.
5. Complete the assessment under the same fixed cues on each run. Tracking gaps reduce confidence and may make report comparison unavailable; the app does not invent values.

## Safety and product boundaries

- This prototype demonstrates clinician-prescribed exercises; it does not diagnose, prescribe medication, change targets, or replace a physiotherapist.
- Hand tracking estimates movement and does not measure grip force or clinical goniometer angles.
- No backend, account, persistence, analytics, or network service is used.

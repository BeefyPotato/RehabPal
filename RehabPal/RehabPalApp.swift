//
//  RehabPalApp.swift
//  RehabPal
//
//  Created by Event on 8/8/26.
//

import SwiftUI

@main
struct RehabPalApp: App {
    @State private var state: AppState
    @State private var handTracking: HandTrackingEngine
    @State private var session: RehabSessionCoordinator

    init() {
        let state = AppState()
        let tracking = HandTrackingEngine()
        _state = State(initialValue: state)
        _handTracking = State(initialValue: tracking)
        _session = State(initialValue: RehabSessionCoordinator(
            prescription: state.prescription,
            liveTracking: tracking
        ))
    }

    var body: some Scene {
        WindowGroup {
            ContentView(
                state: state,
                handTracking: handTracking,
                session: session
            )
        }

        ImmersiveSpace(id: RehabSessionCoordinator.immersiveSpaceID) {
            SharedRehabImmersiveView(session: session)
        }
        .immersionStyle(selection: .constant(.mixed), in: .mixed)
    }
}

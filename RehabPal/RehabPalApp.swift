//
//  RehabPalApp.swift
//  RehabPal
//
//  Created by Event on 8/8/26.
//

import SwiftUI

@main
struct RehabPalApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }

        ImmersiveSpace(id: RehabSessionCoordinator.immersiveSpaceID) {
            SharedRehabImmersiveView()
        }
        .immersionStyle(selection: .constant(.mixed), in: .mixed)
    }
}

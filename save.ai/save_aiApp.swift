//
//  save_aiApp.swift
//  save.ai
//
//  Created by Chris on 9/15/25.
//

import SwiftUI

@main
struct save_aiApp: App {
    var body: some Scene {
        WindowGroup {
            AssistantNativeContentView(progressStore: SaveMVPProgressStoreFactory.make())
        }
    }
}

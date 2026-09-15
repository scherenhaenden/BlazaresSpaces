//
//  BlazaresSpacesApp.swift
//  BlazaresSpaces
//
//  Created by Edward Flores on 15.09.26.
//

import SwiftUI

@main
struct BlazaresSpacesApp: App {
    @StateObject private var model = DiagnosticsViewModel()

    var body: some Scene {
        WindowGroup {
            DailyDriverDashboardView()
                .environmentObject(model)
        }
        .defaultSize(width: 980, height: 760)

        MenuBarExtra {
            MenuBarControllerView()
                .environmentObject(model)
        } label: {
            Label(model.workspaceName(model.workspaceManager.activeWorkspaceID), systemImage: "square.3.layers.3d")
        }
        .menuBarExtraStyle(.menu)

        Window("BlazaresSpaces Inspector", id: "inspector") {
            ContentView()
                .environmentObject(model)
        }
        .defaultSize(width: 900, height: 700)

        Window(WindowControlLabConstants.title, id: "window-control-lab") {
            WindowControlLabView()
        }
        .defaultSize(width: 760, height: 360)
    }
}

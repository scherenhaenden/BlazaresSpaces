//
//  BlazaresSpacesApp.swift
//  BlazaresSpaces
//
//  Created by Edward Flores on 15.09.26.
//

import SwiftUI

@main
struct BlazaresSpacesApp: App {
    @NSApplicationDelegateAdaptor(BlazaresSpacesAppDelegate.self) private var appDelegate
    @StateObject private var model = DiagnosticsViewModel()

    var body: some Scene {
        WindowGroup("BlazaresSpaces", id: "main") {
            VStack(spacing: 0) {
                AccessibilityPermissionBanner()
                BlazaresSpacesHomeView()
            }
            .environmentObject(model)
        }
        .defaultSize(width: 1040, height: 700)

        MenuBarExtra {
            CompactMenuBarView()
                .environmentObject(model)
        } label: {
            Label(model.workspaceName(model.workspaceManager.activeWorkspaceID), systemImage: "square.3.layers.3d")
        }
        .menuBarExtraStyle(.window)

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

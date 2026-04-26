import SwiftUI

@main
struct xRateApp: App {
    @State private var model = ConverterModel()

    var body: some Scene {
        WindowGroup("xRate") {
            ContentView(model: model)
                .frame(minWidth: 480, minHeight: 360)
        }
        .defaultSize(width: 560, height: 520)
        .commands {
            CommandGroup(after: .newItem) {
                Button("Add Currency…") {
                    NotificationCenter.default.post(name: .xrateShowAddSheet, object: nil)
                }
                .keyboardShortcut("n", modifiers: [.command])

                Button("Refresh Rates") {
                    NotificationCenter.default.post(name: .xrateRefresh, object: nil)
                }
                .keyboardShortcut("r", modifiers: [.command])
            }
        }
    }
}

extension Notification.Name {
    static let xrateShowAddSheet = Notification.Name("xrate.showAddSheet")
    static let xrateRefresh = Notification.Name("xrate.refresh")
}

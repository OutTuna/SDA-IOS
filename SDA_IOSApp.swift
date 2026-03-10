import SwiftUI
import SwiftData

@main
struct SDA_IOSApp: App {
    var sharedModelContainer: ModelContainer = {
        let schema = Schema([Item.self])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
        do { return try ModelContainer(for: schema, configurations: [config]) }
        catch { fatalError("Could not create ModelContainer: \(error)") }
    }()

    var body: some Scene {
        WindowGroup {
            BiometricGateView {
                ContentView()
            }
        }
        .modelContainer(sharedModelContainer)
    }
}

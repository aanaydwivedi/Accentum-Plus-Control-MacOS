import SwiftUI

@main
struct MyAppApp: App {
    @StateObject private var bluetoothManager = BluetoothManager()

    var body: some Scene {
        // Full independent window app (Split View layout)
        WindowGroup {
            ContentView()
                .environmentObject(bluetoothManager)
        }
        
        // Menu Bar Extra automatically inserts/removes itself based on connection status
        MenuBarExtra(
            isInserted: Binding(
                get: { bluetoothManager.isConnected },
                set: { _ in }
            )
        ) {
            MenuBarView()
                .environmentObject(bluetoothManager)
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "headphones")
                if let battery = bluetoothManager.batteryLevel {
                    Text("\(battery)%")
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                }
            }
        }
        .menuBarExtraStyle(.window)
    }
}

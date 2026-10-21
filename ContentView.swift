import SwiftUI

struct ContentView: View {
    @EnvironmentObject var btManager: BluetoothManager
    @State private var selectedTab: SidebarItem? = .noiseControl
    
    enum SidebarItem: Hashable {
        case noiseControl, behavior
    }
    
    var body: some View {
        NavigationSplitView {
            List(selection: $selectedTab) {
                Section("Headphones") {
                    NavigationLink(value: SidebarItem.noiseControl) {
                        Label("Noise Control", systemImage: "earbuds")
                    }
                    NavigationLink(value: SidebarItem.behavior) {
                        Label("Behavior", systemImage: "switch.2")
                    }
                }
            }
            .listStyle(.sidebar)
        } detail: {
            if !btManager.isConnected {
                DisconnectedView()
            } else {
                switch selectedTab {
                case .noiseControl:
                    NoiseControlView()
                case .behavior:
                    BehaviorView()
                default:
                    Text("Select a category")
                }
            }
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                // Integrated single-layer status pill matching macOS HIG
                HStack(spacing: 8) {
                    if btManager.isConnected {
                        // Battery indicator
                        HStack(spacing: 4) {
                            Image(systemName: batteryIcon(for: btManager.batteryLevel ?? 100))
                                .foregroundColor(batteryColor(for: btManager.batteryLevel ?? 100))
                            Text(btManager.batteryLevel != nil ? "\(btManager.batteryLevel!)%" : "--%")
                                .font(.system(.body, design: .rounded).monospacedDigit())
                                .foregroundColor(.primary)
                        }
                        
                        Divider()
                            .frame(height: 12)
                        
                        // Status indicator
                        HStack(spacing: 5) {
                            Circle()
                                .fill(Color.green)
                                .frame(width: 8, height: 8)
                            Text("Connected")
                                .font(.system(.body, design: .rounded))
                                .foregroundColor(.primary)
                        }
                    } else {
                        HStack(spacing: 5) {
                            Circle()
                                .fill(Color.secondary)
                                .frame(width: 8, height: 8)
                            Text("Disconnected")
                                .font(.system(.body, design: .rounded))
                                .foregroundColor(.secondary)
                        }
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
            }
        }
        .frame(minWidth: 620, minHeight: 460)
    }
    
    private func batteryIcon(for level: Int) -> String {
        switch level {
        case 0..<20: return "battery.0percent"
        case 20..<50: return "battery.25percent"
        case 50..<80: return "battery.50percent"
        default: return "battery.100percent"
        }
    }
    
    private func batteryColor(for level: Int) -> Color {
        if level <= 20 { return .red }
        if level <= 40 { return .orange }
        return .green
    }
}

struct DisconnectedView: View {
    @EnvironmentObject var btManager: BluetoothManager
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "headphones")
                .font(.system(size: 60))
                .foregroundColor(.secondary)
            Text("No ACCENTUM Plus Connected")
                .font(.title2).fontWeight(.medium)
            Text("Ensure your headphones are paired in macOS System Settings.")
                .foregroundColor(.secondary)
            Button("Connect to Headphones") {
                btManager.connectToAccentumPlus()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

import SwiftUI

struct ContentView: View {
    @EnvironmentObject var btManager: BluetoothManager
    @State private var selectedTab: SidebarItem? = .noiseControl
    
    enum SidebarItem: Hashable {
        case noiseControl, mySound, connectionManagement, behavior
    }
    
    var body: some View {
        NavigationSplitView {
            List(selection: $selectedTab) {
                Section("Headphones") {
                    NavigationLink(value: SidebarItem.noiseControl) {
                        Label("Noise Control", systemImage: "earbuds")
                    }
                    NavigationLink(value: SidebarItem.mySound) {
                        Label("My Sound", systemImage: "slider.vertical.3")
                    }
                    NavigationLink(value: SidebarItem.connectionManagement) {
                        Label("Connections", systemImage: "laptopcomputer.and.iphone")
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
                case .mySound:
                    MySoundView()
                case .connectionManagement:
                    ConnectionManagementView()
                case .behavior:
                    BehaviorView()
                default:
                    Text("Select a category")
                }
            }
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                // Generously padded native toolbar pill
                HStack(spacing: 8) {
                    if btManager.isConnected {
                        if let battery = btManager.batteryLevel {
                            HStack(spacing: 4) {
                                Image(systemName: batteryIcon(for: battery))
                                    .foregroundColor(batteryColor(for: battery))
                                    .imageScale(.medium)
                                Text("\(battery)%")
                                    .font(.system(size: 12, weight: .medium, design: .rounded).monospacedDigit())
                            }
                            
                            Divider()
                                .frame(height: 12)
                                .opacity(0.4)
                        }
                        
                        HStack(spacing: 6) {
                            Circle()
                                .fill(Color.green)
                                .frame(width: 8, height: 8)
                            Text("Connected")
                                .font(.system(size: 12, weight: .medium, design: .rounded))
                        }
                    } else {
                        HStack(spacing: 6) {
                            Circle()
                                .fill(Color.secondary)
                                .frame(width: 8, height: 8)
                            Text("Disconnected")
                                .font(.system(size: 12, weight: .medium, design: .rounded))
                                .foregroundColor(.secondary)
                        }
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 5)
            }
        }
        .frame(minWidth: 700, minHeight: 520)
    }
    
    private func batteryIcon(for level: Int) -> String {
        switch level {
        case ..<15: return "battery.0percent"
        case 15..<38: return "battery.25percent"
        case 38..<63: return "battery.50percent"
        case 63..<88: return "battery.75percent"
        default: return "battery.100percent"
        }
    }
    
    private func batteryColor(for level: Int) -> Color {
        if level <= 20 { return .red }
        if level <= 45 { return .orange }
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

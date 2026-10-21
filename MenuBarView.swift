import SwiftUI

struct MenuBarView: View {
    @EnvironmentObject var btManager: BluetoothManager
    @State private var selectedTab: MenuBarTab = .noiseControl
    
    enum MenuBarTab: Hashable {
        case noiseControl, mySound, connectionManagement, behavior
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Header Bar (Status & Battery)
            HStack(spacing: 8) {
                HStack(spacing: 6) {
                    Circle()
                        .fill(btManager.isConnected ? Color.green : Color.secondary)
                        .frame(width: 8, height: 8)
                    Text(btManager.isConnected ? btManager.deviceName : "Disconnected")
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                }
                
                Spacer()
                
                if btManager.isConnected {
                    if let battery = btManager.batteryLevel {
                        HStack(spacing: 4) {
                            Image(systemName: batteryIcon(for: battery))
                                .foregroundColor(batteryColor(for: battery))
                                .imageScale(.medium)
                            Text("\(battery)%")
                                .font(.system(size: 12, weight: .medium, design: .rounded).monospacedDigit())
                        }
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .padding(.bottom, 8)
            
            Divider()
                .opacity(0.4)
            
            // Main Content Area (Vertical & Compact)
            ZStack {
                if !btManager.isConnected {
                    MenuBarDisconnectedView()
                } else {
                    ScrollView {
                        VStack(spacing: 12) {
                            switch selectedTab {
                            case .noiseControl:
                                NoiseControlView()
                            case .mySound:
                                MySoundView()
                            case .connectionManagement:
                                ConnectionManagementView()
                            case .behavior:
                                BehaviorView()
                            }
                        }
                        .padding(12)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            
            // Bottom "Liquid Glass" Style Floating Navigation Bar
            HStack(spacing: 12) {
                MenuBarTabButton(icon: "earbuds", title: "Noise", isSelected: selectedTab == .noiseControl) {
                    selectedTab = .noiseControl
                }
                MenuBarTabButton(icon: "slider.vertical.3", title: "Sound", isSelected: selectedTab == .mySound) {
                    selectedTab = .mySound
                }
                MenuBarTabButton(icon: "laptopcomputer.and.iphone", title: "Devices", isSelected: selectedTab == .connectionManagement) {
                    selectedTab = .connectionManagement
                }
                MenuBarTabButton(icon: "switch.2", title: "Behavior", isSelected: selectedTab == .behavior) {
                    selectedTab = .behavior
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(.ultraThinMaterial)
            .cornerRadius(24)
            .shadow(color: Color.black.opacity(0.15), radius: 8, x: 0, y: 4)
            .padding(.horizontal, 14)
            .padding(.bottom, 12)
            .padding(.top, 6)
        }
        .frame(width: 380, height: 500)
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

struct MenuBarTabButton: View {
    let icon: String
    let title: String
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: 3) {
                Image(systemName: icon)
                    .font(.system(size: 15, weight: isSelected ? .semibold : .regular))
                Text(title)
                    .font(.system(size: 10, weight: isSelected ? .medium : .regular))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
            .background(isSelected ? Color.accentColor.opacity(0.2) : Color.clear)
            .foregroundColor(isSelected ? .accentColor : .secondary)
            .cornerRadius(12)
        }
        .buttonStyle(.plain)
    }
}

struct MenuBarDisconnectedView: View {
    @EnvironmentObject var btManager: BluetoothManager
    
    var body: some View {
        VStack(spacing: 14) {
            if btManager.isConnecting {
                ProgressView()
                    .scaleEffect(1.1)
                Text("Connecting...")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            } else {
                Image(systemName: "headphones")
                    .font(.system(size: 44))
                    .foregroundColor(.secondary)
                Text("No ACCENTUM Plus")
                    .font(.headline)
                Text("Turn on headphones or check macOS Bluetooth settings.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 20)
                
                Button("Connect") {
                    btManager.connectToAccentumPlus()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.regular)
                .padding(.top, 4)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            if !btManager.isConnected && !btManager.isConnecting {
                btManager.connectToAccentumPlus()
            }
        }
    }
}
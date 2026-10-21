import SwiftUI

struct MenuBarView: View {
    @EnvironmentObject var btManager: BluetoothManager
    @State private var selectedTab: Int = 0
    @State private var previousTab: Int = 0
    
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
            .padding(.horizontal, 10)
            .padding(.top, 12)
            .padding(.bottom, 6)
            
            Divider()
                .opacity(0.4)
            
            // Custom Directional Slide Container (Slightly faster duration: 0.22s)
            ZStack {
                if !btManager.isConnected {
                    MenuBarDisconnectedView()
                } else {
                    GeometryReader { proxy in
                        ZStack {
                            pageView(for: 0)
                                .offset(x: CGFloat(0 - selectedTab) * proxy.size.width)
                            pageView(for: 1)
                                .offset(x: CGFloat(1 - selectedTab) * proxy.size.width)
                            pageView(for: 2)
                                .offset(x: CGFloat(2 - selectedTab) * proxy.size.width)
                            pageView(for: 3)
                                .offset(x: CGFloat(3 - selectedTab) * proxy.size.width)
                        }
                        .animation(.easeInOut(duration: 0.22), value: selectedTab)
                    }
                    .clipped()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            
            // Bottom "Liquid Glass" Style Floating Navigation Bar
            HStack(spacing: 6) {
                MenuBarTabButton(icon: "earbuds", title: "Noise", isSelected: selectedTab == 0) {
                    switchToTab(0)
                }
                MenuBarTabButton(icon: "slider.vertical.3", title: "Sound", isSelected: selectedTab == 1) {
                    switchToTab(1)
                }
                MenuBarTabButton(icon: "laptopcomputer.and.iphone", title: "Devices", isSelected: selectedTab == 2) {
                    switchToTab(2)
                }
                MenuBarTabButton(icon: "switch.2", title: "Behavior", isSelected: selectedTab == 3) {
                    switchToTab(3)
                }
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 6)
            .background(.ultraThinMaterial)
            .cornerRadius(20)
            .shadow(color: Color.black.opacity(0.15), radius: 6, x: 0, y: 3)
            .padding(.horizontal, 10)
            .padding(.bottom, 10)
            .padding(.top, 4)
        }
        .frame(width: 340, height: 540)
    }
    
    @ViewBuilder
    private func pageView(for index: Int) -> some View {
        ScrollView {
            VStack(spacing: 8) {
                switch index {
                case 0: NoiseControlView()
                case 1: MySoundView()
                case 2: ConnectionManagementView()
                case 3: BehaviorView()
                default: EmptyView()
                }
            }
            .padding(.horizontal, 4)
            .padding(.vertical, 6)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    private func switchToTab(_ newIndex: Int) {
        guard newIndex != selectedTab else { return }
        previousTab = selectedTab
        withAnimation(.easeInOut(duration: 0.22)) {
            selectedTab = newIndex
        }
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
            VStack(spacing: 2) {
                Image(systemName: icon)
                    .font(.system(size: 14, weight: isSelected ? .semibold : .regular))
                Text(title)
                    .font(.system(size: 10, weight: isSelected ? .medium : .regular))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
            .background(isSelected ? Color.accentColor.opacity(0.25) : Color.clear)
            .foregroundColor(isSelected ? .accentColor : .secondary)
            .cornerRadius(10)
            .contentShape(Rectangle())
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
                    .foregroundColor(.primary)
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

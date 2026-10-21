import SwiftUI

struct MenuBarView: View {
    @EnvironmentObject var btManager: BluetoothManager
    @State private var selectedTab: Int = 0
    @State private var previousTab: Int = 0
    @Namespace private var glassNamespace // Proper view-level namespace
    
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
            
            // Custom Directional Slide Container
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
            
            // Apple Native iOS Liquid Glass Floating Tab Bar
            HStack(spacing: 4) {
                LiquidGlassTabButton(icon: "earbuds", title: "Noise", isSelected: selectedTab == 0, namespace: glassNamespace) {
                    switchToTab(0)
                }
                LiquidGlassTabButton(icon: "slider.vertical.3", title: "Sound", isSelected: selectedTab == 1, namespace: glassNamespace) {
                    switchToTab(1)
                }
                LiquidGlassTabButton(icon: "laptopcomputer.and.iphone", title: "Devices", isSelected: selectedTab == 2, namespace: glassNamespace) {
                    switchToTab(2)
                }
                LiquidGlassTabButton(icon: "switch.2", title: "Behavior", isSelected: selectedTab == 3, namespace: glassNamespace) {
                    switchToTab(3)
                }
            }
            .padding(4)
            .background(.ultraThinMaterial)
            .background(Color.primary.opacity(0.04))
            .cornerRadius(30)
            .overlay(
                RoundedRectangle(cornerRadius: 30)
                    .stroke(Color.white.opacity(0.12), lineWidth: 0.5)
            )
            .shadow(color: Color.black.opacity(0.2), radius: 10, x: 0, y: 5)
            .padding(.horizontal, 16)
            .padding(.bottom, 12)
            .padding(.top, 6)
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
        withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
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

// Apple iOS Liquid Glass Tab Button with Selection Morph
struct LiquidGlassTabButton: View {
    let icon: String
    let title: String
    let isSelected: Bool
    var namespace: Namespace.ID
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: 2) {
                Image(systemName: icon)
                    .font(.system(size: 14, weight: isSelected ? .semibold : .regular))
                Text(title)
                    .font(.system(size: 9, weight: isSelected ? .medium : .regular))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .background(
                ZStack {
                    if isSelected {
                        RoundedRectangle(cornerRadius: 24)
                            .fill(Color.accentColor.opacity(0.25))
                            .matchedGeometryEffect(id: "GLASS_ACTIVE_TAB", in: namespace)
                            .shadow(color: Color.accentColor.opacity(0.1), radius: 4, x: 0, y: 2)
                    }
                }
            )
            .foregroundColor(isSelected ? .accentColor : .secondary)
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

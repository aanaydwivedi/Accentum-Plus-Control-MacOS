//
//  Untitled.swift
//  MyApp
//
//  Created by Aanay Dwivedi on 21/10/26.
//

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
                HStack(spacing: 8) {
                    if btManager.isConnected {
                        if let battery = btManager.batteryLevel {
                            HStack(spacing: 4) {
                                Image(systemName: batteryIcon(for: battery))
                                    .foregroundColor(batteryColor(for: battery))
                                Text("\(battery)%")
                                    .font(.callout.monospacedDigit())
                                    .foregroundColor(.secondary)
                            }
                        }
                        
                        Circle()
                            .fill(Color.green)
                            .frame(width: 7, height: 7)
                        
                        Text("Connected")
                            .font(.callout)
                            .foregroundColor(.secondary)
                    } else {
                        Circle()
                            .fill(Color.secondary)
                            .frame(width: 7, height: 7)
                        Text("Disconnected")
                            .font(.callout)
                            .foregroundColor(.secondary)
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(Color(NSColor.controlBackgroundColor))
                .clipShape(Capsule())
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

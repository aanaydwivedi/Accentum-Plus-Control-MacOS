//
//  Untitled.swift
//  MyApp
//
//  Created by Aanay Dwivedi on 21/10/26.
//

import SwiftUI

struct NoiseControlView: View {
    @EnvironmentObject var btManager: BluetoothManager
    
    var body: some View {
        Form {
            Section {
                // Device Header Card
                HStack(spacing: 14) {
                    Image(systemName: "headphones")
                        .font(.system(size: 34))
                        .foregroundColor(.accentColor)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(btManager.deviceName)
                            .font(.headline)
                        Text(btManager.isConnected ? "Connected • Bluetooth Classic" : "Disconnected")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                    if let battery = btManager.batteryLevel {
                        Text("\(battery)% Battery")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                }
                .padding(.vertical, 4)
            }
            
            Section {
                // Segmented Mode Selector
                Picker("Noise Mode", selection: Binding(
                    get: { btManager.noiseMode },
                    set: { newMode in btManager.setNoiseMode(newMode) }
                )) {
                    Text("ANC").tag(NoiseMode.anc)
                    Text("Adaptive").tag(NoiseMode.adaptive)
                    Text("Transparency").tag(NoiseMode.transparency)
                    Text("Off").tag(NoiseMode.off)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                
                // Toggle switch
                Toggle("Transparent Hearing", isOn: Binding(
                    get: { btManager.isTransparencyOn },
                    set: { val in btManager.toggleTransparency(val) }
                ))
                .toggleStyle(.switch)
            } header: {
                Text("Modes")
            }
            
            // Dynamic Slider: Ambient Sound volume (when Transparency is ON)
            if btManager.isTransparencyOn {
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Ambient Sound Level")
                            Spacer()
                            Text("\(Int(btManager.transparencyLevel))%")
                                .font(.callout.monospacedDigit())
                                .foregroundColor(.secondary)
                        }
                        HStack {
                            Image(systemName: "speaker.wave.1.fill")
                                .foregroundColor(.secondary)
                            Slider(value: Binding(
                                get: { btManager.transparencyLevel },
                                set: { val in btManager.setTransparencyLevel(Int(val)) }
                            ), in: 0...100, step: 1)
                            Image(systemName: "speaker.wave.3.fill")
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding(.vertical, 4)
                } header: {
                    Text("Ambient Sound Control")
                } footer: {
                    Text("Controls the volume of voices and environmental sounds passed into the headphones.")
                }
            }
            
            // Dynamic Slider: ANC Strength (when in manual ANC mode)
            if btManager.noiseMode == .anc && !btManager.isTransparencyOn {
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Noise Cancellation Strength")
                            Spacer()
                            Text("\(Int(btManager.ancStrength))%")
                                .font(.callout.monospacedDigit())
                                .foregroundColor(.secondary)
                        }
                        HStack {
                            Text("Min").font(.caption).foregroundColor(.secondary)
                            Slider(value: Binding(
                                get: { btManager.ancStrength },
                                set: { val in btManager.setAncStrength(Int(val)) }
                            ), in: 0...100, step: 1)
                            Text("Max").font(.caption).foregroundColor(.secondary)
                        }
                    }
                    .padding(.vertical, 4)
                } header: {
                    Text("Cancellation Strength")
                } footer: {
                    Text("Adjusts the intensity of active background noise suppression.")
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Noise Control")
    }
}

struct BehaviorView: View {
    @EnvironmentObject var btManager: BluetoothManager
    
    var body: some View {
        Form {
            Section {
                Toggle("Smart Pause", isOn: Binding(
                    get: { btManager.isSmartPauseOn },
                    set: { val in btManager.setSmartPause(val) }
                ))
                .toggleStyle(.switch)
                
                Toggle("On-Head Detection", isOn: Binding(
                    get: { btManager.isOnHeadDetectionOn },
                    set: { val in btManager.setOnHeadDetection(val) }
                ))
                .toggleStyle(.switch)
                
                Toggle("Touch Controls", isOn: Binding(
                    get: { btManager.isTouchControlOn },
                    set: { val in btManager.setTouchControls(val) }
                ))
                .toggleStyle(.switch)
            } header: {
                Text("Sensor & Touch Controls")
            } footer: {
                Text("Smart Pause pauses playback automatically when you take off the headphones.")
            }
            
            Section {
                Toggle("Auto-Answer Calls", isOn: Binding(
                    get: { btManager.isAutoAnswerOn },
                    set: { val in btManager.setAutoAnswer(val) }
                ))
                .toggleStyle(.switch)
                
                Toggle("Comfort Call", isOn: Binding(
                    get: { btManager.isComfortCallOn },
                    set: { val in btManager.setComfortCall(val) }
                ))
                .toggleStyle(.switch)
            } header: {
                Text("Calls")
            }
            
            Section {
                Picker("Auto Power Off", selection: Binding(
                    get: { btManager.autoPowerOffMinutes },
                    set: { val in btManager.setAutoPowerOff(minutes: val) }
                )) {
                    Text("Never").tag(0)
                    Text("15 Minutes").tag(15)
                    Text("30 Minutes").tag(30)
                    Text("60 Minutes").tag(60)
                }
            } header: {
                Text("Power Management")
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Behavior")
    }
}

import SwiftUI

struct NoiseControlView: View {
    @EnvironmentObject var btManager: BluetoothManager
    
    // Exact text scaling matching the official Sennheiser app
    private var leftLabel: String {
        if btManager.ancSliderValue <= 50 {
            let percent = Int(round((50.0 - btManager.ancSliderValue) * 2.0))
            return "ANC \(percent)%"
        } else {
            return "ANC 0%"
        }
    }
    
    private var rightLabel: String {
        if btManager.ancSliderValue >= 50 {
            let percent = Int(round((btManager.ancSliderValue - 50.0) * 2.0))
            return "\(percent)% Transparency"
        } else {
            return "0% Transparency"
        }
    }
    
    var body: some View {
        Form {
            Section {
                // Device Header Card (Redundant battery display removed)
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
                }
                .padding(.vertical, 4)
            }
            
            Section {
                // Official Modes: Adaptive | Custom | Off
                Picker("Noise Control", selection: Binding(
                    get: { btManager.noiseMode },
                    set: { newMode in btManager.setNoiseMode(newMode) }
                )) {
                    Text("Adaptive").tag(NoiseMode.adaptive)
                    Text("Custom").tag(NoiseMode.custom)
                    Text("Off").tag(NoiseMode.off)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                
                if btManager.noiseMode == .custom {
                    VStack(spacing: 12) {
                        // Dynamic labels matching Sennheiser Smart Control
                        HStack {
                            Text(leftLabel)
                                .font(.subheadline.weight(btManager.ancSliderValue < 50 ? .semibold : .regular))
                                .foregroundColor(btManager.ancSliderValue < 50 ? .primary : .secondary)
                            Spacer()
                            Text(rightLabel)
                                .font(.subheadline.weight(btManager.ancSliderValue > 50 ? .semibold : .regular))
                                .foregroundColor(btManager.ancSliderValue > 50 ? .primary : .secondary)
                        }
                        
                        // Unified Blend Slider (0 to 100 with Center Notch at 50)
                        ZStack {
                            Rectangle()
                                .fill(Color.secondary.opacity(0.4))
                                .frame(width: 1.5, height: 16)
                            
                            Slider(value: Binding(
                                get: { btManager.ancSliderValue },
                                set: { val in btManager.setSliderValue(val) }
                            ), in: 0...100, step: 1)
                        }
                    }
                    .padding(.vertical, 6)
                } else if btManager.noiseMode == .adaptive {
                    HStack(spacing: 8) {
                        Image(systemName: "waveform.path")
                            .foregroundColor(.accentColor)
                        Text("Adaptive noise cancellation is automatically adapting to your environment.")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    .padding(.vertical, 4)
                } else {
                    Text("Noise cancellation and transparency are disabled.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .padding(.vertical, 4)
                }
            } header: {
                Text("Noise Control")
            } footer: {
                if btManager.noiseMode == .custom {
                    Text("Center is neutral. Slide left for active noise cancellation, or right for transparency.")
                }
            }
            
            // Anti-Wind Toggle
            if btManager.noiseMode != .off {
                Section {
                    Toggle(isOn: Binding(
                        get: { btManager.isAntiWindOn },
                        set: { val in btManager.setAntiWind(val) }
                    )) {
                        HStack(spacing: 10) {
                            Image(systemName: "wind")
                                .font(.system(size: 18))
                                .foregroundColor(.secondary)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Anti-wind")
                                Text("Reduce wind noise in ANC.")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                    .toggleStyle(.switch)
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

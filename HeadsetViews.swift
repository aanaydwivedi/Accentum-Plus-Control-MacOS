import SwiftUI

// MARK: - 1. NOISE CONTROL VIEW
struct NoiseControlView: View {
    @EnvironmentObject var btManager: BluetoothManager
    
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
                // Hero Device Card (No duplicate battery)
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
                // Mode Selector: Adaptive | Custom | Off
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
                    VStack(spacing: 10) {
                        HStack {
                            Text(leftLabel)
                                .font(.subheadline.weight(btManager.ancSliderValue < 50 ? .semibold : .regular))
                                .foregroundColor(btManager.ancSliderValue < 50 ? .primary : .secondary)
                            Spacer()
                            Text(rightLabel)
                                .font(.subheadline.weight(btManager.ancSliderValue > 50 ? .semibold : .regular))
                                .foregroundColor(btManager.ancSliderValue > 50 ? .primary : .secondary)
                        }
                        
                        // Clean Slider - no vertical line artifact
                        Slider(value: Binding(
                            get: { btManager.ancSliderValue },
                            set: { val in btManager.setSliderValue(val) }
                        ), in: 0...100, step: 1)
                    }
                    .padding(.vertical, 4)
                } else if btManager.noiseMode == .adaptive {
                    HStack(spacing: 8) {
                        Image(systemName: "waveform.path")
                            .foregroundColor(.accentColor)
                        Text("Adaptive noise cancellation is automatically adapting to your surroundings.")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    .padding(.vertical, 4)
                } else {
                    Text("Noise cancellation and transparency are off.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .padding(.vertical, 4)
                }
            } header: {
                Text("Noise Control")
            }
            
            // Anti-Wind Settings (Images 3 & 4)
            if btManager.noiseMode != .off {
                Section {
                    Toggle(isOn: Binding(
                        get: { btManager.isAntiWindOn },
                        set: { val in btManager.setAntiWind(enabled: val) }
                    )) {
                        HStack(spacing: 8) {
                            Image(systemName: "wind")
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
                    
                    if btManager.isAntiWindOn {
                        Picker("Anti-wind Mode", selection: Binding(
                            get: { btManager.antiWindSetting },
                            set: { val in btManager.setAntiWind(enabled: true, setting: val) }
                        )) {
                            Text("Auto").tag(AntiWindSetting.auto)
                            Text("Max").tag(AntiWindSetting.max)
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                    }
                } header: {
                    Text("Anti-wind Settings")
                }
            }
            
            // Phone Calls (Sidetone) (Image 4)
            Section {
                Toggle(isOn: Binding(
                    get: { btManager.isPhoneCallTransparencyOn },
                    set: { val in btManager.setPhoneCallTransparency(enabled: val) }
                )) {
                    HStack(spacing: 8) {
                        Image(systemName: "phone.badge.waveform")
                            .foregroundColor(.secondary)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Phone calls")
                            Text("Activate transparency during phone calls.")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
                .toggleStyle(.switch)
                
                if btManager.isPhoneCallTransparencyOn {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text("Low").font(.caption).foregroundColor(.secondary)
                            Slider(value: Binding(
                                get: { btManager.phoneCallTransparencyLevel },
                                set: { val in btManager.setPhoneCallTransparency(enabled: true, level: val) }
                            ), in: 1...5, step: 1)
                            Text("High").font(.caption).foregroundColor(.secondary)
                        }
                    }
                    .padding(.top, 4)
                }
            } header: {
                Text("Call Transparency")
            }
            
            // Auto-pause (Image 4)
            Section {
                Toggle(isOn: Binding(
                    get: { btManager.isAutoPauseTransparencyOn },
                    set: { val in btManager.setAutoPauseTransparency(val) }
                )) {
                    HStack(spacing: 8) {
                        Image(systemName: "pause.circle")
                            .foregroundColor(.secondary)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Auto-pause")
                            Text("Pause audio when Transparency is enabled.")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
                .toggleStyle(.switch)
            } header: {
                Text("Convenience")
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Noise Control")
    }
}

// MARK: - 2. CONNECTION MANAGEMENT VIEW (Image 2)
struct ConnectionManagementView: View {
    @EnvironmentObject var btManager: BluetoothManager
    
    var body: some View {
        Form {
            Section {
                Toggle(isOn: $btManager.isMultipointEnabled) {
                    HStack(spacing: 10) {
                        Image(systemName: "laptopcomputer.and.iphone")
                            .font(.system(size: 20))
                            .foregroundColor(.secondary)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Multipoint")
                            Text("Connect up to two devices at once.")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
                .toggleStyle(.switch)
            } header: {
                Text("Settings")
            }
            
            Section {
                if btManager.pairedDevices.isEmpty {
                    HStack {
                        ProgressView()
                            .scaleEffect(0.8)
                        Text("Reading paired devices...")
                            .foregroundColor(.secondary)
                    }
                } else {
                    ForEach(btManager.pairedDevices) { device in
                        HStack(spacing: 12) {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(device.name)
                                    .font(.body.weight(device.isConnected ? .medium : .regular))
                                if device.isThisDevice {
                                    Text("This Mac")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }
                            
                            Spacer()
                            
                            if device.isConnected {
                                Image(systemName: "checkmark")
                                    .foregroundColor(.accentColor)
                                    .font(.headline)
                            }
                            
                            Button(device.isConnected ? "Disconnect" : "Connect") {
                                btManager.toggleDeviceConnection(device)
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                            
                            if !device.isThisDevice {
                                Button(role: .destructive) {
                                    btManager.removeDevice(device)
                                } label: {
                                    Image(systemName: "trash")
                                        .foregroundColor(.secondary)
                                }
                                .buttonStyle(.borderless)
                            }
                        }
                        .padding(.vertical, 3)
                    }
                }
            } header: {
                HStack {
                    Text("Paired Devices")
                    Spacer()
                    Button("Refresh") {
                        btManager.refreshPairedDevices()
                    }
                    .font(.caption)
                    .buttonStyle(.borderless)
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Connection Management")
        .onAppear {
            if btManager.isConnected {
                btManager.refreshPairedDevices()
            }
        }
    }
}

// MARK: - 3. MY SOUND & GRAPHIC EQ VIEW (Image 5)
struct MySoundView: View {
    @EnvironmentObject var btManager: BluetoothManager
    @State private var showingSaveSheet = false
    @State private var newPresetName = ""
    
    let frequencies = ["63 Hz", "250 Hz", "1 kHz", "4 kHz", "8 kHz"]
    
    var body: some View {
        Form {
            // Section 1: Graphic EQ & Presets
            Section {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Graphic EQ")
                            .font(.headline)
                        Text(btManager.selectedPresetName)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                    
                    Menu {
                        Section("Built-in Presets") {
                            ForEach(btManager.customPresets) { preset in
                                Button(preset.name) {
                                    btManager.applyPreset(preset)
                                }
                            }
                        }
                        Section {
                            Button("Save Current Curve...") {
                                newPresetName = ""
                                showingSaveSheet = true
                            }
                        }
                    } label: {
                        Text(btManager.selectedPresetName)
                            .font(.callout)
                    }
                }
                .padding(.vertical, 2)
                
                // 5 Vertical Sliders
                HStack(spacing: 24) {
                    ForEach(0..<5) { index in
                        VStack(spacing: 8) {
                            Text("\(btManager.eqGains[index] >= 0 ? "+" : "")\(String(format: "%.1f", btManager.eqGains[index]))")
                                .font(.caption2.monospacedDigit())
                                .foregroundColor(.secondary)
                            
                            Slider(value: Binding(
                                get: { btManager.eqGains[index] },
                                set: { val in btManager.setEqBand(index: index, gain: val) }
                            ), in: -6.0...6.0, step: 0.5)
                            .frame(height: 120)
                            
                            Text(frequencies[index])
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }
                }
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity, alignment: .center)
                
                Toggle("Bass boost", isOn: Binding(
                    get: { btManager.isBassBoostOn },
                    set: { val in btManager.setBassBoost(val) }
                ))
                .toggleStyle(.switch)
            } header: {
                Text("Equalizer")
            }
            
            // Section 2: Speech Clarity
            Section {
                Toggle(isOn: Binding(
                    get: { btManager.isSpeechClarityOn },
                    set: { val in btManager.setSpeechClarity(val) }
                )) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Speech Clarity")
                            .font(.body)
                        Text("Make voices stand out among audio playback.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                .toggleStyle(.switch)
            } header: {
                Text("Clarity")
            }
            
            // Section 3: Sound Personalization (Visual Card from Image 5)
            Section {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Sound Personalization")
                                .font(.headline)
                            Text("Tailor your listening experience")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                        Toggle("", isOn: Binding(
                            get: { btManager.isSoundPersonalizationOn },
                            set: { val in btManager.setSoundPersonalization(val) }
                        ))
                        .toggleStyle(.switch)
                        .labelsHidden()
                    }
                    
                    // Wave graphic visualization
                    HStack(alignment: .bottom, spacing: 4) {
                        ForEach(0..<30) { bar in
                            RoundedRectangle(cornerRadius: 2)
                                .fill(LinearGradient(colors: [.accentColor.opacity(0.8), .cyan], startPoint: .bottom, endPoint: .top))
                                .frame(width: 4, height: waveHeight(for: bar))
                        }
                    }
                    .frame(height: 50)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 4)
                    
                    Text("Sound Personalization uses an algorithm to create a unique sound profile tuned to your hearing preferences.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(.vertical, 4)
            } header: {
                Text("Personalization")
            }
        }
        .formStyle(.grouped)
        .navigationTitle("My Sound")
        .sheet(isPresented: $showingSaveSheet) {
            VStack(spacing: 16) {
                Text("Save Preset").font(.headline)
                TextField("Preset Name", text: $newPresetName)
                    .textFieldStyle(.roundedBorder)
                HStack {
                    Button("Cancel") { showingSaveSheet = false }
                    Spacer()
                    Button("Save") {
                        if !newPresetName.isEmpty {
                            btManager.saveCustomPreset(name: newPresetName)
                            showingSaveSheet = false
                        }
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
            .padding()
            .frame(width: 280)
        }
    }
    
    private func waveHeight(for index: Int) -> CGFloat {
        let center = 15.0
        let dist = abs(Double(index) - center)
        let normalized = max(0.2, 1.0 - (dist / 15.0))
        return CGFloat(10 + sin(Double(index) * 0.5) * 8 + normalized * 30)
    }
}

// MARK: - 4. BEHAVIOR VIEW
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

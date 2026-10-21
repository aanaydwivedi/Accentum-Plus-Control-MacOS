import Foundation
import IOBluetooth
import Combine

enum NoiseMode: String, CaseIterable, Identifiable {
    case adaptive = "Adaptive"
    case custom = "Custom"
    case off = "Off"
    var id: String { rawValue }
}

enum AntiWindSetting: String, CaseIterable, Identifiable {
    case auto = "Auto"
    case max = "Max"
    var id: String { rawValue }
}

struct PairedDevice: Identifiable, Hashable {
    let id: Int
    var name: String
    var isConnected: Bool
    var isThisDevice: Bool
}

struct EqPresetItem: Identifiable, Hashable {
    let id = UUID()
    let name: String
    let gains: [Double] // 5 bands
}

class BluetoothManager: NSObject, ObservableObject, IOBluetoothRFCOMMChannelDelegate {
    @Published var isConnected = false
    @Published var deviceName = "ACCENTUM Plus"
    @Published var batteryLevel: Int? = nil
    
    // MARK: - Noise Control State
    @Published var noiseMode: NoiseMode = .custom
    @Published var ancSliderValue: Double = 50.0 // 0 = 100% ANC | 50 = Center (0/0) | 100 = 100% Transparency
    @Published var isAntiWindOn: Bool = false
    @Published var antiWindSetting: AntiWindSetting = .max
    @Published var isPhoneCallTransparencyOn: Bool = false
    @Published var phoneCallTransparencyLevel: Double = 3.0 // 1 to 5 (Sidetone)
    @Published var isAutoPauseTransparencyOn: Bool = true
    
    // MARK: - Connection Management (Multipoint)
    @Published var isMultipointEnabled: Bool = true
    @Published var pairedDevices: [PairedDevice] = []
    @Published var ownDeviceIndex: Int = 0
    
    // MARK: - My Sound & Equalizer State
    @Published var eqGains: [Double] = [0, 0, 0, 0, 0] // 63Hz, 250Hz, 1kHz, 4kHz, 8kHz
    @Published var selectedPresetName: String = "Wide Airy"
    @Published var isBassBoostOn: Bool = false
    @Published var isSpeechClarityOn: Bool = false
    @Published var isSoundPersonalizationOn: Bool = false
    @Published var customPresets: [EqPresetItem] = [
        EqPresetItem(name: "Wide Airy", gains: [1.5, 0.5, 0.0, 2.0, 3.5]),
        EqPresetItem(name: "Rock", gains: [3.0, 1.0, -1.0, 1.5, 3.5]),
        EqPresetItem(name: "Pop", gains: [-1.0, 1.0, 2.5, 1.5, -0.5]),
        EqPresetItem(name: "Hip Hop", gains: [4.5, 2.5, 0.0, 1.0, 2.0]),
        EqPresetItem(name: "Flat", gains: [0.0, 0.0, 0.0, 0.0, 0.0]),
        EqPresetItem(name: "Movie", gains: [4.0, 1.5, 0.0, 1.0, 0.0])
    ]
    
    // MARK: - Behavior State
    @Published var isSmartPauseOn: Bool = true
    @Published var isTouchControlOn: Bool = true
    @Published var isOnHeadDetectionOn: Bool = true
    @Published var isAutoAnswerOn: Bool = false
    @Published var isComfortCallOn: Bool = true
    @Published var autoPowerOffMinutes: Int = 15
    
    private var rfcommChannel: IOBluetoothRFCOMMChannel?
    let vendorSennheiser: UInt16 = 0x0495
    
    private var rxBuffer = [UInt8]()
    private var sliderDebounceTimer: Timer?
    private var eqDebounceTimer: Timer?
    private var batteryPollTimer: Timer?
    
    func connectToAccentumPlus() {
        guard let paired = IOBluetoothDevice.pairedDevices() as? [IOBluetoothDevice] else { return }
        guard let accentum = paired.first(where: {
            $0.name?.localizedCaseInsensitiveContains("ACCENTUM Plus") == true
        }) else {
            deviceName = "ACCENTUM Plus not found"
            return
        }
        
        deviceName = accentum.name ?? "ACCENTUM Plus"
        accentum.openRFCOMMChannelSync(&rfcommChannel, withChannelID: 1, delegate: self)
        
        if rfcommChannel != nil {
            DispatchQueue.main.async { self.isConnected = true }
            registerNotifications()
            readInitialState()
            startPeriodicBatteryPoll()
        }
    }
    
    func rfcommChannelData(_ rfcommChannel: IOBluetoothRFCOMMChannel!, data dataPointer: UnsafeMutableRawPointer!, length dataLength: Int) {
        let buffer = UnsafeBufferPointer(start: dataPointer.assumingMemoryBound(to: UInt8.self), count: dataLength)
        parseIncomingStream(Array(buffer))
    }
    
    func rfcommChannelClosed(_ rfcommChannel: IOBluetoothRFCOMMChannel!) {
        DispatchQueue.main.async {
            self.isConnected = false
            self.batteryLevel = nil
            self.batteryPollTimer?.invalidate()
        }
    }
    
    // MARK: - Low-Level Send
    private func send(command: UInt16, payload: [UInt8] = []) {
        var frame = GaiaFrame.encode(command: command, payload: payload)
        let frameLength = UInt16(frame.count) // Read the count BEFORE borrowing `frame` mutably
        
        frame.withUnsafeMutableBytes { ptr in
            guard let baseAddress = ptr.baseAddress else { return }
            rfcommChannel?.writeSync(baseAddress, length: frameLength)
        }
    }
    
    // MARK: - Noise Control Actions
    func setNoiseMode(_ mode: NoiseMode) {
        self.noiseMode = mode
        let windByte: UInt8 = isAntiWindOn ? (antiWindSetting == .auto ? 0x02 : 0x01) : 0x00
        
        switch mode {
        case .adaptive:
            send(command: 0x1804, payload: [0x00])
            send(command: 0x1A04, payload: [0x01])
            send(command: 0x1A00, payload: [0x01, windByte, 0x02, 0x00, 0x03, 0x01])
            
        case .custom:
            send(command: 0x1A04, payload: [0x01])
            send(command: 0x1A00, payload: [0x01, windByte, 0x02, 0x00, 0x03, 0x00])
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                let hardwareLevel = UInt8(clamping: Int(round(self.ancSliderValue)))
                self.send(command: 0x1A02, payload: [hardwareLevel])
            }
            
        case .off:
            send(command: 0x1A04, payload: [0x00])
            send(command: 0x1804, payload: [0x00])
        }
    }
    
    func setSliderValue(_ value: Double) {
        self.ancSliderValue = value
        if noiseMode != .custom {
            self.noiseMode = .custom
            let windByte: UInt8 = isAntiWindOn ? (antiWindSetting == .auto ? 0x02 : 0x01) : 0x00
            send(command: 0x1A04, payload: [0x01])
            send(command: 0x1A00, payload: [0x01, windByte, 0x02, 0x00, 0x03, 0x00])
        }
        
        sliderDebounceTimer?.invalidate()
        sliderDebounceTimer = Timer.scheduledTimer(withTimeInterval: 0.03, repeats: false) { [weak self] _ in
            guard let self = self else { return }
            let hardwareLevel = UInt8(clamping: Int(round(value)))
            self.send(command: 0x1A02, payload: [hardwareLevel])
        }
    }
    
    func setAntiWind(enabled: Bool, setting: AntiWindSetting? = nil) {
        self.isAntiWindOn = enabled
        if let s = setting { self.antiWindSetting = s }
        let windVal: UInt8 = enabled ? (self.antiWindSetting == .auto ? 0x02 : 0x01) : 0x00
        let adaptiveByte: UInt8 = (noiseMode == .adaptive) ? 0x01 : 0x00
        send(command: 0x1A00, payload: [0x01, windVal, 0x02, 0x00, 0x03, adaptiveByte])
    }
    
    func setPhoneCallTransparency(enabled: Bool, level: Double? = nil) {
        self.isPhoneCallTransparencyOn = enabled
        if let l = level { self.phoneCallTransparencyLevel = l }
        let sidetoneByte = enabled ? UInt8(clamping: Int(self.phoneCallTransparencyLevel)) : 0x00
        send(command: 0x0805, payload: [sidetoneByte]) // 0x0805 = Set Sidetone (0..5)
    }
    
    func setAutoPauseTransparency(_ on: Bool) {
        self.isAutoPauseTransparencyOn = on
        send(command: 0x1800, payload: [on ? 0x01 : 0x00]) // 0x1800 = Set Auto-pause mode
    }
    
    // MARK: - Connection Management Actions
    func toggleDeviceConnection(_ device: PairedDevice) {
        if device.isConnected {
            // 0x1403 = Disconnect device
            send(command: 0x1403, payload: [UInt8(device.id)])
        } else {
            // 0x1402 = Connect device
            send(command: 0x1402, payload: [UInt8(device.id)])
        }
        // Refresh device list after brief delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
            self.refreshPairedDevices()
        }
    }
    
    func removeDevice(_ device: PairedDevice) {
        send(command: 0x1405, payload: [UInt8(device.id)]) // 0x1405 = Delete pairing
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            self.refreshPairedDevices()
        }
    }
    
    func refreshPairedDevices() {
        send(command: 0x1407) // Own index
        send(command: 0x1400) // Device count
    }
    
    // MARK: - My Sound & EQ Actions
    func setEqBand(index: Int, gain: Double) {
        guard index >= 0 && index < eqGains.count else { return }
        eqGains[index] = gain
        selectedPresetName = "Custom"
        
        eqDebounceTimer?.invalidate()
        eqDebounceTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: false) { [weak self] _ in
            guard let self = self else { return }
            // GAIA 0x1001 expects: [band_index, gain_in_tenths_of_dB (i8)]
            let rawGain = Int8(clamping: Int(round(gain * 10.0)))
            self.send(command: 0x1001, payload: [UInt8(index), UInt8(bitPattern: rawGain)])
        }
    }
    
    func applyPreset(_ preset: EqPresetItem) {
        selectedPresetName = preset.name
        eqGains = preset.gains
        for (i, gain) in preset.gains.enumerated() {
            let rawGain = Int8(clamping: Int(round(gain * 10.0)))
            send(command: 0x1001, payload: [UInt8(i), UInt8(bitPattern: rawGain)])
        }
    }
    
    func saveCustomPreset(name: String) {
        let newPreset = EqPresetItem(name: name, gains: eqGains)
        customPresets.append(newPreset)
        selectedPresetName = name
    }
    
    func setBassBoost(_ on: Bool) {
        isBassBoostOn = on
        send(command: 0x1008, payload: [on ? 0x01 : 0x00]) // 0x1008 = Bass Boost
    }
    
    func setSpeechClarity(_ on: Bool) {
        isSpeechClarityOn = on
        if on {
            isSoundPersonalizationOn = false
            send(command: 0x0803, payload: [0x00, 0x02]) // Sound mode 2 = Speech Clarity
        } else {
            send(command: 0x0803, payload: [0x00, 0x01]) // Sound mode 1 = Equalizer
        }
    }
    
    func setSoundPersonalization(_ on: Bool) {
        isSoundPersonalizationOn = on
        if on {
            isSpeechClarityOn = false
            send(command: 0x0803, payload: [0x00, 0x03]) // Sound mode 3 = Personalization
        } else {
            send(command: 0x0803, payload: [0x00, 0x01]) // Sound mode 1 = Equalizer
        }
    }
    
    // MARK: - Behavior Actions
    func setSmartPause(_ on: Bool) {
        isSmartPauseOn = on
        send(command: 0x080C, payload: [on ? 1 : 0])
    }
    func setTouchControls(_ on: Bool) {
        isTouchControlOn = on
        send(command: 0x1606, payload: [on ? 0 : 1]) // 0 = active, 1 = locked
    }
    func setOnHeadDetection(_ on: Bool) {
        isOnHeadDetectionOn = on
        send(command: 0x0400, payload: [on ? 1 : 0])
    }
    func setAutoAnswer(_ on: Bool) {
        isAutoAnswerOn = on
        send(command: 0x080A, payload: [on ? 1 : 0])
    }
    func setComfortCall(_ on: Bool) {
        isComfortCallOn = on
        send(command: 0x0814, payload: [on ? 1 : 0])
    }
    func setAutoPowerOff(minutes: Int) {
        self.autoPowerOffMinutes = minutes
        let seconds = minutes * 60
        send(command: 0x0600, payload: [0x00, UInt8((seconds >> 8) & 0xFF), UInt8(seconds & 0xFF)])
    }
    
    // MARK: - Query & Registration
    private func registerNotifications() {
        send(command: 0x0007, payload: [0x03]) // Battery
        send(command: 0x0007, payload: [0x0D]) // ANC
        send(command: 0x0007, payload: [0x0C]) // Transparency
        send(command: 0x0007, payload: [0x08]) // EQ
        send(command: 0x0007, payload: [0x0A]) // Multipoint
        send(command: 0x0007, payload: [0x0B]) // Touch
        send(command: 0x0007, payload: [0x02]) // Device State
    }
    
    private func readInitialState() {
        let commands: [(UInt16, [UInt8])] = [
            (0x0603, []),           // Battery
            (0x1A05, []),           // ANC Enabled
            (0x1A01, []),           // ANC Modes
            (0x1A03, []),           // ANC Level
            (0x1801, []),           // Auto-pause mode
            (0x0806, []),           // Sidetone (Phone calls transparency)
            (0x1003, [0x00]),       // EQ all gains
            (0x1009, []),           // Bass boost
            (0x0804, []),           // Sound mode
            (0x1407, []),           // Own device index
            (0x1400, []),           // Paired device count
            (0x080D, []),           // Smart pause
            (0x1607, []),           // Touch lock
            (0x0401, []),           // On-head detection
            (0x080B, []),           // Auto answer
            (0x0815, []),           // Comfort call
            (0x0601, [0x00])        // Auto power off
        ]
        
        for (i, item) in commands.enumerated() {
            DispatchQueue.main.asyncAfter(deadline: .now() + Double(i) * 0.04) { [weak self] in
                guard let self = self, self.isConnected else { return }
                self.send(command: item.0, payload: item.1)
            }
        }
    }
    
    private func startPeriodicBatteryPoll() {
        batteryPollTimer?.invalidate()
        batteryPollTimer = Timer.scheduledTimer(withTimeInterval: 30.0, repeats: true) { [weak self] _ in
            guard let self = self, self.isConnected else { return }
            self.send(command: 0x0603)
        }
    }
    
    // MARK: - Stream Parser
    private func parseIncomingStream(_ data: [UInt8]) {
        rxBuffer.append(contentsOf: data)
        while rxBuffer.count >= 8 {
            guard let sofIndex = rxBuffer.firstIndex(of: 0xFF) else {
                rxBuffer.removeAll()
                return
            }
            if sofIndex > 0 { rxBuffer.removeSubrange(0..<sofIndex) }
            guard rxBuffer.count >= 8 else { return }
            guard rxBuffer[1] == 0x03 else {
                rxBuffer.removeFirst()
                continue
            }
            
            let flags = rxBuffer[2]
            let payloadLength = Int(rxBuffer[3])
            let totalLen = 8 + payloadLength + ((flags & 0x01) != 0 ? 1 : 0)
            guard rxBuffer.count >= totalLen else { return }
            
            let commandId = (UInt16(rxBuffer[6]) << 8) | UInt16(rxBuffer[7])
            let payload = Array(rxBuffer[8..<(8 + payloadLength)])
            rxBuffer.removeSubrange(0..<totalLen)
            
            dispatchFrame(commandId: commandId, payload: payload)
        }
    }
    
    private func dispatchFrame(commandId: UInt16, payload: [UInt8]) {
        DispatchQueue.main.async {
            switch commandId {
            case 0x0703, 0x0683: // Battery
                if let b = payload.first { self.batteryLevel = Int(b) }
                
            case 0x1B01, 0x1A81: // ANC Mode Table
                var i = 0
                while i + 1 < payload.count {
                    let modeId = payload[i]
                    let val = payload[i+1]
                    if modeId == 0x01 {
                        self.isAntiWindOn = (val >= 1)
                        if val == 2 { self.antiWindSetting = .auto }
                        else if val == 1 { self.antiWindSetting = .max }
                    }
                    if modeId == 0x03 && val == 1 { self.noiseMode = .adaptive }
                    i += 2
                }
                
            case 0x1B05, 0x1A85: // ANC Enabled
                if let val = payload.first, val == 0 { self.noiseMode = .off }
                
            case 0x1B03, 0x1A83: // Level
                if let level = payload.first, self.noiseMode == .custom {
                    self.ancSliderValue = Double(level)
                }
                
            case 0x1901: // Auto-pause
                if let val = payload.first { self.isAutoPauseTransparencyOn = (val == 1) }
                
            case 0x0906: // Sidetone
                if let s = payload.first {
                    self.isPhoneCallTransparencyOn = (s > 0)
                    if s > 0 { self.phoneCallTransparencyLevel = Double(min(5, max(1, s))) }
                }
                
            case 0x1103: // EQ All Gains
                if payload.count >= 5 {
                    self.eqGains = (0..<5).map { Double(Int8(bitPattern: payload[$0])) / 10.0 }
                }
                
            case 0x1109, 0x1089: // Bass Boost
                if let val = payload.first { self.isBassBoostOn = (val == 1) }
                
            case 0x0904, 0x0884: // Sound Mode
                if payload.count >= 2 {
                    let mode = payload[1]
                    self.isSpeechClarityOn = (mode == 2)
                    self.isSoundPersonalizationOn = (mode == 3)
                }
                
            case 0x1507: // Own index
                if let own = payload.first { self.ownDeviceIndex = Int(own) }
                
            case 0x1500: // Paired device count
                if payload.count >= 2 {
                    let count = (Int(payload[0]) << 8) | Int(payload[1])
                    self.pairedDevices.removeAll()
                    for idx in 0..<count {
                        self.send(command: 0x1401, payload: [UInt8(idx)])
                    }
                }
                
            case 0x1501: // Paired device info: [index, prio, status, name...]
                if payload.count >= 4 {
                    let idx = Int(payload[0])
                    let isConn = (payload[2] != 0)
                    let nameBytes = payload[3...].prefix(while: { $0 != 0 })
                    let name = String(bytes: nameBytes, encoding: .utf8) ?? "Device \(idx)"
                    let item = PairedDevice(id: idx, name: name, isConnected: isConn, isThisDevice: idx == self.ownDeviceIndex)
                    if let existing = self.pairedDevices.firstIndex(where: { $0.id == idx }) {
                        self.pairedDevices[existing] = item
                    } else {
                        self.pairedDevices.append(item)
                    }
                }
                
            case 0x1584: // Peer connection changed: [index, status]
                if payload.count >= 2 {
                    let idx = Int(payload[0])
                    let isConn = (payload[1] != 0)
                    if let i = self.pairedDevices.firstIndex(where: { $0.id == idx }) {
                        self.pairedDevices[i].isConnected = isConn
                    }
                }
                
            case 0x090D: if let v = payload.first { self.isSmartPauseOn = (v == 1) }
            case 0x1707, 0x1687: if let v = payload.first { self.isTouchControlOn = (v == 0) }
            case 0x0501: if let v = payload.first { self.isOnHeadDetectionOn = (v == 1) }
            case 0x090B: if let v = payload.first { self.isAutoAnswerOn = (v == 1) }
            case 0x0915: if let v = payload.first { self.isComfortCallOn = (v == 1) }
            case 0x0701:
                if payload.count >= 3 && payload[0] == 0 {
                    let secs = (Int(payload[1]) << 8) | Int(payload[2])
                    self.autoPowerOffMinutes = secs / 60
                }
            default: break
            }
        }
    }
}

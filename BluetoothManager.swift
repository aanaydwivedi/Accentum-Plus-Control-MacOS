import Foundation
import IOBluetooth
import Combine
import SwiftUI
import CoreAudio
import AudioToolbox

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

struct EqPresetItem: Identifiable, Hashable, Codable {
    var id = UUID()
    let name: String
    let gains: [Double]
}

final class BluetoothManager: NSObject, ObservableObject, IOBluetoothRFCOMMChannelDelegate {
    @Published var isConnected = false
    @Published var isConnecting = false
    @Published var deviceName = "ACCENTUM Plus"
    @Published var batteryLevel: Int? = nil
    @Published var audioFormatDescription: String = ""
    
    // MARK: - Noise Control State
    @Published var noiseMode: NoiseMode = .custom
    @Published var ancSliderValue: Double = 50.0
    @Published var isAntiWindOn: Bool = false
    @Published var antiWindSetting: AntiWindSetting = .max
    @Published var isPhoneCallTransparencyOn: Bool = false
    @Published var phoneCallTransparencyLevel: Double = 3.0
    @Published var isAutoPauseTransparencyOn: Bool = true
    
    // MARK: - Connection Management (Multipoint)
    @Published var isMultipointEnabled: Bool = UserDefaults.standard.object(forKey: "isMultipointEnabled") as? Bool ?? true
    @Published var pairedDevices: [PairedDevice] = []
    @Published var ownDeviceIndex: Int = 0
    private var lastDisconnectedDeviceId: Int? = nil
    
    // MARK: - My Sound & Equalizer State
    @Published var eqGains: [Double] = [0.0, 0.0, 0.0, 0.0, 0.0]
    @Published var selectedPresetName: String = "Flat"
    @Published var isBassBoostOn: Bool = false
    @Published var isSpeechClarityOn: Bool = false
    @Published var isSoundPersonalizationOn: Bool = false
    @Published var customPresets: [EqPresetItem] = []
    
    let defaultPresets: [EqPresetItem] = [
        EqPresetItem(name: "Wide Airy", gains: [1.5, 0.5, 0.0, 2.0, 3.5]),
        EqPresetItem(name: "Rock", gains: [3.0, 1.0, -0.5, 2.0, 3.5]),
        EqPresetItem(name: "Pop", gains: [-0.5, 1.5, 2.0, 1.5, -0.5]),
        EqPresetItem(name: "Hip Hop", gains: [4.0, 2.0, 0.0, 1.0, 2.5]),
        EqPresetItem(name: "Flat", gains: [0.0, 0.0, 0.0, 0.0, 0.0]),
        EqPresetItem(name: "Movie", gains: [3.5, 1.5, 0.0, 1.5, 0.5])
    ]
    
    // MARK: - Behavior State
    @Published var isSmartPauseOn: Bool = true
    @Published var isTouchControlOn: Bool = true
    @Published var isOnHeadDetectionOn: Bool = true
    @Published var isAutoAnswerOn: Bool = false
    @Published var isComfortCallOn: Bool = true
    @Published var autoPowerOffMinutes: Int = 15
    
    private var rfcommChannel: IOBluetoothRFCOMMChannel?
    private let btQueue = DispatchQueue(label: "com.accentum.bluetooth.queue", qos: .userInitiated)
    private var connectNotification: IOBluetoothUserNotification?
    
    private var rxBuffer = [UInt8]()
    private var sliderDebounceTimer: Timer?
    private var eqDebounceTimer: Timer?
    private var batteryPollTimer: Timer?
    private var autoReconnectTimer: Timer?
    
    override init() {
        super.init()
        loadPresets()
        registerForSystemBluetoothNotifications()
        registerAudioDeviceListener()
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            self?.connectToAccentumPlus()
            self?.startAutoReconnectMonitor()
        }
    }
    
    deinit {
        connectNotification?.unregister()
        batteryPollTimer?.invalidate()
        autoReconnectTimer?.invalidate()
    }
    
    // MARK: - System-Wide Connect Listener
    private func registerForSystemBluetoothNotifications() {
        let selector = #selector(deviceConnectedNotification(notification:device:))
        connectNotification = IOBluetoothDevice.register(forConnectNotifications: self, selector: selector)
    }
    
    @objc private func deviceConnectedNotification(notification: IOBluetoothUserNotification, device: IOBluetoothDevice) {
        if device.name?.localizedCaseInsensitiveContains("ACCENTUM Plus") == true {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                guard let self = self, !self.isConnected else { return }
                self.connectToAccentumPlus()
            }
        }
    }
    
    // MARK: - Non-Blocking Connection Logic
    func connectToAccentumPlus() {
        guard !isConnected && !isConnecting else { return }
        
        DispatchQueue.main.async { self.isConnecting = true }
        
        btQueue.async { [weak self] in
            guard let self = self else { return }
            guard let paired = IOBluetoothDevice.pairedDevices() as? [IOBluetoothDevice] else {
                DispatchQueue.main.async { self.isConnecting = false }
                return
            }
            
            guard let accentum = paired.first(where: {
                $0.name?.localizedCaseInsensitiveContains("ACCENTUM Plus") == true
            }) else {
                DispatchQueue.main.async {
                    self.deviceName = "ACCENTUM Plus not paired"
                    self.isConnecting = false
                }
                return
            }
            
            DispatchQueue.main.async {
                self.deviceName = accentum.name ?? "ACCENTUM Plus"
            }
            
            if !accentum.isConnected() {
                accentum.openConnection()
            }
            
            var channel: IOBluetoothRFCOMMChannel?
            let status = accentum.openRFCOMMChannelSync(&channel, withChannelID: 1, delegate: self)
            
            DispatchQueue.main.async {
                if status == kIOReturnSuccess, let openChannel = channel {
                    self.rfcommChannel = openChannel
                    self.isConnected = true
                    self.isConnecting = false
                    self.registerNotifications()
                    self.readInitialState()
                    self.startPeriodicBatteryPoll()
                    self.updateAudioFormatInfo()
                } else {
                    self.rfcommChannel = nil
                    self.isConnected = false
                    self.isConnecting = false
                }
            }
        }
    }
    
    private func startAutoReconnectMonitor() {
        autoReconnectTimer?.invalidate()
        autoReconnectTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            if !self.isConnected && !self.isConnecting {
                self.connectToAccentumPlus()
            }
        }
    }
    
    // MARK: - RFCOMM Delegate Callbacks
    func rfcommChannelData(_ rfcommChannel: IOBluetoothRFCOMMChannel!, data dataPointer: UnsafeMutableRawPointer!, length dataLength: Int) {
        let buffer = UnsafeBufferPointer(start: dataPointer.assumingMemoryBound(to: UInt8.self), count: dataLength)
        let incomingBytes = Array(buffer)
        
        btQueue.async { [weak self] in
            self?.parseIncomingStream(incomingBytes)
        }
    }
    
    func rfcommChannelClosed(_ rfcommChannel: IOBluetoothRFCOMMChannel!) {
        DispatchQueue.main.async {
            self.isConnected = false
            self.isConnecting = false
            self.batteryLevel = nil
            self.audioFormatDescription = ""
            self.batteryPollTimer?.invalidate()
            self.rfcommChannel = nil
        }
    }
    
    // MARK: - Safe Send
    private func send(command: UInt16, payload: [UInt8] = []) {
        btQueue.async { [weak self] in
            guard let self = self, let channel = self.rfcommChannel, channel.isOpen() else { return }
            var frame = GaiaFrame.encode(command: command, payload: payload)
            let frameLength = UInt16(frame.count)
            frame.withUnsafeMutableBytes { ptr in
                guard let base = ptr.baseAddress else { return }
                channel.writeSync(base, length: frameLength)
            }
        }
    }
    
    // MARK: - Noise Control Actions
    func setNoiseMode(_ mode: NoiseMode) {
        self.noiseMode = mode
        let windVal: UInt8 = isAntiWindOn ? (antiWindSetting == .auto ? 0x02 : 0x01) : 0x00
        
        switch mode {
        case .adaptive:
            send(command: 0x1804, payload: [0x00])
            send(command: 0x1A04, payload: [0x01])
            send(command: 0x1A00, payload: [0x01, windVal, 0x02, 0x00, 0x03, 0x01])
            send(command: 0x1A00, payload: [0x03, 0x01])
            
        case .custom:
            send(command: 0x1A04, payload: [0x01])
            send(command: 0x1A00, payload: [0x01, windVal, 0x02, 0x00, 0x03, 0x00])
            send(command: 0x1A00, payload: [0x03, 0x00])
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
        // Snap behavior: magnetically center at 50 (0 ANC & 0 Transparency)
        var targetValue = value
        if abs(value - 50.0) <= 2.0 {
            targetValue = 50.0
        }
        
        let previousValue = self.ancSliderValue
        self.ancSliderValue = targetValue
        
        // Haptic feedback
        let prevInt = Int(round(previousValue))
        let newInt = Int(round(targetValue))
        if prevInt != newInt {
            if targetValue == 50.0 && previousValue != 50.0 {
                // Centering snap feedback haptic
                NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .default)
            } else {
                // Changing slider haptic feedback
                NSHapticFeedbackManager.defaultPerformer.perform(.levelChange, performanceTime: .default)
            }
        }
        
        if noiseMode != .custom {
            self.noiseMode = .custom
            send(command: 0x1A04, payload: [0x01])
            send(command: 0x1A00, payload: [0x03, 0x00])
        }
        
        sliderDebounceTimer?.invalidate()
        sliderDebounceTimer = Timer.scheduledTimer(withTimeInterval: 0.04, repeats: false) { [weak self] _ in
            guard let self = self else { return }
            let hardwareLevel = UInt8(clamping: Int(round(targetValue)))
            self.send(command: 0x1A02, payload: [hardwareLevel])
        }
    }
    
    func setAntiWind(enabled: Bool, setting: AntiWindSetting? = nil) {
        self.isAntiWindOn = enabled
        if let s = setting { self.antiWindSetting = s }
        let windVal: UInt8 = enabled ? (self.antiWindSetting == .auto ? 0x02 : 0x01) : 0x00
        let adaptiveByte: UInt8 = (noiseMode == .adaptive) ? 0x01 : 0x00
        
        send(command: 0x1A00, payload: [0x01, windVal, 0x02, 0x00, 0x03, adaptiveByte])
        send(command: 0x1A00, payload: [0x01, windVal])
    }
    
    func setPhoneCallTransparency(enabled: Bool, level: Double? = nil) {
        self.isPhoneCallTransparencyOn = enabled
        if let l = level { self.phoneCallTransparencyLevel = l }
        let val: UInt8 = enabled ? UInt8(clamping: Int(self.phoneCallTransparencyLevel)) : 0x00
        send(command: 0x0805, payload: [val])
    }
    
    func setAutoPauseTransparency(_ on: Bool) {
        self.isAutoPauseTransparencyOn = on
        send(command: 0x1800, payload: [on ? 0x01 : 0x00])
    }
    
    // MARK: - Connection Management Actions
    func setMultipointEnabled(_ on: Bool) {
        self.isMultipointEnabled = on
        UserDefaults.standard.set(on, forKey: "isMultipointEnabled")
        send(command: 0x1408, payload: [on ? 0x02 : 0x01])
        
        if !on {
            for device in pairedDevices where !device.isThisDevice && device.isConnected {
                lastDisconnectedDeviceId = device.id
                send(command: 0x1403, payload: [UInt8(clamping: device.id)])
            }
        } else {
            if let targetId = lastDisconnectedDeviceId {
                send(command: 0x1402, payload: [UInt8(clamping: targetId)])
            } else if let secondary = pairedDevices.first(where: { !$0.isThisDevice && !$0.isConnected }) {
                send(command: 0x1402, payload: [UInt8(clamping: secondary.id)])
            }
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
            self.refreshPairedDevices()
        }
    }
    
    func toggleDeviceConnection(_ device: PairedDevice) {
        let devId = UInt8(clamping: device.id)
        if device.isConnected {
            send(command: 0x1403, payload: [devId])
        } else {
            send(command: 0x1402, payload: [devId])
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
            self.refreshPairedDevices()
        }
    }
    
    func removeDevice(_ device: PairedDevice) {
        self.pairedDevices.removeAll(where: { $0.id == device.id })
        let devId = UInt8(clamping: device.id)
        if device.isConnected {
            send(command: 0x1403, payload: [devId])
        }
        send(command: 0x1405, payload: [devId])
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
            self.refreshPairedDevices()
        }
    }
    
    func refreshPairedDevices() {
        send(command: 0x1407)
        send(command: 0x1400)
    }
    
    // MARK: - Graphic EQ & Presets
    func setEqBand(index: Int, gain: Double) {
        guard index >= 0 && index < eqGains.count else { return }
        eqGains[index] = gain
        selectedPresetName = "Custom"
        
        eqDebounceTimer?.invalidate()
        eqDebounceTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: false) { [weak self] _ in
            guard let self = self else { return }
            let rawGain = Int8(clamping: Int(round(gain * 10.0)))
            self.send(command: 0x1001, payload: [UInt8(index), UInt8(bitPattern: rawGain)])
        }
    }
    
    func applyPreset(_ preset: EqPresetItem) {
        selectedPresetName = preset.name
        eqGains = preset.gains
        for (i, gain) in preset.gains.enumerated() {
            DispatchQueue.main.asyncAfter(deadline: .now() + Double(i) * 0.05) { [weak self] in
                guard let self = self else { return }
                let rawGain = Int8(clamping: Int(round(gain * 10.0)))
                self.send(command: 0x1001, payload: [UInt8(i), UInt8(bitPattern: rawGain)])
            }
        }
    }
    
    func readCurrentEqFromHeadphones() {
        send(command: 0x1003, payload: [0x00])
    }
    
    func saveCustomPreset(name: String) {
        let newPreset = EqPresetItem(name: name, gains: eqGains)
        customPresets.removeAll(where: { $0.name.localizedCaseInsensitiveCompare(name) == .orderedSame })
        customPresets.append(newPreset)
        selectedPresetName = name
        savePresets()
    }
    
    func deleteCustomPreset(_ preset: EqPresetItem) {
        customPresets.removeAll(where: { $0.id == preset.id })
        savePresets()
    }
    
    private func savePresets() {
        if let encoded = try? JSONEncoder().encode(customPresets) {
            UserDefaults.standard.set(encoded, forKey: "SennheiserCustomPresets")
        }
    }
    
    private func loadPresets() {
        if let data = UserDefaults.standard.data(forKey: "SennheiserCustomPresets"),
           let decoded = try? JSONDecoder().decode([EqPresetItem].self, from: data) {
            customPresets = decoded
        }
    }
    
    func setBassBoost(_ on: Bool) {
        isBassBoostOn = on
        send(command: 0x1008, payload: [on ? 0x01 : 0x00])
    }
    
    func setSpeechClarity(_ on: Bool) {
        isSpeechClarityOn = on
        if on {
            isSoundPersonalizationOn = false
            send(command: 0x0803, payload: [0x00, 0x02])
        } else {
            send(command: 0x0803, payload: [0x00, 0x01])
        }
    }
    
    func setSoundPersonalization(_ on: Bool) {
        isSoundPersonalizationOn = on
        if on {
            isSpeechClarityOn = false
            send(command: 0x0803, payload: [0x00, 0x03])
        } else {
            send(command: 0x0803, payload: [0x00, 0x01])
        }
    }
    
    // MARK: - Behavior Actions
    func setSmartPause(_ on: Bool) {
        self.isSmartPauseOn = on
        send(command: 0x080C, payload: [on ? 1 : 0])
    }
    func setTouchControls(_ on: Bool) {
        self.isTouchControlOn = on
        send(command: 0x1606, payload: [on ? 0 : 1])
    }
    func setOnHeadDetection(_ on: Bool) {
        isOnHeadDetectionOn = on
        send(command: 0x0400, payload: [on ? 1 : 0])
    }
    func setAutoAnswer(_ on: Bool) {
        self.isAutoAnswerOn = on
        send(command: 0x080A, payload: [on ? 1 : 0])
    }
    func setComfortCall(_ on: Bool) {
        self.isComfortCallOn = on
        send(command: 0x0814, payload: [on ? 1 : 0])
    }
    func setAutoPowerOff(minutes: Int) {
        self.autoPowerOffMinutes = minutes
        let seconds = minutes * 60
        send(command: 0x0600, payload: [0x00, UInt8((seconds >> 8) & 0xFF), UInt8(seconds & 0xFF)])
    }
    
    // MARK: - Codec, kHz & Wired Detection (CoreAudio)
    private func registerAudioDeviceListener() {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: AudioObjectPropertyElement(kAudioObjectPropertyElementMain)
        )
        AudioObjectAddPropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            DispatchQueue.global(qos: .utility)
        ) { [weak self] _, _ in
            self?.updateAudioFormatInfo()
        }
    }
    
    func updateAudioFormatInfo() {
        var defaultOutputDeviceID = AudioDeviceID(0)
        var propertySize = UInt32(MemoryLayout<AudioDeviceID>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: AudioObjectPropertyElement(kAudioObjectPropertyElementMain)
        )
        
        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            &propertySize,
            &defaultOutputDeviceID
        )
        
        guard status == noErr, defaultOutputDeviceID != 0 else {
            DispatchQueue.main.async {
                self.audioFormatDescription = "AAC • 48 kHz"
            }
            return
        }
        
        // Check all audio devices to inspect if Accentum Plus is plugged in via USB-C
        var allDevsSize: UInt32 = 0
        address.mSelector = kAudioHardwarePropertyDevices
        AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &allDevsSize)
        let count = Int(allDevsSize) / MemoryLayout<AudioDeviceID>.size
        var devIDs = [AudioDeviceID](repeating: 0, count: count)
        AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &allDevsSize, &devIDs)
        
        var targetDeviceID = defaultOutputDeviceID
        var isUSBWire = false
        
        for devID in devIDs {
            var nameCF: CFString = "" as CFString
            var strSize = UInt32(MemoryLayout<CFString>.size)
            var nameAddr = AudioObjectPropertyAddress(
                mSelector: kAudioObjectPropertyName,
                mScope: kAudioObjectPropertyScopeGlobal,
                mElement: AudioObjectPropertyElement(kAudioObjectPropertyElementMain)
            )
            if AudioObjectGetPropertyData(devID, &nameAddr, 0, nil, &strSize, &nameCF) == noErr {
                let name = nameCF as String
                if name.localizedCaseInsensitiveContains("ACCENTUM Plus") {
                    var trans: UInt32 = 0
                    var transSize = UInt32(MemoryLayout<UInt32>.size)
                    var transAddr = AudioObjectPropertyAddress(
                        mSelector: kAudioDevicePropertyTransportType,
                        mScope: kAudioObjectPropertyScopeGlobal,
                        mElement: AudioObjectPropertyElement(kAudioObjectPropertyElementMain)
                    )
                    if AudioObjectGetPropertyData(devID, &transAddr, 0, nil, &transSize, &trans) == noErr {
                        if trans == kAudioDeviceTransportTypeUSB {
                            targetDeviceID = devID
                            isUSBWire = true
                            break
                        }
                    }
                }
            }
        }
        
        // Query Name, Transport Type, and Nominal Sample Rate
        var nameCF: CFString = "" as CFString
        var strSize = UInt32(MemoryLayout<CFString>.size)
        var nameAddr = AudioObjectPropertyAddress(
            mSelector: kAudioObjectPropertyName,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: AudioObjectPropertyElement(kAudioObjectPropertyElementMain)
        )
        _ = AudioObjectGetPropertyData(targetDeviceID, &nameAddr, 0, nil, &strSize, &nameCF)
        let matchedName = nameCF as String
        
        var trans: UInt32 = 0
        var transSize = UInt32(MemoryLayout<UInt32>.size)
        var transAddr = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyTransportType,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: AudioObjectPropertyElement(kAudioObjectPropertyElementMain)
        )
        _ = AudioObjectGetPropertyData(targetDeviceID, &transAddr, 0, nil, &transSize, &trans)
        
        var sampleRate: Float64 = 48000.0
        var srSize = UInt32(MemoryLayout<Float64>.size)
        var srAddr = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyNominalSampleRate,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: AudioObjectPropertyElement(kAudioObjectPropertyElementMain)
        )
        _ = AudioObjectGetPropertyData(targetDeviceID, &srAddr, 0, nil, &srSize, &sampleRate)
        
        let khzStr: String
        if sampleRate > 0 {
            if sampleRate.truncatingRemainder(dividingBy: 1000) == 0 {
                khzStr = "\(Int(sampleRate / 1000)) kHz"
            } else {
                khzStr = String(format: "%.1f kHz", sampleRate / 1000.0)
            }
        } else {
            khzStr = "48 kHz"
        }
        
        let formatDesc: String
        if isUSBWire || trans == kAudioDeviceTransportTypeUSB {
            formatDesc = "Wired (USB-C) • \(khzStr)"
        } else if matchedName.localizedCaseInsensitiveContains("Headphone") || trans == kAudioDeviceTransportTypeBuiltIn {
            formatDesc = "Wired (AUX) • \(khzStr)"
        } else {
            formatDesc = "AAC • \(khzStr)"
        }
        
        DispatchQueue.main.async {
            self.audioFormatDescription = formatDesc
        }
    }
    
    // MARK: - Initialization Queries
    private func registerNotifications() {
        let notificationIds: [UInt8] = [0x03, 0x0D, 0x0C, 0x08, 0x0A, 0x0B, 0x04, 0x02]
        for nid in notificationIds {
            send(command: 0x0007, payload: [nid])
        }
    }
    
    private func readInitialState() {
        let commands: [(UInt16, [UInt8])] = [
            (0x0603, []),
            (0x1A05, []),
            (0x1A01, []),
            (0x1A03, []),
            (0x1801, []),
            (0x0806, []),
            (0x1003, [0x00]),
            (0x1009, []),
            (0x0804, []),
            (0x1409, []),
            (0x1407, []),
            (0x1400, []),
            (0x080D, []),
            (0x1607, []),
            (0x0401, []),
            (0x080B, []),
            (0x0815, []),
            (0x0601, [0x00])
        ]
        
        for (i, item) in commands.enumerated() {
            DispatchQueue.main.asyncAfter(deadline: .now() + Double(i) * 0.05) { [weak self] in
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
            self.updateAudioFormatInfo()
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
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            switch commandId {
            case 0x0703, 0x0683:
                if let b = payload.first { self.batteryLevel = Int(b) }
                
            case 0x1B01, 0x1A81:
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
                
            case 0x1B05, 0x1A85:
                if let val = payload.first, val == 0 { self.noiseMode = .off }
                
            case 0x1B03, 0x1A83:
                if let level = payload.first, self.noiseMode == .custom {
                    self.ancSliderValue = Double(level)
                }
                
            case 0x1901:
                if let val = payload.first { self.isAutoPauseTransparencyOn = (val == 1) }
                
            case 0x0906:
                if let s = payload.first {
                    self.isPhoneCallTransparencyOn = (s > 0)
                    if s > 0 { self.phoneCallTransparencyLevel = Double(min(5, max(1, s))) }
                }
                
            case 0x1103:
                if payload.count >= 5 {
                    self.eqGains = (0..<5).map { Double(Int8(bitPattern: payload[$0])) / 10.0 }
                }
                
            case 0x1109, 0x1089:
                if let val = payload.first { self.isBassBoostOn = (val == 1) }
                
            case 0x0904, 0x0884:
                if payload.count >= 2 {
                    let mode = payload[1]
                    self.isSpeechClarityOn = (mode == 2)
                    self.isSoundPersonalizationOn = (mode == 3)
                }
                
            case 0x1507:
                if let own = payload.first { self.ownDeviceIndex = Int(own) }
                
            case 0x1500:
                if payload.count >= 2 {
                    let count = (Int(payload[0]) << 8) | Int(payload[1])
                    for idx in 0..<count {
                        DispatchQueue.main.asyncAfter(deadline: .now() + Double(idx) * 0.08) {
                            self.send(command: 0x1401, payload: [UInt8(idx)])
                        }
                    }
                }
                
            case 0x1501:
                if payload.count >= 4 {
                    let idx = Int(payload[0])
                    let isConn = (payload[2] != 0)
                    let nameBytes = payload[3...].prefix(while: { $0 != 0 })
                    let rawName = String(bytes: nameBytes, encoding: .utf8) ?? ""
                    let cleanedName = rawName.trimmingCharacters(in: .whitespacesAndNewlines.union(.controlCharacters))
                    
                    if cleanedName.count >= 2 {
                        let item = PairedDevice(id: idx, name: cleanedName, isConnected: isConn, isThisDevice: idx == self.ownDeviceIndex)
                        if let existing = self.pairedDevices.firstIndex(where: { $0.id == idx }) {
                            self.pairedDevices[existing] = item
                        } else {
                            self.pairedDevices.append(item)
                        }
                        self.pairedDevices.sort { $0.id < $1.id }
                    }
                }
                
            case 0x1584:
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

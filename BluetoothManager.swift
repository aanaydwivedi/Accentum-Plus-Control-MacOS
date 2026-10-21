import Foundation
import IOBluetooth
import Combine

enum NoiseMode: String, CaseIterable, Identifiable {
    case adaptive = "Adaptive"
    case custom = "Custom"
    case off = "Off"
    
    var id: String { rawValue }
}

class BluetoothManager: NSObject, ObservableObject, IOBluetoothRFCOMMChannelDelegate {
    @Published var isConnected = false
    @Published var deviceName = "ACCENTUM Plus"
    @Published var batteryLevel: Int? = nil
    
    // Noise Control
    @Published var noiseMode: NoiseMode = .custom
    // ancSliderValue matches the hardware 0x1A02 register:
    // 0 = 100% ANC | 50 = Center (0% ANC / 0% Transparency) | 100 = 100% Transparency
    @Published var ancSliderValue: Double = 50.0
    @Published var isAntiWindOn: Bool = false
    
    // Behavior State
    @Published var isSmartPauseOn: Bool = true
    @Published var isTouchControlOn: Bool = true
    @Published var isOnHeadDetectionOn: Bool = true
    @Published var isAutoAnswerOn: Bool = false
    @Published var isComfortCallOn: Bool = true
    @Published var autoPowerOffMinutes: Int = 15
    
    private var rfcommChannel: IOBluetoothRFCOMMChannel?
    let vendorSennheiser: UInt16 = 0x0495
    
    // Stream buffer for concatenated/split packets
    private var rxBuffer = [UInt8]()
    private var sliderDebounceTimer: Timer?
    private var batteryPollTimer: Timer?
    
    func connectToAccentumPlus() {
        guard let pairedDevices = IOBluetoothDevice.pairedDevices() as? [IOBluetoothDevice] else { return }
        
        guard let accentum = pairedDevices.first(where: {
            ($0.name?.localizedCaseInsensitiveContains("ACCENTUM Plus") == true)
        }) else {
            deviceName = "ACCENTUM Plus not found"
            return
        }
        
        deviceName = accentum.name ?? "ACCENTUM Plus"
        accentum.openRFCOMMChannelSync(&rfcommChannel, withChannelID: 1, delegate: self)
        
        if rfcommChannel != nil {
            DispatchQueue.main.async {
                self.isConnected = true
            }
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
    
    // MARK: - Safe RFCOMM Write
    private func send(command: UInt16, payload: [UInt8] = []) {
        var frame = GaiaFrame.encode(command: command, payload: payload)
        let frameLength = UInt16(frame.count)
        frame.withUnsafeMutableBytes { ptr in
            guard let baseAddress = ptr.baseAddress else { return }
            rfcommChannel?.writeSync(baseAddress, length: frameLength)
        }
    }
    
    // MARK: - Noise Control Actions
    func setNoiseMode(_ mode: NoiseMode) {
        self.noiseMode = mode
        let wind: UInt8 = isAntiWindOn ? 0x01 : 0x00
        
        switch mode {
        case .adaptive:
            send(command: 0x1804, payload: [0x00]) // Transparency Off
            send(command: 0x1A04, payload: [0x01]) // ANC On
            // 6-byte table: [Anti-wind, Comfort: 0, Adaptive: 1]
            send(command: 0x1A00, payload: [0x01, wind, 0x02, 0x00, 0x03, 0x01])
            
        case .custom:
            send(command: 0x1A04, payload: [0x01]) // ANC On
            // Adaptive Off unlocks manual level slider
            send(command: 0x1A00, payload: [0x01, wind, 0x02, 0x00, 0x03, 0x00])
            
            // Re-apply current hardware slider position
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                let hardwareLevel = UInt8(clamping: Int(round(self.ancSliderValue)))
                self.send(command: 0x1A02, payload: [hardwareLevel])
            }
            
        case .off:
            send(command: 0x1A04, payload: [0x00]) // ANC Off
            send(command: 0x1804, payload: [0x00]) // Transparency Off
        }
    }
    
    func setSliderValue(_ value: Double) {
        self.ancSliderValue = value
        
        if noiseMode != .custom {
            self.noiseMode = .custom
            let wind: UInt8 = isAntiWindOn ? 0x01 : 0x00
            send(command: 0x1A04, payload: [0x01])
            send(command: 0x1A00, payload: [0x01, wind, 0x02, 0x00, 0x03, 0x00])
        }
        
        sliderDebounceTimer?.invalidate()
        sliderDebounceTimer = Timer.scheduledTimer(withTimeInterval: 0.03, repeats: false) { [weak self] _ in
            guard let self = self else { return }
            // 0x1A02 hardware register directly represents the slider: 0 (Max ANC) ... 50 (Neutral) ... 100 (Max Transparency)
            let hardwareLevel = UInt8(clamping: Int(round(value)))
            self.send(command: 0x1A02, payload: [hardwareLevel])
        }
    }
    
    func setAntiWind(_ on: Bool) {
        self.isAntiWindOn = on
        let adaptiveByte: UInt8 = (noiseMode == .adaptive) ? 0x01 : 0x00
        send(command: 0x1A00, payload: [0x01, on ? 0x01 : 0x00, 0x02, 0x00, 0x03, adaptiveByte])
    }
    
    // MARK: - Behavior Actions
    func setSmartPause(_ on: Bool) {
        self.isSmartPauseOn = on
        send(command: 0x080C, payload: [on ? 1 : 0])
    }
    
    func setTouchControls(_ on: Bool) {
        self.isTouchControlOn = on
        send(command: 0x1606, payload: [on ? 0 : 1]) // Inverted: 0 = active, 1 = locked
    }
    
    func setOnHeadDetection(_ on: Bool) {
        self.isOnHeadDetectionOn = on
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
    
    // MARK: - Initial Queries & Periodic Battery Polling
    private func registerNotifications() {
        send(command: 0x0007, payload: [0x03]) // Battery
        send(command: 0x0007, payload: [0x0D]) // ANC
        send(command: 0x0007, payload: [0x0C]) // Transparency
        send(command: 0x0007, payload: [0x0B]) // Touch Lock
        send(command: 0x0007, payload: [0x02]) // Wear State
    }
    
    private func readInitialState() {
        let commands: [(UInt16, [UInt8])] = [
            (0x0603, []),           // Battery
            (0x1A05, []),           // ANC Enabled
            (0x1A01, []),           // ANC Modes
            (0x1A03, []),           // ANC Level
            (0x080D, []),           // Smart Pause
            (0x1607, []),           // Touch Lock
            (0x0401, []),           // On-Head Detection
            (0x080B, []),           // Auto Answer
            (0x0815, []),           // Comfort Call
            (0x0601, [0x00])        // Auto Power Off
        ]
        
        for (index, item) in commands.enumerated() {
            DispatchQueue.main.asyncAfter(deadline: .now() + Double(index) * 0.05) { [weak self] in
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
            if sofIndex > 0 {
                rxBuffer.removeSubrange(0..<sofIndex)
            }
            guard rxBuffer.count >= 8 else { return }
            guard rxBuffer[1] == 0x03 else {
                rxBuffer.removeFirst()
                continue
            }
            
            let flags = rxBuffer[2]
            let payloadLength = Int(rxBuffer[3])
            let totalFrameLen = 8 + payloadLength + ((flags & 0x01) != 0 ? 1 : 0)
            
            guard rxBuffer.count >= totalFrameLen else { return }
            
            let commandId = (UInt16(rxBuffer[6]) << 8) | UInt16(rxBuffer[7])
            let payload = Array(rxBuffer[8..<(8 + payloadLength)])
            rxBuffer.removeSubrange(0..<totalFrameLen)
            
            dispatchFrame(commandId: commandId, payload: payload)
        }
    }
    
    private func dispatchFrame(commandId: UInt16, payload: [UInt8]) {
        DispatchQueue.main.async {
            switch commandId {
            case 0x0703, 0x0683: // Battery Level Response / Notification
                if let level = payload.first {
                    self.batteryLevel = Int(level)
                }
                
            case 0x1B01, 0x1A81: // ANC Mode Table
                var i = 0
                while i + 1 < payload.count {
                    let modeId = payload[i]
                    let val = payload[i+1]
                    if modeId == 0x01 { self.isAntiWindOn = (val >= 1) }
                    if modeId == 0x03 && val == 1 { self.noiseMode = .adaptive }
                    i += 2
                }
                
            case 0x1B05, 0x1A85: // ANC Enabled
                if let val = payload.first, val == 0 {
                    self.noiseMode = .off
                }
                
            case 0x1B03, 0x1A83: // Current ANC/Transparency Level (0 to 100)
                if let level = payload.first, self.noiseMode == .custom {
                    self.ancSliderValue = Double(level)
                }
                
            case 0x090D: // Smart Pause
                if let val = payload.first { self.isSmartPauseOn = (val == 1) }
            case 0x1707, 0x1687: // Touch Lock
                if let val = payload.first { self.isTouchControlOn = (val == 0) }
            case 0x0501: // On-Head Detection
                if let val = payload.first { self.isOnHeadDetectionOn = (val == 1) }
            case 0x090B: // Auto-Answer
                if let val = payload.first { self.isAutoAnswerOn = (val == 1) }
            case 0x0915: // Comfort Call
                if let val = payload.first { self.isComfortCallOn = (val == 1) }
            case 0x0701: // Auto Power Off
                if payload.count >= 3 && payload[0] == 0 {
                    let secs = (Int(payload[1]) << 8) | Int(payload[2])
                    self.autoPowerOffMinutes = secs / 60
                }
            default:
                break
            }
        }
    }
}

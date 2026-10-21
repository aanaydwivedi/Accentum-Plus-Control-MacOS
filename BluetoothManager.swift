import Foundation
import IOBluetooth
import Combine

enum NoiseMode: String, CaseIterable, Identifiable {
    case anc = "ANC"
    case adaptive = "Adaptive"
    case transparency = "Transparency"
    case off = "Off"
    
    var id: String { rawValue }
}

class BluetoothManager: NSObject, ObservableObject, IOBluetoothRFCOMMChannelDelegate {
    @Published var isConnected = false
    @Published var deviceName = "ACCENTUM Plus"
    @Published var batteryLevel: Int? = nil
    
    // Noise Control State
    @Published var noiseMode: NoiseMode = .anc
    @Published var isAncEnabled = true
    @Published var isTransparencyOn = false
    @Published var isAdaptiveAnc = false
    @Published var ancStrength: Double = 100.0          // 0 to 100% (100 = max noise cancellation)
    @Published var transparencyLevel: Double = 100.0    // 0 to 100% (ambient volume)
    
    // Behavior State
    @Published var isSmartPauseOn: Bool = true
    @Published var isTouchControlOn: Bool = true
    @Published var isOnHeadDetectionOn: Bool = true
    @Published var isAutoAnswerOn: Bool = false
    @Published var isComfortCallOn: Bool = true
    @Published var autoPowerOffMinutes: Int = 15
    
    private var rfcommChannel: IOBluetoothRFCOMMChannel?
    let vendorSennheiser: UInt16 = 0x0495
    
    // Streaming RX buffer for reassembling fragmented or concatenated packets
    private var rxBuffer = [UInt8]()
    
    // Debounce timer for slider gestures to avoid flooding Bluetooth
    private var ancDebounceTimer: Timer?
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
        
        // Open RFCOMM Channel 1
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
    
    // MARK: - Safe RFCOMM Sending
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
        switch mode {
        case .anc:
            self.isTransparencyOn = false
            self.isAncEnabled = true
            self.isAdaptiveAnc = false
            
            send(command: 0x1804, payload: [0x00])                         // Transparency Off
            send(command: 0x1A04, payload: [0x01])                         // ANC On
            
            // Set 6-byte ANC mode table: [Anti-wind: Off (0), Comfort: Off (0), Adaptive: Off (0)]
            // Turning Adaptive and Anti-Wind off unlocks manual ANC control via 0x1A02
            send(command: 0x1A00, payload: [0x01, 0x00, 0x02, 0x00, 0x03, 0x00])
            
            // Apply current slider level after table initialization
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
                let hardwareLevel = UInt8(clamping: 100 - Int(self.ancStrength))
                self.send(command: 0x1A02, payload: [hardwareLevel])
            }
            
        case .adaptive:
            self.isTransparencyOn = false
            self.isAncEnabled = true
            self.isAdaptiveAnc = true
            send(command: 0x1804, payload: [0x00])                         // Transparency Off
            send(command: 0x1A04, payload: [0x01])                         // ANC On
            send(command: 0x1A00, payload: [0x01, 0x01, 0x02, 0x00, 0x03, 0x01]) // Adaptive On
            
        case .transparency:
            self.isTransparencyOn = true
            self.isAncEnabled = true
            send(command: 0x1A04, payload: [0x01])                         // ANC Enabled
            send(command: 0x1804, payload: [0x01])                         // Transparency On
            setTransparencyLevel(Int(transparencyLevel))
            
        case .off:
            self.isTransparencyOn = false
            self.isAncEnabled = false
            send(command: 0x1A04, payload: [0x00])                         // ANC Off
            send(command: 0x1804, payload: [0x00])                         // Transparency Off
        }
    }
    
    func toggleTransparency(_ on: Bool) {
        setNoiseMode(on ? .transparency : .anc)
    }
    
    func setAncStrength(_ strength: Int) {
        self.ancStrength = Double(strength)
        
        // Debounce to avoid flooding the Bluetooth link while dragging
        ancDebounceTimer?.invalidate()
        ancDebounceTimer = Timer.scheduledTimer(withTimeInterval: 0.04, repeats: false) { [weak self] _ in
            guard let self = self else { return }
            // 0x1A02: 0 = Max ANC, 100 = Min ANC
            let hardwareLevel = UInt8(clamping: 100 - strength)
            self.send(command: 0x1A02, payload: [hardwareLevel])
        }
    }
    
    func setTransparencyLevel(_ level: Int) {
        self.transparencyLevel = Double(level)
        let clamped = UInt8(clamping: level)
        send(command: 0x1802, payload: [clamped])
    }
    
    // MARK: - Behavior Actions
    func setSmartPause(_ on: Bool) {
        self.isSmartPauseOn = on
        send(command: 0x080C, payload: [on ? 1 : 0])
    }
    
    func setTouchControls(_ on: Bool) {
        self.isTouchControlOn = on
        send(command: 0x1606, payload: [on ? 0 : 1]) // 0 = active, 1 = locked
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
    
    // MARK: - Initial State & Subscriptions
    private func registerNotifications() {
        send(command: 0x0007, payload: [0x03]) // Battery
        send(command: 0x0007, payload: [0x0D]) // ANC
        send(command: 0x0007, payload: [0x0C]) // Transparent Hearing
        send(command: 0x0007, payload: [0x0B]) // MMI / Touch
        send(command: 0x0007, payload: [0x02]) // Device State
    }
    
    private func readInitialState() {
        let commands: [(UInt16, [UInt8])] = [
            (0x0603, []),           // Battery
            (0x1A05, []),           // ANC Enabled
            (0x1A01, []),           // ANC Modes
            (0x1A03, []),           // ANC Level
            (0x1805, []),           // Transparency Status
            (0x1803, []),           // Transparency Level
            (0x080D, []),           // Smart Pause
            (0x1607, []),           // Touch Lock
            (0x0401, []),           // On-Head Detection
            (0x080B, []),           // Auto Answer
            (0x0815, []),           // Comfort Call
            (0x0601, [0x00])        // Auto Power Off
        ]
        
        // Stagger initial reads by 60ms so UART buffers never drop packets
        for (index, item) in commands.enumerated() {
            DispatchQueue.main.asyncAfter(deadline: .now() + Double(index) * 0.06) { [weak self] in
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
    
    // MARK: - Streaming Frame Parser
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
            
            guard rxBuffer.count >= totalFrameLen else {
                return // Wait for the remaining bytes
            }
            
            let commandId = (UInt16(rxBuffer[6]) << 8) | UInt16(rxBuffer[7])
            let payload = Array(rxBuffer[8..<(8 + payloadLength)])
            rxBuffer.removeSubrange(0..<totalFrameLen)
            
            dispatchFrame(commandId: commandId, payload: payload)
        }
    }
    
    private func dispatchFrame(commandId: UInt16, payload: [UInt8]) {
        DispatchQueue.main.async {
            switch commandId {
            case 0x0703, 0x0683: // Battery
                if let level = payload.first {
                    self.batteryLevel = Int(level)
                }
                
            case 0x1B05, 0x1A85: // ANC Enabled
                if let val = payload.first {
                    self.isAncEnabled = (val == 1)
                    self.syncNoiseMode()
                }
                
            case 0x1B01, 0x1A81: // ANC Mode Table
                var i = 0
                while i + 1 < payload.count {
                    if payload[i] == 0x03 { self.isAdaptiveAnc = (payload[i+1] == 1) }
                    i += 2
                }
                self.syncNoiseMode()
                
            case 0x1B03, 0x1A83: // ANC Level
                if let level = payload.first {
                    self.ancStrength = 100.0 - Double(level)
                }
                
            case 0x1905, 0x1885: // Transparent Hearing Status
                if let val = payload.first {
                    self.isTransparencyOn = (val == 1)
                    self.syncNoiseMode()
                }
                
            case 0x1903: // Transparency Level
                if let level = payload.first {
                    self.transparencyLevel = Double(level)
                }
                
            case 0x090D: // Smart Pause
                if let val = payload.first { self.isSmartPauseOn = (val == 1) }
                
            case 0x1707, 0x1687: // Touch Lock (0 = on)
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
    
    private func syncNoiseMode() {
        if !isAncEnabled {
            noiseMode = .off
        } else if isTransparencyOn {
            noiseMode = .transparency
        } else if isAdaptiveAnc {
            noiseMode = .adaptive
        } else {
            noiseMode = .anc
        }
    }
}

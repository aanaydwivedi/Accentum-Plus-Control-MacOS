//
//  BluetoothManager.swift
//  MyApp
//
//  Created by Aanay Dwivedi on 21/10/26.
//


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
    @Published var ancStrength: Double = 100.0          // 0 to 100% (100 = strongest ANC)
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
    
    func connectToAccentumPlus() {
        guard let pairedDevices = IOBluetoothDevice.pairedDevices() as? [IOBluetoothDevice] else { return }
        
        guard let accentum = pairedDevices.first(where: {
            ($0.name?.contains("ACCENTUM Plus") == true) || ($0.name?.contains("Accentum Plus") == true)
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
        }
    }
    
    func rfcommChannelData(_ rfcommChannel: IOBluetoothRFCOMMChannel!, data dataPointer: UnsafeMutableRawPointer!, length dataLength: Int) {
        let buffer = UnsafeBufferPointer(start: dataPointer.assumingMemoryBound(to: UInt8.self), count: dataLength)
        handleIncomingData(Array(buffer))
    }
    
    func rfcommChannelClosed(_ rfcommChannel: IOBluetoothRFCOMMChannel!) {
        DispatchQueue.main.async {
            self.isConnected = false
            self.batteryLevel = nil
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
            send(command: 0x1A00, payload: [0x03, 0x00])                   // Adaptive Off
            setAncStrength(Int(ancStrength))
            
        case .adaptive:
            self.isTransparencyOn = false
            self.isAncEnabled = true
            self.isAdaptiveAnc = true
            send(command: 0x1804, payload: [0x00])                         // Transparency Off
            send(command: 0x1A04, payload: [0x01])                         // ANC On
            send(command: 0x1A00, payload: [0x03, 0x01])                   // Adaptive On
            
        case .transparency:
            self.isTransparencyOn = true
            self.isAncEnabled = true
            send(command: 0x1A04, payload: [0x01])                         // ANC must be enabled
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
        // Ensure Adaptive mode is disabled so the hardware level register applies
        send(command: 0x1A00, payload: [0x03, 0x00])
        // 0x1A02 expects inverted level: 0 = Max ANC, 100 = Min ANC
        let hardwareLevel = UInt8(clamping: 100 - strength)
        send(command: 0x1A02, payload: [hardwareLevel])
    }
    
    func setTransparencyLevel(_ level: Int) {
        self.transparencyLevel = Double(level)
        let clamped = UInt8(clamping: level)
        send(command: 0x1802, payload: [clamped]) // 0x1802 controls transparency ambient volume
    }
    
    // MARK: - Behavior Actions (Immediate Optimistic Updates)
    func setSmartPause(_ on: Bool) {
        self.isSmartPauseOn = on
        send(command: 0x080C, payload: [on ? 1 : 0])
    }
    
    func setTouchControls(_ on: Bool) {
        self.isTouchControlOn = on
        // Touch lock is inverted on Sennheiser hardware: 0 = active, 1 = locked
        send(command: 0x1606, payload: [on ? 0 : 1])
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
        send(command: 0x0007, payload: [0x03]) // Battery (Feature 3)
        send(command: 0x0007, payload: [0x0D]) // ANC (Feature 13)
        send(command: 0x0007, payload: [0x0C]) // Transparent Hearing (Feature 12)
        send(command: 0x0007, payload: [0x0B]) // MMI / Touch Lock (Feature 11)
        send(command: 0x0007, payload: [0x02]) // Device Wear State (Feature 2)
    }
    
    private func readInitialState() {
        send(command: 0x0603)                   // Battery
        send(command: 0x1A05)                   // ANC Enabled
        send(command: 0x1A01)                   // ANC Mode table
        send(command: 0x1A03)                   // ANC Level
        send(command: 0x1805)                   // Transparent Hearing Status
        send(command: 0x1803)                   // Transparent Hearing Level
        send(command: 0x080D)                   // Smart Pause
        send(command: 0x1607)                   // Touch Lock
        send(command: 0x0401)                   // On-head Detection
        send(command: 0x080B)                   // Auto Answer
        send(command: 0x0815)                   // Comfort Call
        send(command: 0x0601, payload: [0x00])  // Timer (Auto power-off)
    }
    
    private func handleIncomingData(_ data: [UInt8]) {
        guard data.count >= 8, data[0] == 0xFF, data[1] == 0x03 else { return }
        let commandId = (UInt16(data[6]) << 8) | UInt16(data[7])
        let payload = Array(data[8...])
        
        DispatchQueue.main.async {
            switch commandId {
            case 0x0703, 0x0683: // Battery
                if let level = payload.first { self.batteryLevel = Int(level) }
                
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
                if let level = payload.first { self.ancStrength = 100.0 - Double(level) }
                
            case 0x1905, 0x1885: // Transparent Hearing
                if let val = payload.first {
                    self.isTransparencyOn = (val == 1)
                    self.syncNoiseMode()
                }
                
            case 0x1903: // Transparency Level
                if let level = payload.first { self.transparencyLevel = Double(level) }
                
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
                if payload.count >= 3, payload[0] == 0 {
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

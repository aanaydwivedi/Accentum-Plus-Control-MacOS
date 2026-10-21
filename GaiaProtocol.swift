//
//  Untitled.swift
//  MyApp
//
//  Created by Aanay Dwivedi on 21/10/26.
//
import Foundation

enum PacketType: UInt8 {
    case command = 0
    case notification = 1
    case response = 2
    case error = 3
}

struct CommandWord {
    let value: UInt16
    var feature: UInt8 { UInt8(value >> 9) }
    var type: PacketType { PacketType(rawValue: UInt8((value >> 7) & 0x03))! }
    var number: UInt8 { UInt8(value & 0x7F) }
}

struct GaiaFrame {
    // Sennheiser Vendor ID is 0x0495
    static let vendorSennheiser: UInt16 = 0x0495
    
    static func encode(command: UInt16, payload: [UInt8] = []) -> [UInt8] {
        var frame: [UInt8] = [0xFF, 0x03, 0x00, UInt8(payload.count)]
        frame.append(UInt8(vendorSennheiser >> 8))
        frame.append(UInt8(vendorSennheiser & 0xFF))
        frame.append(UInt8(command >> 8))
        frame.append(UInt8(command & 0xFF))
        frame.append(contentsOf: payload)
        return frame
    }
}

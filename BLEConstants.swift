import Foundation
import CoreBluetooth

enum BLEConstants {
    static let stepServiceUUID = CBUUID(string: "19B10010-E8F2-537E-4F6C-D104768A1214")

    static let scanServiceUUIDs: [CBUUID]? = [stepServiceUUID]

    static let connectionTimeout: TimeInterval = 20
    static let scanDuration: TimeInterval = 15
    static let maximumLogEntries = 100

    static func serviceName(for uuid: CBUUID) -> String? {
        switch uuid.uuidString.uppercased() {
        case "1800": return "Generic Access"
        case "1801": return "Generic Attribute"
        case "180A": return "Device Information"
        case "180F": return "Battery Service"
        case "181A": return "Environmental Sensing"
        default: return nil
        }
    }
}

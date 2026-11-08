import Foundation

/// Follows CC 99 / 98 / 6 / 38 on one channel and reports complete NRPN values.
///
/// One-byte parameters are complete on CC 6 (Data Entry MSB). Two-byte parameters wait for
/// CC 38 (Data Entry LSB), which the manual's example sends right after CC 6
/// ("Bx 06 03 Bx 26 3A" for Master Tune 442 Hz). A later CC 38 on its own updates the low
/// bits of the last value, as MIDI allows.
public struct NRPNDecoder {
    public typealias LengthLookup = (_ msb: UInt8, _ lsb: UInt8) -> Int?

    private var msb: UInt8? = nil
    private var lsb: UInt8? = nil
    private var dataMSB: Int? = nil
    private let length: LengthLookup

    public init(length: @escaping LengthLookup) { self.length = length }

    public struct Value: Equatable {
        public let msb: UInt8
        public let lsb: UInt8
        public let raw: Int
    }

    /// Feed one control change; returns a value when one is complete.
    public mutating func handle(controller: Int, value: Int) -> Value? {
        switch controller {
        case 99:
            msb = UInt8(value); dataMSB = nil
            if value == 127 { msb = nil; lsb = nil }
        case 98:
            lsb = UInt8(value); dataMSB = nil
            if value == 127 { msb = nil; lsb = nil }
        case 6:
            guard let m = msb, let l = lsb, let len = length(m, l) else { dataMSB = nil; return nil }
            if len == 2 {
                dataMSB = value
            } else {
                dataMSB = nil
                return Value(msb: m, lsb: l, raw: value)
            }
        case 38:
            guard let m = msb, let l = lsb, let hi = dataMSB, length(m, l) == 2 else { return nil }
            return Value(msb: m, lsb: l, raw: hi << 7 | value)
        case 101, 100:
            // RPN selected: NRPN data entry no longer applies.
            msb = nil; lsb = nil; dataMSB = nil
        case 121:
            // Reset All Controllers: "NRPN: unset" (p. 176).
            msb = nil; lsb = nil; dataMSB = nil
        default:
            break
        }
        return nil
    }
}

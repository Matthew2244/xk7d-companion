import Foundation

/// Patch names: the factory table, reading names out of a Temporary dump, and the spoken line.
///
/// Factory patches F00-F99 can't be changed (p. 35, "cannot be changed"), so their names come from
/// the Factory Patches table (pp. 172-173): Upper names in one column, Lower and Pedal in the
/// other. User patches U00-U99 start as copies of them but can be renamed, so their names have to
/// come from the organ: a Name Data Set it sends, or a Temporary dump (see HANDOFF.md).
public enum PatchNames {
    /// F00-F99, the UPPER Name column of pp. 172-173 (the trailing "U" part marker left off).
    public static let factoryUpper: [String] = [
        "Dr. L.S.",
        "Squabble",
        "Rock",
        "Classic Rock",
        "Booker",
        "Vx Reeds",
        "Strings Ens Farf",
        "Principal Chorus + Mixture",
        "Full Theatre",
        "Full Overdrive",
        "First 3 Overdrive",
        "Joe’s M-3",
        "Power Comp",
        "Power Solo 1",
        "Power Solo 2",
        "Kinda Brian",
        "Mark’s Foot Stmp",
        "Spencer Wood",
        "Jerry C.",
        "Solo & Comp",
        "Principal Chorus",
        "Stopped Flute Chorus",
        "Gamba Celeste",
        "Sesquialtera II",
        "Stopped Flute 16´ & 8´",
        "Diapason 8´ & 4´",
        "Bourdon 16´ & Prin 2´",
        "Flutes w/Trem",
        "Hautbois Solo",
        "Sforzando",
        "Tibia 8´",
        "Tibia 8´ & 4´",
        "Style D Trumpet 8´",
        "Oboe 8´ & Tibia 4´",
        "Tibias 16´ & 4´",
        "Brass Trumpet 8´",
        "Tibias, Strings & Voxes",
        "Tibia 16´ 8´ 2´ & Vox",
        "Full Tibias & Voxes",
        "Full Comb + Posthrn",
        "DB 8´ 4´",
        "DB 8´ 2´",
        "DB 8´ 1´",
        "DB 8´ 4´ 2´",
        "DB 16´ 8´",
        "DB 16´ 4´",
        "DB 16´ 8´ 2´",
        "DB 16´ 8´ 4´ & 2´",
        "DB 16´ 8´ 4´ 2´ & 1´",
        "DB Full Organ",
        "Sylvia",
        "Lady",
        "Yeh Yeh",
        "Season Time",
        "On a Clear Day",
        "Twee motten",
        "Toccata Live",
        "Je t’aime moi -+",
        "Early Bird",
        "Bluesette",
        "Vx Mellow",
        "Vx Bright",
        "Vx Mixture",
        "Farf Flute",
        "Farf Brass",
        "Farf Reeds",
        "Farf Strings",
        "Farf Full",
        "Ace Flute",
        "Ace Strings",
        "Summer Samba",
        "Pumping Compress",
        "Touch Wah",
        "Ring + Flanged Jazz",
        "California Girl",
        "Won’t Get Fooled",
        "[TAP] To Delay Time",
        "Drawbar Celesta",
        "Interference",
        "Talking Drawbars",
        "Cancel",
        "French Horn 8´",
        "Tibial 8´ & 2´",
        "Clarinet 8´",
        "Novel Solo 8´",
        "Theatre Solo 16´",
        "Oboe Horn 8´",
        "Full Tibias 16´",
        "Trumpet 8´",
        "Full Theatre Brass 16´",
        "Cancel",
        "Stopped Flute",
        "Dulciana",
        "French Horn",
        "Salicional",
        "Flutes 8´ & 4´",
        "Oboe Horn",
        "Swell Diapason",
        "Trumpet",
        "Full Swell",
    ]

    /// F00-F99, the LOWER and PEDAL Name column of pp. 172-173 (the trailing "L" left off).
    public static let factoryLower: [String] = [
        "Dr. L.S.",
        "Squabble",
        "Rock",
        "Classic Rock",
        "Booker",
        "Vx Reeds",
        "Strings Ens Farf",
        "Principal Chorus + Mixture",
        "Full Theatre",
        "Full Overdrive",
        "First 3 Overdrive",
        "Joe’s M-3",
        "Power Comp",
        "Power Solo 1",
        "Power Solo 2",
        "Kinda Brian",
        "Mark’s Foot Stmp",
        "Spencer Wood",
        "Jerry C.",
        "Solo & Comp",
        "Principal Chorus",
        "Principal 4´ & 2´",
        "Flute Harmonique",
        "Gedeckt 8´",
        "Melodia 8´",
        "Diapason 8´ & 4´",
        "Principal 16´ & 8´",
        "Gedeckt 8´ w/Trem",
        "Diapason 8´",
        "Sforzando",
        "Clarinet 8´",
        "Diapason 8´",
        "Diapason & Vox",
        "Diapason & Clarinet",
        "Diapason & Flute",
        "Diapason & Oboe",
        "Diapason & Strings",
        "Diapason Flute & Vox",
        "Diapason 8 & 4 & Vox",
        "Full Accomp.",
        "DB 8´ 4´ 64",
        "DB 8´ 2´ 62",
        "DB 8´ 4´ 2⅔´",
        "DB 8´ & 4´ 84",
        "DB 8´ & 4´ 61",
        "DB 8´ & 4´ 65",
        "DB 8´ & 4´ 73",
        "DB 8´ & 4´ 87",
        "DB 8´ 4´ 2´",
        "DB Ensemble",
        "Sylvia",
        "Lady",
        "Yeh Yeh",
        "Season Time",
        "On a Clear Day",
        "Twee motten",
        "Toccata Live",
        "Je t’aime moi -+",
        "Early Bird",
        "Bluesette",
        "Vx Mellow",
        "Vx Bright",
        "Vx Mixture",
        "Farf Flute",
        "Farf Brass",
        "Farf Reeds",
        "Farf Strings",
        "Farf Full",
        "Ace Flute",
        "Ace Strings",
        "Summer Samba",
        "Pumping Compress",
        "Touch Wah",
        "Ring + Flanged Jazz",
        "California Girl",
        "Won’t Get Fooled",
        "[TAP] To Delay Time",
        "Drawbar Celesta",
        "Interference",
        "Talking Drawbars",
        "Cancel",
        "Cello 8´",
        "Dulciana 8´",
        "Vibraharp 8´",
        "Vox 8´ & Tibia 4´",
        "String Accomp. 8´",
        "Open Diapason 8´",
        "Full Accomp. 8´",
        "Tibia 8´",
        "Bombarde 16´",
        "Cancel",
        "Cello",
        "Flute & String",
        "Clarinet",
        "Diapason, Gamba & Flute",
        "Great, no reeds",
        "Open Diapason",
        "Full Great",
        "Tibia Clausa",
        "Full Great with 16´",
    ]

    /// Which name a part uses: Upper its own, Lower and Pedal the Lower name (p. 172's columns).
    public static func usesUpperName(part: String) -> Bool { part == "Upper" }

    /// The factory name for a program on a part, when the bank is Factory (bank MSB 01).
    public static func factoryName(part: String, bank: Int?, program: Int) -> String? {
        guard bank == 1, (0..<100).contains(program) else { return nil }
        return usesUpperName(part: part) ? factoryUpper[program] : factoryLower[program]
    }

    /// Whether a program change selects a stored patch whose name is worth looking up: a User patch
    /// or a Favorite. Adjust presets and unknown banks are said by slot only.
    public static func isLookupSlot(bank: Int?, program: Int) -> Bool {
        switch program {
        case 0...0x63: return bank == 0
        case 0x64...0x6D: return true
        default: return false
        }
    }

    /// A name as the organ stores it (16 letters, padded with spaces), tidied for speaking:
    /// runs of spaces become one, and a part marker ("U" or "L" set apart at the end, as the
    /// factory table prints it) is left off.
    public static func clean(_ raw: String) -> String {
        var s = raw.replacingOccurrences(of: "\u{0}", with: " ")
        if s.count >= 3 {
            let tail = String(s.suffix(3))
            if tail == "  U" || tail == "  L" { s = String(s.dropLast()) }
        }
        let words = s.split(separator: " ", omittingEmptySubsequences: true)
        return words.joined(separator: " ")
    }

    /// The name as it is said: a footage mark after a number (8´, 8' or 8’) becomes "foot".
    public static func spoken(_ name: String) -> String {
        var out = ""
        var previous: Character?
        for c in name {
            if (c == "\u{B4}" || c == "'" || c == "\u{2019}"), let p = previous, ("0"..."9").contains(p) || p == "\u{2154}" {
                out += " foot"
            } else if c == "\u{B4}" {
                out += " "
            } else {
                out.append(c)
            }
            previous = c
        }
        return out
    }

    /// The line spoken for a patch change: "Upper: Dr. L.S., F00" with a name,
    /// "Upper: patch U05" without one.
    public static func announcement(part: String, description: String, name: String?) -> String {
        let slot = PatchSelect.spoken(description)
        guard let name, !name.isEmpty else { return "\(part): \(slot)" }
        let short = slot.hasPrefix("patch ") ? String(slot.dropFirst(6)) : slot
        return "\(part): \(spoken(name)), \(short)"
    }

    /// Finds the Upper and Lower names in a Temporary dump's data (packets of type 07 in order,
    /// already de-nibblized). The manual doesn't publish the dump layout, so this looks for the
    /// two 16-letter names side by side, as their addresses are (00 00 10 00 00 and 00 00 10 00 01):
    /// 32 bytes in a row that are all printable ASCII, each half at least half letters or spaces,
    /// with three letters or more between them and two in one of them. Either name can come back
    /// empty (a blank name). Anything less certain gives nil, and the slot is said instead.
    public static func fromTemporaryDump(_ data: [UInt8]) -> (upper: String, lower: String)? {
        guard data.count >= 32 else { return nil }
        func printable(_ b: UInt8) -> Bool { b >= 0x20 && b <= 0x7E }
        func letter(_ b: UInt8) -> Bool { (b >= 0x41 && b <= 0x5A) || (b >= 0x61 && b <= 0x7A) }
        func letters(_ s: ArraySlice<UInt8>) -> Int { s.filter(letter).count }
        func wordy(_ s: ArraySlice<UInt8>) -> Bool { s.filter { letter($0) || $0 == 0x20 }.count * 2 >= s.count }
        var run = 0
        for i in 0..<data.count {
            run = printable(data[i]) ? run + 1 : 0
            guard run >= 32 else { continue }
            let start = i - 31
            let up = data[start..<start + 16], lo = data[start + 16..<start + 32]
            if wordy(up), wordy(lo), max(letters(up), letters(lo)) >= 2, letters(up) + letters(lo) >= 3 {
                return (clean(String(decoding: up, as: UTF8.self)), clean(String(decoding: lo, as: UTF8.self)))
            }
        }
        return nil
    }
}

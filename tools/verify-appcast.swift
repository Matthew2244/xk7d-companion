// Checks a published update list the way an installed copy will: the enclosure's EdDSA signature
// against the public key the apps carry, and its length against the file.
//   swift tools/verify-appcast.swift PUBLIC_KEY appcast.xml downloaded-file
// Exits 1 on any mismatch. Needs only the public key; the private key never comes near it.
import CryptoKit
import Foundation

let args = CommandLine.arguments
guard args.count == 4 else { print("usage: verify-appcast.swift PUBLIC_KEY appcast.xml file"); exit(2) }
func fail(_ s: String) -> Never { print("FAIL: \(s)"); exit(1) }
guard let keyData = Data(base64Encoded: args[1]), let key = try? Curve25519.Signing.PublicKey(rawRepresentation: keyData)
else { fail("the public key isn't a base64 Ed25519 key") }
guard let xml = try? String(contentsOfFile: args[2], encoding: .utf8) else { fail("can't read \(args[2])") }
guard let file = try? Data(contentsOf: URL(fileURLWithPath: args[3])) else { fail("can't read \(args[3])") }
func attribute(_ name: String) -> String? {
    guard let r = xml.range(of: "\(name)=\"") else { return nil }
    return String(xml[r.upperBound...].prefix { $0 != "\"" })
}
guard xml.components(separatedBy: "<enclosure").count == 2 else { fail("expected exactly one enclosure") }
guard let sig = attribute("sparkle:edSignature").flatMap({ Data(base64Encoded: $0) }) else { fail("no signature") }
guard attribute("length") == String(file.count) else { fail("length \(attribute("length") ?? "none") but the file is \(file.count) bytes") }
guard key.isValidSignature(sig, for: file) else { fail("the signature doesn't match the file") }
print("OK: \(args[2]) signs \((args[3] as NSString).lastPathComponent), \(file.count) bytes")

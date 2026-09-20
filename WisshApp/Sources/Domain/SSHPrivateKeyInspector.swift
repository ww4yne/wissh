import CryptoKit
import Foundation

enum SSHPrivateKeyType: String, Codable, Equatable, Sendable {
    case ed25519 = "ssh-ed25519"
    case rsa = "ssh-rsa"
    case ecdsaP256 = "ecdsa-sha2-nistp256"
    case ecdsaP384 = "ecdsa-sha2-nistp384"
    case ecdsaP521 = "ecdsa-sha2-nistp521"

    var displayName: String {
        switch self {
        case .ed25519:
            "ED25519"
        case .rsa:
            "RSA"
        case .ecdsaP256:
            "ECDSA P-256"
        case .ecdsaP384:
            "ECDSA P-384"
        case .ecdsaP521:
            "ECDSA P-521"
        }
    }

    var ecdsaCurveName: String? {
        switch self {
        case .ed25519, .rsa:
            nil
        case .ecdsaP256:
            "nistp256"
        case .ecdsaP384:
            "nistp384"
        case .ecdsaP521:
            "nistp521"
        }
    }

    var ecdsaPointByteCount: Int? {
        switch self {
        case .ed25519, .rsa:
            nil
        case .ecdsaP256:
            65
        case .ecdsaP384:
            97
        case .ecdsaP521:
            133
        }
    }
}

struct SSHPrivateKeyInspection: Equatable, Sendable {
    let keyType: SSHPrivateKeyType
    let publicFingerprint: String
    let publicKeyLine: String
    let normalizedPEM: String
    let isEncrypted: Bool
}

struct SSHGeneratedPrivateKey: Equatable, Sendable {
    let privateKeyPEM: String
    let publicKeyLine: String
    let publicFingerprint: String
}

enum SSHPrivateKeyInspectionError: Error, Equatable, LocalizedError, Sendable {
    case empty
    case tooLarge
    case legacyPEMFormat
    case invalidOpenSSHPrivateKey
    case unsupportedKeyType(String)

    var errorDescription: String? {
        switch self {
        case .empty:
            "Private key is required."
        case .tooLarge:
            "Private key file is too large."
        case .legacyPEMFormat:
            "This key uses legacy PEM format. Convert a copy with ssh-keygen -p -o, then import it again."
        case .invalidOpenSSHPrivateKey:
            "Import an OpenSSH private key."
        case .unsupportedKeyType(let keyType):
            "Wissh does not support \(keyType) private keys yet."
        }
    }
}

enum SSHPrivateKeyInspector {
    static let maxByteCount = 256 * 1024

    static func inspect(_ pem: String) throws -> SSHPrivateKeyInspection {
        var normalizedPEM = pem.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedPEM.isEmpty else {
            throw SSHPrivateKeyInspectionError.empty
        }

        guard normalizedPEM.utf8.count <= maxByteCount else {
            throw SSHPrivateKeyInspectionError.tooLarge
        }

        if normalizedPEM.hasPrefix("-----BEGIN RSA PRIVATE KEY-----") {
            normalizedPEM = try convertLegacyRSAPrivateKey(normalizedPEM)
        } else if normalizedPEM.hasPrefix("-----BEGIN EC PRIVATE KEY-----") ||
            normalizedPEM.hasPrefix("-----BEGIN PRIVATE KEY-----") ||
            normalizedPEM.hasPrefix("-----BEGIN ENCRYPTED PRIVATE KEY-----") {
            throw SSHPrivateKeyInspectionError.legacyPEMFormat
        }

        let payload = try openSSHPrivateKeyPayload(from: normalizedPEM)
        var reader = SSHPrivateKeyPayloadReader(data: payload)

        guard
            try reader.readBytes(count: "openssh-key-v1\0".utf8.count) == Data("openssh-key-v1\0".utf8)
        else {
            throw SSHPrivateKeyInspectionError.invalidOpenSSHPrivateKey
        }

        let cipherName = try reader.readSSHString()
        let kdfName = try reader.readSSHString()
        let kdfOptions = try reader.readSSHStringData()

        guard try reader.readUInt32() == 1 else {
            throw SSHPrivateKeyInspectionError.invalidOpenSSHPrivateKey
        }

        let publicKeyBlob = try reader.readSSHStringData()
        var publicKeyReader = SSHPrivateKeyPayloadReader(data: publicKeyBlob)
        let rawKeyType = try publicKeyReader.readSSHString()

        guard let keyType = SSHPrivateKeyType(rawValue: rawKeyType) else {
            throw SSHPrivateKeyInspectionError.unsupportedKeyType(rawKeyType)
        }
        try validatePublicKeyBlob(for: keyType, reader: &publicKeyReader)
        guard publicKeyReader.isAtEnd else {
            throw SSHPrivateKeyInspectionError.invalidOpenSSHPrivateKey
        }

        let privateKeyBlock = try reader.readSSHStringData()
        guard reader.isAtEnd else {
            throw SSHPrivateKeyInspectionError.invalidOpenSSHPrivateKey
        }

        if cipherName == "none" {
            guard kdfName == "none", kdfOptions.isEmpty else {
                throw SSHPrivateKeyInspectionError.invalidOpenSSHPrivateKey
            }
            try validateUnencryptedPrivateKeyBlock(
                privateKeyBlock,
                keyType: keyType,
                publicKeyBlob: publicKeyBlob
            )
        } else {
            guard !privateKeyBlock.isEmpty else {
                throw SSHPrivateKeyInspectionError.invalidOpenSSHPrivateKey
            }
        }

        let fingerprint = Data(SHA256.hash(data: publicKeyBlob))
            .base64EncodedString()
            .replacingOccurrences(of: "=", with: "")

        return SSHPrivateKeyInspection(
            keyType: keyType,
            publicFingerprint: "SHA256:\(fingerprint)",
            publicKeyLine: "\(rawKeyType) \(publicKeyBlob.base64EncodedString())",
            normalizedPEM: normalizedPEM,
            isEncrypted: cipherName != "none"
        )
    }

    private static func validatePublicKeyBlob(
        for keyType: SSHPrivateKeyType,
        reader: inout SSHPrivateKeyPayloadReader
    ) throws {
        switch keyType {
        case .ed25519:
            guard try reader.readSSHStringData().count == 32 else {
                throw SSHPrivateKeyInspectionError.invalidOpenSSHPrivateKey
            }
        case .rsa:
            let exponent = try reader.readSSHStringData()
            let modulus = try reader.readSSHStringData()
            guard
                !exponent.isEmpty,
                !modulus.isEmpty
            else {
                throw SSHPrivateKeyInspectionError.invalidOpenSSHPrivateKey
            }
        case .ecdsaP256, .ecdsaP384, .ecdsaP521:
            guard
                let expectedCurveName = keyType.ecdsaCurveName,
                let expectedPointByteCount = keyType.ecdsaPointByteCount,
                try reader.readSSHString() == expectedCurveName
            else {
                throw SSHPrivateKeyInspectionError.invalidOpenSSHPrivateKey
            }
            let point = try reader.readSSHStringData()
            guard point.count == expectedPointByteCount, point.first == 0x04 else {
                throw SSHPrivateKeyInspectionError.invalidOpenSSHPrivateKey
            }
        }
    }

    private static func validateUnencryptedPrivateKeyBlock(
        _ data: Data,
        keyType: SSHPrivateKeyType,
        publicKeyBlob: Data
    ) throws {
        guard data.count.isMultiple(of: 8) else {
            throw SSHPrivateKeyInspectionError.invalidOpenSSHPrivateKey
        }

        var reader = SSHPrivateKeyPayloadReader(data: data)
        var publicKeyReader = SSHPrivateKeyPayloadReader(data: publicKeyBlob)

        guard try publicKeyReader.readSSHString() == keyType.rawValue else {
            throw SSHPrivateKeyInspectionError.invalidOpenSSHPrivateKey
        }

        let firstCheck = try reader.readUInt32()
        guard try reader.readUInt32() == firstCheck else {
            throw SSHPrivateKeyInspectionError.invalidOpenSSHPrivateKey
        }

        guard try reader.readSSHString() == keyType.rawValue else {
            throw SSHPrivateKeyInspectionError.invalidOpenSSHPrivateKey
        }

        switch keyType {
        case .ed25519:
            let publicKey = try publicKeyReader.readSSHStringData()
            let privateBlockPublicKey = try reader.readSSHStringData()
            let privateMaterial = try reader.readSSHStringData()
            guard
                privateBlockPublicKey == publicKey,
                publicKey.count == 32,
                privateMaterial.count == 64,
                Data(privateMaterial.suffix(32)) == publicKey
            else {
                throw SSHPrivateKeyInspectionError.invalidOpenSSHPrivateKey
            }
        case .rsa:
            let publicExponent = try publicKeyReader.readSSHStringData()
            let publicModulus = try publicKeyReader.readSSHStringData()
            let privateBlockModulus = try reader.readSSHStringData()
            let privateBlockExponent = try reader.readSSHStringData()
            guard
                privateBlockModulus == publicModulus,
                privateBlockExponent == publicExponent
            else {
                throw SSHPrivateKeyInspectionError.invalidOpenSSHPrivateKey
            }
            for _ in 0..<4 {
                let component = try reader.readSSHStringData()
                guard !component.isEmpty else {
                    throw SSHPrivateKeyInspectionError.invalidOpenSSHPrivateKey
                }
            }
        case .ecdsaP256, .ecdsaP384, .ecdsaP521:
            guard
                let expectedCurveName = keyType.ecdsaCurveName,
                let expectedPointByteCount = keyType.ecdsaPointByteCount,
                try publicKeyReader.readSSHString() == expectedCurveName,
                try reader.readSSHString() == expectedCurveName
            else {
                throw SSHPrivateKeyInspectionError.invalidOpenSSHPrivateKey
            }
            let publicPoint = try publicKeyReader.readSSHStringData()
            let point = try reader.readSSHStringData()
            let privateScalar = try reader.readSSHStringData()
            guard
                point == publicPoint,
                point.count == expectedPointByteCount,
                point.first == 0x04,
                !privateScalar.isEmpty
            else {
                throw SSHPrivateKeyInspectionError.invalidOpenSSHPrivateKey
            }
        }

        _ = try reader.readSSHString()
        let padding = try reader.readRemainingBytes()
        guard padding.count <= 8 else {
            throw SSHPrivateKeyInspectionError.invalidOpenSSHPrivateKey
        }
        for (index, byte) in padding.enumerated() {
            guard byte == UInt8(index + 1) else {
                throw SSHPrivateKeyInspectionError.invalidOpenSSHPrivateKey
            }
        }

        guard publicKeyReader.isAtEnd else {
            throw SSHPrivateKeyInspectionError.invalidOpenSSHPrivateKey
        }
    }

    static func generateEd25519(comment: String = "remux") -> SSHGeneratedPrivateKey {
        let privateKey = Curve25519.Signing.PrivateKey()
        let publicKey = privateKey.publicKey.rawRepresentation
        let privateSeed = privateKey.rawRepresentation
        let keyType = SSHPrivateKeyType.ed25519.rawValue

        var publicBlob = SSHPrivateKeyPayloadWriter()
        publicBlob.writeSSHString(keyType)
        publicBlob.writeSSHString(publicKey)
        let publicKeyBlob = publicBlob.data

        let check = UInt32.random(in: UInt32.min...UInt32.max)
        var privateBlock = SSHPrivateKeyPayloadWriter()
        privateBlock.writeUInt32(check)
        privateBlock.writeUInt32(check)
        privateBlock.writeSSHString(keyType)
        privateBlock.writeSSHString(publicKey)
        privateBlock.writeSSHString(privateSeed + publicKey)
        privateBlock.writeSSHString(comment)
        privateBlock.writePadding(blockSize: 8)

        var payload = SSHPrivateKeyPayloadWriter()
        payload.writeBytes(Data("openssh-key-v1\0".utf8))
        payload.writeSSHString("none")
        payload.writeSSHString("none")
        payload.writeSSHString(Data())
        payload.writeUInt32(1)
        payload.writeSSHString(publicKeyBlob)
        payload.writeSSHString(privateBlock.data)

        let privateKeyPEM = openSSHPrivateKeyPEM(payload.data)
        let fingerprint = Data(SHA256.hash(data: publicKeyBlob))
            .base64EncodedString()
            .replacingOccurrences(of: "=", with: "")
        return SSHGeneratedPrivateKey(
            privateKeyPEM: privateKeyPEM,
            publicKeyLine: "\(keyType) \(publicKeyBlob.base64EncodedString())",
            publicFingerprint: "SHA256:\(fingerprint)"
        )
    }

    private static func openSSHPrivateKeyPayload(from pem: String) throws -> Data {
        let lines = pem
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        guard
            lines.first == "-----BEGIN OPENSSH PRIVATE KEY-----",
            lines.last == "-----END OPENSSH PRIVATE KEY-----"
        else {
            throw SSHPrivateKeyInspectionError.invalidOpenSSHPrivateKey
        }

        let base64 = lines.dropFirst().dropLast().joined()
        guard let payload = Data(base64Encoded: base64) else {
            throw SSHPrivateKeyInspectionError.invalidOpenSSHPrivateKey
        }

        return payload
    }

    private static func convertLegacyRSAPrivateKey(_ pem: String) throws -> String {
        let lines = pem
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard
            lines.first == "-----BEGIN RSA PRIVATE KEY-----",
            lines.last == "-----END RSA PRIVATE KEY-----",
            lines.dropFirst().dropLast().allSatisfy({ !$0.contains(":") }),
            let der = Data(base64Encoded: lines.dropFirst().dropLast().joined())
        else {
            throw SSHPrivateKeyInspectionError.legacyPEMFormat
        }

        var outerReader = DERReader(data: der)
        let sequence = try outerReader.readElement(tag: 0x30)
        guard outerReader.isAtEnd else {
            throw SSHPrivateKeyInspectionError.invalidOpenSSHPrivateKey
        }

        var keyReader = DERReader(data: sequence)
        let version = try keyReader.readPositiveInteger()
        guard version == Data([0]) else {
            throw SSHPrivateKeyInspectionError.invalidOpenSSHPrivateKey
        }
        let modulus = try keyReader.readPositiveInteger()
        let publicExponent = try keyReader.readPositiveInteger()
        let privateExponent = try keyReader.readPositiveInteger()
        let prime1 = try keyReader.readPositiveInteger()
        let prime2 = try keyReader.readPositiveInteger()
        _ = try keyReader.readPositiveInteger()
        _ = try keyReader.readPositiveInteger()
        let coefficient = try keyReader.readPositiveInteger()
        guard keyReader.isAtEnd else {
            throw SSHPrivateKeyInspectionError.invalidOpenSSHPrivateKey
        }

        var publicBlob = SSHPrivateKeyPayloadWriter()
        publicBlob.writeSSHString(SSHPrivateKeyType.rsa.rawValue)
        publicBlob.writeSSHString(publicExponent)
        publicBlob.writeSSHString(modulus)

        let checkBytes = SHA256.hash(data: der).prefix(4)
        let check = checkBytes.reduce(UInt32(0)) { value, byte in
            (value << 8) | UInt32(byte)
        }
        var privateBlock = SSHPrivateKeyPayloadWriter()
        privateBlock.writeUInt32(check)
        privateBlock.writeUInt32(check)
        privateBlock.writeSSHString(SSHPrivateKeyType.rsa.rawValue)
        privateBlock.writeSSHString(modulus)
        privateBlock.writeSSHString(publicExponent)
        privateBlock.writeSSHString(privateExponent)
        privateBlock.writeSSHString(coefficient)
        privateBlock.writeSSHString(prime1)
        privateBlock.writeSSHString(prime2)
        privateBlock.writeSSHString("")
        privateBlock.writePadding(blockSize: 8)

        var payload = SSHPrivateKeyPayloadWriter()
        payload.writeBytes(Data("openssh-key-v1\0".utf8))
        payload.writeSSHString("none")
        payload.writeSSHString("none")
        payload.writeSSHString(Data())
        payload.writeUInt32(1)
        payload.writeSSHString(publicBlob.data)
        payload.writeSSHString(privateBlock.data)
        return openSSHPrivateKeyPEM(payload.data)
    }

    private static func openSSHPrivateKeyPEM(_ payload: Data) -> String {
        let base64 = payload.base64EncodedString()
        let wrapped = stride(from: 0, to: base64.count, by: 70).map { offset in
            let start = base64.index(base64.startIndex, offsetBy: offset)
            let end = base64.index(
                start,
                offsetBy: min(70, base64.distance(from: start, to: base64.endIndex))
            )
            return String(base64[start..<end])
        }.joined(separator: "\n")
        return """
        -----BEGIN OPENSSH PRIVATE KEY-----
        \(wrapped)
        -----END OPENSSH PRIVATE KEY-----
        """
    }
}

private struct DERReader {
    private let data: Data
    private var offset = 0

    init(data: Data) {
        self.data = data
    }

    mutating func readElement(tag expectedTag: UInt8) throws -> Data {
        guard offset < data.count, data[offset] == expectedTag else {
            throw SSHPrivateKeyInspectionError.invalidOpenSSHPrivateKey
        }
        offset += 1
        let length = try readLength()
        guard length <= data.count - offset else {
            throw SSHPrivateKeyInspectionError.invalidOpenSSHPrivateKey
        }
        let value = Data(data[offset..<(offset + length)])
        offset += length
        return value
    }

    mutating func readPositiveInteger() throws -> Data {
        var integer = try readElement(tag: 0x02)
        guard !integer.isEmpty, integer.first.map({ $0 & 0x80 == 0 }) == true else {
            throw SSHPrivateKeyInspectionError.invalidOpenSSHPrivateKey
        }
        while integer.count > 1, integer[0] == 0, integer[1] & 0x80 == 0 {
            integer.removeFirst()
        }
        return integer
    }

    private mutating func readLength() throws -> Int {
        guard offset < data.count else {
            throw SSHPrivateKeyInspectionError.invalidOpenSSHPrivateKey
        }
        let first = data[offset]
        offset += 1
        if first & 0x80 == 0 {
            return Int(first)
        }

        let byteCount = Int(first & 0x7f)
        guard byteCount > 0, byteCount <= 4, byteCount <= data.count - offset else {
            throw SSHPrivateKeyInspectionError.invalidOpenSSHPrivateKey
        }
        var length = 0
        for _ in 0..<byteCount {
            length = (length << 8) | Int(data[offset])
            offset += 1
        }
        return length
    }

    var isAtEnd: Bool {
        offset == data.count
    }
}

private struct SSHPrivateKeyPayloadReader {
    private let data: Data
    private var offset = 0

    init(data: Data) {
        self.data = data
    }

    mutating func readUInt32() throws -> UInt32 {
        guard offset + 4 <= data.count else {
            throw SSHPrivateKeyInspectionError.invalidOpenSSHPrivateKey
        }

        let value = data[offset..<(offset + 4)].reduce(UInt32(0)) { result, byte in
            (result << 8) | UInt32(byte)
        }
        offset += 4
        return value
    }

    mutating func readSSHString() throws -> String {
        let stringData = try readSSHStringData()
        guard let string = String(data: stringData, encoding: .utf8) else {
            throw SSHPrivateKeyInspectionError.invalidOpenSSHPrivateKey
        }
        return string
    }

    mutating func readSSHStringData() throws -> Data {
        let length = Int(try readUInt32())
        return try readBytes(count: length)
    }

    mutating func readBytes(count: Int) throws -> Data {
        guard count >= 0, offset + count <= data.count else {
            throw SSHPrivateKeyInspectionError.invalidOpenSSHPrivateKey
        }

        let bytes = data[offset..<(offset + count)]
        offset += count
        return Data(bytes)
    }

    mutating func readRemainingBytes() throws -> Data {
        try readBytes(count: data.count - offset)
    }

    var isAtEnd: Bool {
        offset == data.count
    }
}

private struct SSHPrivateKeyPayloadWriter {
    private(set) var data = Data()

    mutating func writeUInt32(_ value: UInt32) {
        data.append(UInt8((value >> 24) & 0xff))
        data.append(UInt8((value >> 16) & 0xff))
        data.append(UInt8((value >> 8) & 0xff))
        data.append(UInt8(value & 0xff))
    }

    mutating func writeSSHString(_ string: String) {
        writeSSHString(Data(string.utf8))
    }

    mutating func writeSSHString(_ bytes: Data) {
        writeUInt32(UInt32(bytes.count))
        data.append(bytes)
    }

    mutating func writeBytes(_ bytes: Data) {
        data.append(bytes)
    }

    mutating func writePadding(blockSize: Int) {
        var paddingByte: UInt8 = 1
        repeat {
            data.append(paddingByte)
            paddingByte &+= 1
        } while data.count % blockSize != 0
    }
}

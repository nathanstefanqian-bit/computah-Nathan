import Foundation
import zlib

public enum VolcengineASRProtocol {
    public static let fullClientRequest: UInt8 = 0x1
    public static let audioOnlyRequest: UInt8 = 0x2
    public static let fullServerResponse: UInt8 = 0x9
    public static let errorResponse: UInt8 = 0xF

    public static func fullRequest(json: Data) throws -> Data {
        try frame(
            messageType: fullClientRequest, flags: 0, serialization: 1,
            compression: 1, payload: Gzip.compress(json))
    }

    public static func audio(_ pcm: Data, final: Bool = false) throws -> Data {
        try frame(
            messageType: audioOnlyRequest, flags: final ? 2 : 0, serialization: 0,
            compression: 1, payload: Gzip.compress(pcm))
    }

    public static func parseServerFrame(_ data: Data) throws -> VolcengineServerFrame {
        guard data.count >= 4 else { throw VolcengineProtocolError.shortHeader }
        let version = data[0] >> 4
        let headerSize = Int(data[0] & 0x0F) * 4
        guard version == 1, headerSize >= 4, data.count >= headerSize else {
            throw VolcengineProtocolError.invalidHeader
        }

        let messageType = data[1] >> 4
        let flags = data[1] & 0x0F
        let serialization = data[2] >> 4
        let compression = data[2] & 0x0F
        guard serialization == 0 || serialization == 1 else {
            throw VolcengineProtocolError.unsupportedSerialization(serialization)
        }
        guard compression == 0 || compression == 1 else {
            throw VolcengineProtocolError.unsupportedCompression(compression)
        }

        var offset = headerSize
        var sequence: Int32?
        var errorCode: UInt32?
        if messageType == errorResponse {
            errorCode = try readUInt32(data, offset: &offset)
        } else if flags == 1 || flags == 3 {
            sequence = Int32(bitPattern: try readUInt32(data, offset: &offset))
        }
        let payloadSize = Int(try readUInt32(data, offset: &offset))
        guard payloadSize >= 0, offset + payloadSize == data.count else {
            throw VolcengineProtocolError.invalidPayloadSize
        }
        var payload = data.subdata(in: offset..<(offset + payloadSize))
        if compression == 1 { payload = try Gzip.decompress(payload) }
        return VolcengineServerFrame(
            messageType: messageType, flags: flags, serialization: serialization,
            compression: compression, sequence: sequence, errorCode: errorCode,
            payload: payload)
    }

    private static func frame(
        messageType: UInt8, flags: UInt8, serialization: UInt8,
        compression: UInt8, payload: Data
    ) throws -> Data {
        guard messageType < 16, flags < 16, serialization < 16, compression < 16,
              payload.count <= Int(UInt32.max) else {
            throw VolcengineProtocolError.invalidPayloadSize
        }
        var result = Data([
            0x11,
            (messageType << 4) | flags,
            (serialization << 4) | compression,
            0x00,
        ])
        appendUInt32(UInt32(payload.count), to: &result)
        result.append(payload)
        return result
    }

    private static func readUInt32(_ data: Data, offset: inout Int) throws -> UInt32 {
        guard offset + 4 <= data.count else { throw VolcengineProtocolError.invalidPayloadSize }
        let value = data[offset..<(offset + 4)].reduce(UInt32(0)) { ($0 << 8) | UInt32($1) }
        offset += 4
        return value
    }

    private static func appendUInt32(_ value: UInt32, to data: inout Data) {
        data.append(UInt8((value >> 24) & 0xFF))
        data.append(UInt8((value >> 16) & 0xFF))
        data.append(UInt8((value >> 8) & 0xFF))
        data.append(UInt8(value & 0xFF))
    }
}

public struct VolcengineServerFrame: Equatable, Sendable {
    public let messageType: UInt8
    public let flags: UInt8
    public let serialization: UInt8
    public let compression: UInt8
    public let sequence: Int32?
    public let errorCode: UInt32?
    public let payload: Data

    public var isFinal: Bool {
        flags == 2 || flags == 3 || (sequence.map { $0 < 0 } ?? false)
    }
}

public enum VolcengineProtocolError: LocalizedError {
    case shortHeader
    case invalidHeader
    case invalidPayloadSize
    case unsupportedSerialization(UInt8)
    case unsupportedCompression(UInt8)
    case compressionFailed(Int32)

    public var errorDescription: String? {
        switch self {
        case .shortHeader: return "Volcengine ASR frame is shorter than its header."
        case .invalidHeader: return "Volcengine ASR frame has an invalid protocol header."
        case .invalidPayloadSize: return "Volcengine ASR frame has an invalid payload size."
        case .unsupportedSerialization(let value):
            return "Volcengine ASR frame uses unsupported serialization \(value)."
        case .unsupportedCompression(let value):
            return "Volcengine ASR frame uses unsupported compression \(value)."
        case .compressionFailed(let status):
            return "Volcengine ASR gzip processing failed with zlib status \(status)."
        }
    }
}

private enum Gzip {
    static func compress(_ input: Data) throws -> Data {
        try transform(input, operation: .compress)
    }

    static func decompress(_ input: Data) throws -> Data {
        try transform(input, operation: .decompress)
    }

    private enum Operation { case compress, decompress }

    private static func transform(_ input: Data, operation: Operation) throws -> Data {
        var stream = z_stream()
        let initialized: Int32
        switch operation {
        case .compress:
            initialized = deflateInit2_(
                &stream, Z_DEFAULT_COMPRESSION, Z_DEFLATED, MAX_WBITS + 16, 8,
                Z_DEFAULT_STRATEGY, ZLIB_VERSION, Int32(MemoryLayout<z_stream>.size))
        case .decompress:
            initialized = inflateInit2_(
                &stream, MAX_WBITS + 32, ZLIB_VERSION, Int32(MemoryLayout<z_stream>.size))
        }
        guard initialized == Z_OK else { throw VolcengineProtocolError.compressionFailed(initialized) }
        defer {
            if case .compress = operation { deflateEnd(&stream) }
            else { inflateEnd(&stream) }
        }

        return try input.withUnsafeBytes { inputBuffer in
            stream.next_in = UnsafeMutablePointer<Bytef>(
                mutating: inputBuffer.bindMemory(to: Bytef.self).baseAddress)
            stream.avail_in = uInt(input.count)
            var output = Data()
            let chunkSize = 16_384
            var chunk = [UInt8](repeating: 0, count: chunkSize)
            while true {
                let status = chunk.withUnsafeMutableBytes { outputBuffer -> Int32 in
                    stream.next_out = outputBuffer.bindMemory(to: Bytef.self).baseAddress
                    stream.avail_out = uInt(chunkSize)
                    switch operation {
                    case .compress: return deflate(&stream, Z_FINISH)
                    case .decompress: return inflate(&stream, Z_NO_FLUSH)
                    }
                }
                let produced = chunkSize - Int(stream.avail_out)
                if produced > 0 { output.append(chunk, count: produced) }
                if status == Z_STREAM_END { return output }
                guard status == Z_OK else {
                    throw VolcengineProtocolError.compressionFailed(status)
                }
            }
        }
    }
}

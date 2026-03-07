import Foundation
import zlib

/// Errors thrown by ZipExtractor.
enum ZipExtractError: Error, LocalizedError {
    case invalidFormat
    case fileNotFound(String)
    case decompressionFailed(Int32)
    case unsupportedCompression(UInt16)

    var errorDescription: String? {
        switch self {
        case .invalidFormat:
            return "Invalid zip archive format"
        case .fileNotFound(let name):
            return "'\(name)' not found in zip archive"
        case .decompressionFailed(let code):
            return "Decompression failed (zlib code: \(code))"
        case .unsupportedCompression(let method):
            return "Unsupported zip compression method: \(method)"
        }
    }
}

/// Minimal zip archive extractor implemented in pure Swift.
/// No external processes or third-party libraries — works in App Sandbox.
/// Supports: Store (method 0) and Deflate (method 8).
enum ZipExtractor {

    /// Extracts the first entry whose filename ends with `suffix` from the given zip data.
    nonisolated static func extractFile(endingWith suffix: String, from data: Data) throws -> Data {
        guard let eocdOffset = findEOCD(in: data) else {
            throw ZipExtractError.invalidFormat
        }

        let cdOffset = Int(data.readLE32(at: eocdOffset + 16))
        let cdCount  = Int(data.readLE16(at: eocdOffset + 10))
        let lower    = suffix.lowercased()

        var pos = cdOffset
        for _ in 0..<cdCount {
            guard pos + 46 <= data.count,
                  data.readLE32(at: pos) == 0x02014b50 else { break }

            let method      = data.readLE16(at: pos + 10)
            let compSize    = Int(data.readLE32(at: pos + 20))
            let uncompSize  = Int(data.readLE32(at: pos + 24))
            let nameLen     = Int(data.readLE16(at: pos + 28))
            let extraLen    = Int(data.readLE16(at: pos + 30))
            let commentLen  = Int(data.readLE16(at: pos + 32))
            let localOffset = Int(data.readLE32(at: pos + 42))

            let nameEnd = pos + 46 + nameLen
            guard nameEnd <= data.count else { break }
            let name = String(data: data.subdata(in: (pos + 46)..<nameEnd), encoding: .utf8)
                ?? String(data: data.subdata(in: (pos + 46)..<nameEnd), encoding: .isoLatin1)
                ?? ""

            if name.lowercased().hasSuffix(lower) {
                return try extractLocalEntry(
                    from: data,
                    at: localOffset,
                    method: method,
                    compSize: compSize,
                    uncompSize: uncompSize
                )
            }
            pos += 46 + nameLen + extraLen + commentLen
        }
        throw ZipExtractError.fileNotFound(suffix)
    }

    // MARK: - Private

    nonisolated private static func extractLocalEntry(
        from data: Data,
        at localOffset: Int,
        method: UInt16,
        compSize: Int,
        uncompSize: Int
    ) throws -> Data {
        guard localOffset + 30 <= data.count,
              data.readLE32(at: localOffset) == 0x04034b50 else {
            throw ZipExtractError.invalidFormat
        }
        let nameLen  = Int(data.readLE16(at: localOffset + 26))
        let extraLen = Int(data.readLE16(at: localOffset + 28))
        let dataStart = localOffset + 30 + nameLen + extraLen
        guard dataStart + compSize <= data.count else {
            throw ZipExtractError.invalidFormat
        }

        let compressed = data.subdata(in: dataStart..<(dataStart + compSize))

        switch method {
        case 0:  // Store — no compression
            return compressed
        case 8:  // Deflate
            return try inflateDeflate(compressed, uncompressedSize: uncompSize)
        default:
            throw ZipExtractError.unsupportedCompression(method)
        }
    }

    /// Decompresses raw DEFLATE data (zip compression method 8) using zlib.
    ///
    /// Zip stores raw deflate streams, so we must initialize inflate with a negative window size
    /// to disable zlib/gzip header parsing.
    nonisolated private static func inflateDeflate(_ data: Data, uncompressedSize: Int) throws -> Data {
        var stream = z_stream()
        let initResult = inflateInit2_(&stream, -MAX_WBITS, ZLIB_VERSION, Int32(MemoryLayout<z_stream>.size))
        guard initResult == Z_OK else {
            throw ZipExtractError.decompressionFailed(initResult)
        }
        defer { inflateEnd(&stream) }

        var output = Data(count: uncompressedSize)

        let result: Int32 = output.withUnsafeMutableBytes { outBuf in
            data.withUnsafeBytes { inBuf in
                guard let srcBase = inBuf.baseAddress, let dstBase = outBuf.baseAddress else {
                    return Int32(Z_BUF_ERROR)
                }
                stream.next_in = UnsafeMutablePointer<Bytef>(
                    mutating: srcBase.assumingMemoryBound(to: Bytef.self)
                )
                stream.avail_in = uInt(inBuf.count)
                stream.next_out = dstBase.assumingMemoryBound(to: Bytef.self)
                stream.avail_out = uInt(outBuf.count)
                return inflate(&stream, Z_FINISH)
            }
        }

        guard result == Z_STREAM_END, Int(stream.total_out) == uncompressedSize else {
            throw ZipExtractError.decompressionFailed(result)
        }
        return output
    }

    /// Searches backwards for the End of Central Directory record (PK\x05\x06).
    nonisolated private static func findEOCD(in data: Data) -> Int? {
        guard data.count >= 22 else { return nil }
        let minPos = max(0, data.count - 65535 - 22)
        for i in stride(from: data.count - 22, through: minPos, by: -1) {
            if data[i] == 0x50, data[i + 1] == 0x4b,
               data[i + 2] == 0x05, data[i + 3] == 0x06 {
                return i
            }
        }
        return nil
    }
}

// MARK: - Data helpers (little-endian reads)

private extension Data {
    nonisolated func readLE16(at offset: Int) -> UInt16 {
        guard offset + 1 < count else { return 0 }
        return UInt16(self[offset]) | (UInt16(self[offset + 1]) << 8)
    }

    nonisolated func readLE32(at offset: Int) -> UInt32 {
        guard offset + 3 < count else { return 0 }
        return UInt32(self[offset])
            | (UInt32(self[offset + 1]) << 8)
            | (UInt32(self[offset + 2]) << 16)
            | (UInt32(self[offset + 3]) << 24)
    }
}

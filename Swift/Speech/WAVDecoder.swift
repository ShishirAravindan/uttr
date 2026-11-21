import Foundation

enum WAVDecoderError: Error, LocalizedError, Equatable {
    case notWAV
    case unsupportedFormat(tag: Int, bits: Int)
    case missingData

    var errorDescription: String? {
        switch self {
        case .notWAV: return "The voice returned audio that isn't WAV."
        case .unsupportedFormat(let tag, let bits): return "Unsupported WAV format \(tag) at \(bits) bits."
        case .missingData: return "The voice returned WAV with no audio."
        }
    }
}

/// Decodes RIFF/WAVE PCM (16, 24, 32-bit integer) and 32-bit float into a mono clip,
/// averaging channels.
enum WAVDecoder {
    static func decode(_ data: Data) throws -> SpeechClip {
        let bytes = [UInt8](data)
        guard bytes.count >= 12, ascii(bytes, 0, 4) == "RIFF", ascii(bytes, 8, 4) == "WAVE" else {
            throw WAVDecoderError.notWAV
        }
        var offset = 12
        var formatTag = 0, channels = 0, sampleRate = 0, bits = 0
        var dataRange: Range<Int>?
        while offset + 8 <= bytes.count {
            let id = ascii(bytes, offset, 4)
            let size = Int(uint32(bytes, offset + 4))
            let body = offset + 8
            // A streamed WAV may leave the data size at 0 or 0xFFFFFFFF: read to the end.
            let end = min(bytes.count, size == 0 || size == 0xFFFF_FFFF ? bytes.count : body + size)
            if id == "fmt ", body + 16 <= bytes.count {
                formatTag = Int(uint16(bytes, body))
                channels = Int(uint16(bytes, body + 2))
                sampleRate = Int(uint32(bytes, body + 4))
                bits = Int(uint16(bytes, body + 14))
                // WAVE_FORMAT_EXTENSIBLE carries the real format in its subformat GUID.
                if formatTag == 0xFFFE, body + 26 <= bytes.count {
                    formatTag = Int(uint16(bytes, body + 24))
                }
            } else if id == "data" {
                dataRange = body..<end
                break
            }
            offset = body + size + (size % 2)
        }
        guard let dataRange, channels > 0, sampleRate > 0 else { throw WAVDecoderError.missingData }

        let bytesPerSample = bits / 8
        let isFloat = formatTag == 3 && bits == 32
        guard (formatTag == 1 && [16, 24, 32].contains(bits)) || isFloat else {
            throw WAVDecoderError.unsupportedFormat(tag: formatTag, bits: bits)
        }
        let frameSize = bytesPerSample * channels
        let frames = dataRange.count / frameSize
        var samples = [Float](repeating: 0, count: frames)
        for frame in 0..<frames {
            var sum: Float = 0
            for channel in 0..<channels {
                let at = dataRange.lowerBound + frame * frameSize + channel * bytesPerSample
                sum += sample(bytes, at, bits: bits, isFloat: isFloat)
            }
            samples[frame] = sum / Float(channels)
        }
        return SpeechClip(samples: samples, sampleRate: Double(sampleRate))
    }

    private static func sample(_ b: [UInt8], _ at: Int, bits: Int, isFloat: Bool) -> Float {
        switch bits {
        case 16:
            return Float(Int16(bitPattern: uint16(b, at))) / 32_768
        case 24:
            let value = Int32(b[at]) | Int32(b[at + 1]) << 8 | Int32(Int8(bitPattern: b[at + 2])) << 16
            return Float(value) / 8_388_608
        default:
            let raw = uint32(b, at)
            return isFloat ? Float(bitPattern: raw) : Float(Int32(bitPattern: raw)) / 2_147_483_648
        }
    }

    private static func ascii(_ b: [UInt8], _ at: Int, _ count: Int) -> String {
        guard at + count <= b.count else { return "" }
        return String(decoding: b[at..<at + count], as: UTF8.self)
    }

    private static func uint16(_ b: [UInt8], _ at: Int) -> UInt16 {
        UInt16(b[at]) | UInt16(b[at + 1]) << 8
    }

    private static func uint32(_ b: [UInt8], _ at: Int) -> UInt32 {
        UInt32(b[at]) | UInt32(b[at + 1]) << 8 | UInt32(b[at + 2]) << 16 | UInt32(b[at + 3]) << 24
    }
}

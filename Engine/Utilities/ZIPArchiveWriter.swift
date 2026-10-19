import Foundation

public enum ZIPArchiveError: Error, Sendable {
    case cannotCreateArchive
    case sizeMismatch
}

public final class ZIPArchiveWriter {

    private struct Entry {
        public let name: String
        public let crc: UInt32
        public let size: UInt64
        public let offset: UInt64
        public let isDirectory: Bool
        public let modified: Date
    }

    private static let zip64Threshold: UInt64 = 0xFFFF_FFFF
    private static let chunkSize = 4 * 1024 * 1024

    private let handle: FileHandle
    private var entries: [Entry] = []

    public init(url: URL) throws {
        let fileManager = FileManager.default
        guard fileManager.createFile(atPath: url.path, contents: nil) else {
            throw ZIPArchiveError.cannotCreateArchive
        }
        handle = try FileHandle(forWritingTo: url)
    }

    deinit {
        try? handle.close()
    }

    public func addDirectory(_ path: String, modified: Date = Date()) throws {
        let name = path.hasSuffix("/") ? path : path + "/"
        try writeEntry(name: name, size: 0, isDirectory: true, modified: modified) { _ in }
    }

    public func addFile(_ path: String, data: Data, modified: Date = Date()) throws {
        try writeEntry(name: path, size: UInt64(data.count),
                       isDirectory: false, modified: modified) { write in
            try write(data)
        }
    }

    public func addFile(_ path: String, contentsOf url: URL, modified: Date = Date()) throws {
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        let size = (attributes[.size] as? NSNumber)?.uint64Value ?? 0
        let source = try FileHandle(forReadingFrom: url)
        defer { try? source.close() }
        try writeEntry(name: path, size: size, isDirectory: false, modified: modified) { write in
            while let chunk = try source.read(upToCount: Self.chunkSize), !chunk.isEmpty {
                try write(chunk)
            }
        }
    }

    public func finish() throws {
        let directoryOffset = try handle.offset()
        var directory = Data()
        for entry in entries {
            directory.append(centralDirectoryRecord(for: entry))
        }
        try handle.write(contentsOf: directory)
        try handle.write(contentsOf: endOfCentralDirectory(offset: directoryOffset,
                                                           size: UInt64(directory.count)))
        try handle.close()
    }

    // MARK: - Entry writing

    private func writeEntry(name: String, size: UInt64, isDirectory: Bool, modified: Date,
                            body: ((Data) throws -> Void) throws -> Void) throws {
        let offset = try handle.offset()
        let needsZIP64 = size >= Self.zip64Threshold
        try handle.write(contentsOf: localHeader(name: name, size: size,
                                                 modified: modified, needsZIP64: needsZIP64))
        var crc: UInt32 = 0
        var written: UInt64 = 0
        do {
            try body { chunk in
                crc = CRC32.update(crc, with: chunk)
                written += UInt64(chunk.count)
                try self.handle.write(contentsOf: chunk)
            }
            guard written == size else { throw ZIPArchiveError.sizeMismatch }
        } catch {
            try handle.truncate(atOffset: offset)
            try handle.seek(toOffset: offset)
            throw error
        }
        if size > 0 {
            let end = try handle.offset()
            try handle.seek(toOffset: offset + 14)
            try handle.write(contentsOf: crc.littleEndianData)
            try handle.seek(toOffset: end)
        }
        entries.append(Entry(name: name, crc: crc, size: size, offset: offset,
                             isDirectory: isDirectory, modified: modified))
    }

    private func localHeader(name: String, size: UInt64, modified: Date, needsZIP64: Bool) -> Data {
        let nameBytes = Data(name.utf8)
        let stamp = Self.dosTimestamp(modified)
        var header = Data()
        header.append(UInt32(0x0403_4B50).littleEndianData)
        header.append(UInt16(needsZIP64 ? 45 : 20).littleEndianData)
        header.append(UInt16(0x0800).littleEndianData)
        header.append(UInt16(0).littleEndianData)
        header.append(stamp.time.littleEndianData)
        header.append(stamp.date.littleEndianData)
        header.append(UInt32(0).littleEndianData)
        let storedSize = needsZIP64 ? UInt32(0xFFFF_FFFF) : UInt32(size)
        header.append(storedSize.littleEndianData)
        header.append(storedSize.littleEndianData)
        header.append(UInt16(nameBytes.count).littleEndianData)
        header.append(UInt16(needsZIP64 ? 20 : 0).littleEndianData)
        header.append(nameBytes)
        if needsZIP64 {
            header.append(UInt16(0x0001).littleEndianData)
            header.append(UInt16(16).littleEndianData)
            header.append(size.littleEndianData)
            header.append(size.littleEndianData)
        }
        return header
    }

    private func centralDirectoryRecord(for entry: Entry) -> Data {
        let nameBytes = Data(entry.name.utf8)
        let stamp = Self.dosTimestamp(entry.modified)
        let oversizedEntry = entry.size >= Self.zip64Threshold
        let oversizedOffset = entry.offset >= Self.zip64Threshold
        var extra = Data()
        if oversizedEntry || oversizedOffset {
            var payload = Data()
            if oversizedEntry {
                payload.append(entry.size.littleEndianData)
                payload.append(entry.size.littleEndianData)
            }
            if oversizedOffset {
                payload.append(entry.offset.littleEndianData)
            }
            extra.append(UInt16(0x0001).littleEndianData)
            extra.append(UInt16(payload.count).littleEndianData)
            extra.append(payload)
        }
        var record = Data()
        record.append(UInt32(0x0201_4B50).littleEndianData)
        record.append(UInt16(extra.isEmpty ? 20 : 45).littleEndianData)
        record.append(UInt16(extra.isEmpty ? 20 : 45).littleEndianData)
        record.append(UInt16(0x0800).littleEndianData)
        record.append(UInt16(0).littleEndianData)
        record.append(stamp.time.littleEndianData)
        record.append(stamp.date.littleEndianData)
        record.append(entry.crc.littleEndianData)
        let storedSize = oversizedEntry ? UInt32(0xFFFF_FFFF) : UInt32(entry.size)
        record.append(storedSize.littleEndianData)
        record.append(storedSize.littleEndianData)
        record.append(UInt16(nameBytes.count).littleEndianData)
        record.append(UInt16(extra.count).littleEndianData)
        record.append(UInt16(0).littleEndianData)
        record.append(UInt16(0).littleEndianData)
        record.append(UInt16(0).littleEndianData)
        record.append(UInt32(entry.isDirectory ? 0x41ED_0010 : 0x81A4_0000).littleEndianData)
        record.append((oversizedOffset ? UInt32(0xFFFF_FFFF) : UInt32(entry.offset)).littleEndianData)
        record.append(nameBytes)
        record.append(extra)
        return record
    }

    private func endOfCentralDirectory(offset: UInt64, size: UInt64) -> Data {
        var trailer = Data()
        let needsZIP64 = entries.count > 0xFFFE
            || offset >= Self.zip64Threshold
            || size >= Self.zip64Threshold
        if needsZIP64 {
            let zip64Offset = offset + size
            trailer.append(UInt32(0x0606_4B50).littleEndianData)
            trailer.append(UInt64(44).littleEndianData)
            trailer.append(UInt16(45).littleEndianData)
            trailer.append(UInt16(45).littleEndianData)
            trailer.append(UInt32(0).littleEndianData)
            trailer.append(UInt32(0).littleEndianData)
            trailer.append(UInt64(entries.count).littleEndianData)
            trailer.append(UInt64(entries.count).littleEndianData)
            trailer.append(size.littleEndianData)
            trailer.append(offset.littleEndianData)
            trailer.append(UInt32(0x0706_4B50).littleEndianData)
            trailer.append(UInt32(0).littleEndianData)
            trailer.append(zip64Offset.littleEndianData)
            trailer.append(UInt32(1).littleEndianData)
        }
        let entryCount = needsZIP64 ? UInt16(0xFFFF) : UInt16(entries.count)
        trailer.append(UInt32(0x0605_4B50).littleEndianData)
        trailer.append(UInt16(0).littleEndianData)
        trailer.append(UInt16(0).littleEndianData)
        trailer.append(entryCount.littleEndianData)
        trailer.append(entryCount.littleEndianData)
        trailer.append((needsZIP64 ? UInt32(0xFFFF_FFFF) : UInt32(size)).littleEndianData)
        trailer.append((needsZIP64 ? UInt32(0xFFFF_FFFF) : UInt32(offset)).littleEndianData)
        trailer.append(UInt16(0).littleEndianData)
        return trailer
    }

    private static func dosTimestamp(_ date: Date) -> (time: UInt16, date: UInt16) {
        let calendar = Calendar(identifier: .gregorian)
        let parts = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
        let year = min(max(parts.year ?? 1980, 1980), 2107)
        let dosDate = UInt16((year - 1980) << 9 | (parts.month ?? 1) << 5 | (parts.day ?? 1))
        let dosTime = UInt16((parts.hour ?? 0) << 11 | (parts.minute ?? 0) << 5 | (parts.second ?? 0) / 2)
        return (dosTime, dosDate)
    }
}

public enum CRC32 {

    private static let table: [UInt32] = (0..<256).map { index in
        var value = UInt32(index)
        for _ in 0..<8 {
            value = (value & 1) == 1 ? 0xEDB8_8320 ^ (value >> 1) : value >> 1
        }
        return value
    }

    public static func update(_ crc: UInt32, with data: Data) -> UInt32 {
        var value = crc ^ 0xFFFF_FFFF
        data.withUnsafeBytes { buffer in
            for byte in buffer {
                value = table[Int((value ^ UInt32(byte)) & 0xFF)] ^ (value >> 8)
            }
        }
        return value ^ 0xFFFF_FFFF
    }

    public static func checksum(_ data: Data) -> UInt32 {
        update(0, with: data)
    }
}

private extension FixedWidthInteger {
    var littleEndianData: Data {
        withUnsafeBytes(of: littleEndian) { Data($0) }
    }
}

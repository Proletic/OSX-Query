import Darwin
import Foundation

struct DaemonProcessHandle {
    let process: Process
    let socketPath: String
}

func makeTemporarySelectorCacheSocketPath() -> String {
    FileManager.default.temporaryDirectory
        .appendingPathComponent("osx-selector-cache-\(UUID().uuidString).sock")
        .path
}

func launchSelectorCacheDaemon(socketPath: String) throws -> DaemonProcessHandle {
    let process = Process()
    process.executableURL = productsDirectory.appendingPathComponent("osx")
    process.arguments = [
        "selector-cache-daemon",
        "--socket",
        socketPath,
    ]
    process.standardOutput = FileHandle.nullDevice
    process.standardError = FileHandle.nullDevice

    try process.run()
    try waitForUnixSocket(socketPath: socketPath, timeoutSeconds: 2)
    return DaemonProcessHandle(process: process, socketPath: socketPath)
}

func stopSelectorCacheDaemon(_ handle: DaemonProcessHandle) {
    handle.process.terminate()
    handle.process.waitUntilExit()
    unlink(handle.socketPath)
}

func sendSelectorCacheDaemonRequest(socketPath: String, payload: Data) throws -> Data {
    let fd = try connectUnixSocket(socketPath: socketPath)
    defer { close(fd) }

    try writeAll(payload, to: fd)
    shutdown(fd, SHUT_WR)
    return try readAll(from: fd)
}

private func waitForUnixSocket(socketPath: String, timeoutSeconds: TimeInterval) throws {
    let deadline = Date().addingTimeInterval(timeoutSeconds)

    while Date() < deadline {
        if let fd = try? connectUnixSocket(socketPath: socketPath) {
            close(fd)
            return
        }
        Thread.sleep(forTimeInterval: 0.05)
    }

    throw TestError.generic("Timed out waiting for selector cache daemon socket at \(socketPath).")
}

private func connectUnixSocket(socketPath: String) throws -> Int32 {
    let fd = socket(AF_UNIX, SOCK_STREAM, 0)
    guard fd >= 0 else {
        throw TestError.generic("Failed to create unix socket: \(String(cString: strerror(errno))).")
    }

    do {
        try withSockAddr(path: socketPath) { address, length in
            if Darwin.connect(fd, address, length) != 0 {
                throw TestError.generic("Failed to connect to unix socket: \(String(cString: strerror(errno))).")
            }
        }
        return fd
    } catch {
        close(fd)
        throw error
    }
}

private func readAll(from fd: Int32) throws -> Data {
    var data = Data()
    var buffer = [UInt8](repeating: 0, count: 8192)

    while true {
        let bytesRead = Darwin.read(fd, &buffer, buffer.count)
        if bytesRead > 0 {
            data.append(buffer, count: bytesRead)
            continue
        }
        if bytesRead == 0 {
            return data
        }
        if errno == EINTR {
            continue
        }
        throw TestError.generic("Failed reading daemon response: \(String(cString: strerror(errno))).")
    }
}

private func writeAll(_ data: Data, to fd: Int32) throws {
    try data.withUnsafeBytes { rawBuffer in
        guard let baseAddress = rawBuffer.baseAddress else { return }

        var offset = 0
        while offset < rawBuffer.count {
            let bytesWritten = Darwin.write(fd, baseAddress.advanced(by: offset), rawBuffer.count - offset)
            if bytesWritten > 0 {
                offset += bytesWritten
                continue
            }
            if bytesWritten < 0, errno == EINTR {
                continue
            }
            throw TestError.generic("Failed writing daemon request: \(String(cString: strerror(errno))).")
        }
    }
}

private func withSockAddr<T>(
    path: String,
    _ body: (UnsafePointer<sockaddr>, socklen_t) throws -> T) throws -> T
{
    var address = sockaddr_un()
    address.sun_family = sa_family_t(AF_UNIX)
    let capacity = MemoryLayout.size(ofValue: address.sun_path)

    withUnsafeMutablePointer(to: &address.sun_path) { pointer in
        pointer.withMemoryRebound(to: CChar.self, capacity: capacity) { cStringPtr in
            cStringPtr.initialize(repeating: 0, count: capacity)
            _ = path.withCString { source in
                strncpy(cStringPtr, source, capacity - 1)
            }
        }
    }

    let length = socklen_t(MemoryLayout<sa_family_t>.size + path.utf8.count + 1)
    return try withUnsafePointer(to: &address) { pointer in
        try pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPtr in
            try body(sockaddrPtr, length)
        }
    }
}

import Foundation
@testable import UrbitConnect

final class MemoryTokenStore: TokenStore, @unchecked Sendable {
    private let lock = NSLock()
    private var values: [String: Data] = [:]
    private var writeFailure = false
    private var deleteFailure = false
    func failWrites(_ enabled: Bool) { lock.withLock { writeFailure = enabled } }
    func failDeletes(_ enabled: Bool) { lock.withLock { deleteFailure = enabled } }
    func read(key: String) throws -> Data? { lock.withLock { values[key] } }
    func write(_ data: Data, key: String) throws { try lock.withLock {
        if writeFailure { throw ConnectError.storage("Injected Keychain write failure") }
        values[key] = data
    } }
    func delete(key: String) throws { try lock.withLock {
        if deleteFailure { throw ConnectError.storage("Injected Keychain deletion failure") }
        values.removeValue(forKey: key)
    } }
}

final class TestClock: @unchecked Sendable {
    private let lock = NSLock()
    private var value = Date(timeIntervalSince1970: 1_700_000_000)
    func now() -> Date { lock.withLock { value } }
    func advance(_ seconds: TimeInterval) { lock.withLock { value = value.addingTimeInterval(seconds) } }
}

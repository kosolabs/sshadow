import Synchronization

public final class Flag: Sendable {
    private let value: Atomic<Bool>

    public init(_ initialValue: Bool) {
        self.value = Atomic(initialValue)
    }

    public var isSet: Bool {
        value.load(ordering: .acquiring)
    }

    public func set() {
        value.store(true, ordering: .releasing)
    }

    public func clear() {
        value.store(false, ordering: .releasing)
    }
}

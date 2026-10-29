/// Collects copies while active and hands them back in the order they were copied.
struct PasteStack {
    private(set) var isActive = false
    private(set) var queue: [ClipItem] = []

    mutating func start() {
        isActive = true
        queue = []
    }

    mutating func stop() {
        isActive = false
        queue = []
    }

    mutating func push(_ item: ClipItem) {
        guard isActive else { return }
        queue.append(item)
    }

    /// Returns the oldest collected item; the stack turns itself off once emptied.
    mutating func next() -> ClipItem? {
        guard isActive, !queue.isEmpty else { return nil }
        let item = queue.removeFirst()
        if queue.isEmpty { stop() }
        return item
    }
}

import Foundation
import XCTest
@testable import Takes

/// The takes screen works out each (draft, take) pair's changes once, off the main thread, and keeps the result
/// even when the card that asked stopped wanting it.
@MainActor
final class ChangesCacheTests: XCTestCase {
    private let key = ChangesKey(draft: "i think teh specs", take: "I think the specs")

    /// Counts diffs from the background thread they run on.
    private final class Counter: @unchecked Sendable {
        private let lock = NSLock()
        private var value = 0
        func increment() { lock.lock(); value += 1; lock.unlock() }
        var count: Int { lock.lock(); defer { lock.unlock() }; return value }
    }

    @MainActor private final class Flag { var raised = false }

    /// A cache whose diffs are counted and, with a gate, held until the test lets them finish.
    private func cache(_ counter: Counter, gate: DispatchSemaphore? = nil) -> ChangesCache {
        ChangesCache { key in
            counter.increment()
            _ = gate?.wait(timeout: .now() + 10)
            return WordDiff.changes(from: key.draft, to: key.take)
        }
    }

    func testRepeatedRequestsDiffOnce() async {
        let counter = Counter()
        let cache = cache(counter)
        await cache.load(key)
        await cache.load(key)
        XCTAssertEqual(counter.count, 1)
        XCTAssertEqual(cache.changes(for: key)?.fixCount, 2)
    }

    func testARequestWhileTheDiffRunsWaitsForIt() async {
        let counter = Counter(), gate = DispatchSemaphore(value: 0)
        let cache = cache(counter, gate: gate)
        let first = Task { await cache.load(key) }
        while counter.count == 0 { await Task.yield() }
        // The second request checks for work already running before it first waits, so once it has started it is
        // either waiting on the first diff or has started its own.
        let started = Flag()
        let second = Task {
            started.raised = true
            await cache.load(key)
        }
        while !started.raised { await Task.yield() }
        gate.signal()
        gate.signal()
        await first.value
        await second.value
        XCTAssertEqual(counter.count, 1)
        XCTAssertNotNil(cache.changes(for: key))
    }

    /// ⌥ released before a long diff ends cancels the card's request; the diff still finishes and is kept, so
    /// pressing ⌥ again shows it without diffing again.
    func testACancelledRequestKeepsItsResult() async {
        let counter = Counter(), gate = DispatchSemaphore(value: 0)
        let cache = cache(counter, gate: gate)
        let request = Task { await cache.load(key) }
        while counter.count == 0 { await Task.yield() }
        request.cancel()
        gate.signal()
        await request.value
        XCTAssertNotNil(cache.changes(for: key))
        await cache.load(key)
        XCTAssertEqual(counter.count, 1)
    }

    func testDifferentPairsAreDiffedSeparately() async {
        let counter = Counter()
        let cache = cache(counter)
        let other = ChangesKey(draft: key.draft, take: "I think the specs.")
        await cache.load(key)
        await cache.load(other)
        XCTAssertEqual(counter.count, 2)
        XCTAssertEqual(cache.changes(for: other)?.fixCount, 3)
        XCTAssertNil(cache.changes(for: nil))
    }

    func testOnlyRecentPairsAreKept() async {
        let cache = cache(Counter())
        let keys = (0...ChangesCache.limit).map { ChangesKey(draft: "draft", take: "take \($0)") }
        for key in keys { await cache.load(key) }
        XCTAssertNil(cache.changes(for: keys[0]))
        XCTAssertNotNil(cache.changes(for: keys[ChangesCache.limit]))
        XCTAssertEqual(cache.results.count, ChangesCache.limit)
    }
}

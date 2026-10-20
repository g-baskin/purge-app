import AppKit
import Foundation
import Testing
@testable import Purge

@Suite("Explicit Trash emptying")
struct TrashEmptyingTests {
    @Test func finderScriptCompilesWithoutExecuting() {
        let script = NSAppleScript(source: TrashEmptyingService.scriptSource)
        var error: NSDictionary?
        #expect(script?.compileAndReturnError(&error) == true)
        #expect(error == nil)
    }

    @Test func onlyVerifiedEmptyIsSuccess() {
        #expect(TrashEmptyingService.result(errorNumber: nil, errorMessage: nil, remaining: 0) == .emptied)
        for remaining in [1, 14, -1] {
            if case .failed = TrashEmptyingService.result(errorNumber: nil, errorMessage: nil, remaining: remaining) { } else {
                Issue.record("Nonempty or invalid responses must not report success")
            }
        }
        if case .failed = TrashEmptyingService.result(errorNumber: nil, errorMessage: nil, remaining: nil) { } else {
            Issue.record("Missing response must not report success")
        }
    }

    @Test func permissionFailureExplainsRecovery() {
        let result = TrashEmptyingService.result(errorNumber: -1743, errorMessage: "Denied", remaining: 0)
        guard case .failed(let message) = result else {
            Issue.record("Permission failure was ignored")
            return
        }
        #expect(message.contains("Automation"))
        #expect(message.contains("Finder"))
    }

    @Test func finderHandlerFailureDoesNotClaimCompletion() {
        let result = TrashEmptyingService.result(errorNumber: -10000, errorMessage: "AppleEvent handler failed", remaining: 0)
        guard case .failed(let message) = result else {
            Issue.record("Finder handler failure was ignored")
            return
        }
        #expect(message.contains("may still be running"))
    }

    @Test func finderErrorsAndCancellationAreNotSuccess() {
        #expect(TrashEmptyingService.result(errorNumber: -128, errorMessage: "Cancelled", remaining: 0) == .failed("Cancelled"))
        #expect(TrashEmptyingService.result(errorNumber: -1712, errorMessage: "Timed out", remaining: nil) == .failed("Timed out"))
    }

    /// Injected operations never execute Finder or delete real Trash contents.
    @Test @MainActor func storeFinishesAndRecordsDuration() async {
        let store = TrashStore()
        #expect(!store.isEmptying)
        let result = await store.emptyTrash(using: { .emptied })
        #expect(result == .emptied)
        #expect(!store.isEmptying)
        #expect(store.lastEmptyDuration != nil)
    }

    @Test @MainActor func concurrentRequestsAreIgnored() async {
        let store = TrashStore()
        let gate = DispatchSemaphore(value: 0)
        let first = Task { @MainActor in
            await store.emptyTrash(using: {
                gate.wait()
                return .emptied
            })
        }
        while !store.isEmptying { await Task.yield() }
        let duplicate = await store.emptyTrash(using: {
            Issue.record("A duplicate empty operation must not run")
            return .emptied
        })
        #expect(duplicate == nil)
        gate.signal()
        #expect(await first.value == .emptied)
        #expect(!store.isEmptying)
    }

    @Test @MainActor func storeFailureClearsBusyState() async {
        let store = TrashStore()
        let result = await store.emptyTrash(using: { .failed("Locked item") })
        #expect(result == .failed("Locked item"))
        #expect(!store.isEmptying)
    }
}

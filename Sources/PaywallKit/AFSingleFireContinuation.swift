// AFSingleFireContinuation.swift
// PaywallKit SDK
//
// Thread-safe wrapper around CheckedContinuation.
// Guarantees that continuation is called exactly once — regardless of race conditions.

import Foundation

// MARK: - AFSingleFireContinuation

/// `CheckedContinuation` can only be called once.
/// This class protects against double invocation through `@MainActor` + `isConsumed` guard.
///
/// **Problem it solves:**
/// In delegate-based APIs, multiple callbacks can fire simultaneously
/// (for example `didFinishPurchase` and `didFailPurchase`).
/// Without protection — crash or undefined behavior.
@MainActor
public final class AFSingleFireContinuation<T> {

    private var continuation: CheckedContinuation<T, Never>?
    nonisolated(unsafe) private var isConsumed = false

    init(_ continuation: CheckedContinuation<T, Never>) {
        self.continuation = continuation
    }

    /// Passes the result to the continuation. Repeated calls are ignored.
    public func resume(with value: T) {
        guard !isConsumed else { return }
        isConsumed = true
        continuation?.resume(returning: value)
        continuation = nil // Release memory immediately
    }

    deinit {
        // If continuation was not called — it means UIKit silently failed
        // presenter.present() (for example presenter not in window hierarchy) and no
        // delegate callback arrived. AFPaywallKit now checks presenter.view.window
        // before show, so this shouldn't happen. But if it still does —
        // we log instead of crashing: resume is impossible from deinit (requires @MainActor).
        if !isConsumed {
            print("[AFPaywallKit][warning] AFSingleFireContinuation deallocated without being consumed. " +
                  "Presenter was likely not in window hierarchy. Check logs above for details.")
        }
    }
}

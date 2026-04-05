// AFNetworkReachability.swift
// AdaptyFlowKit SDK
//
// Shared network monitor — used by both OnboardingKit and PaywallKit.
// Replaces: NWPathMonitor that was created every time in OnboardingService.isNetworkAvailable().

import Network
import Foundation

// MARK: - NetworkReachability

/// Singleton for checking network availability.
///
/// **Problem it solves:**
/// Original code created a new `NWPathMonitor` on every `isNetworkAvailable()` call.
/// This is expensive — monitor starts with unknown state and makes first callback with delay.
///
/// **Solution:**
/// One monitor lives all the time. First `await isAvailable()` waits for first callback.
/// Next ones — return cached state immediately.
@MainActor
public final class AFNetworkReachability {

    public static let shared = AFNetworkReachability()
    private init() { startMonitoring() }

    // MARK: - State

    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "FlowKit.NetworkReachability", qos: .utility)

    /// `nil` = first callback hasn't arrived yet.
    private var currentStatus: Bool?
    private var waiters: [CheckedContinuation<Bool, Never>] = []

    // MARK: - Public API

    /// Returns `true` if network is available.
    /// First call waits for callback from NWPathMonitor (~50ms).
    /// Next ones — return cached state immediately.
    public func isAvailable() async -> Bool {
        if let status = currentStatus { return status }

        // First call — wait for pathUpdateHandler
        return await withCheckedContinuation { continuation in
            waiters.append(continuation)
        }
    }

    // MARK: - Private

    private func startMonitoring() {
        monitor.pathUpdateHandler = { [weak self] path in
            let isAvailable = path.status == .satisfied
            Task { @MainActor [weak self] in
                self?.handleUpdate(isAvailable)
            }
        }
        monitor.start(queue: queue)
    }

    private func handleUpdate(_ isAvailable: Bool) {
        currentStatus = isAvailable

        // Wake up all who were waiting for first status
        let pending = waiters
        waiters.removeAll()
        pending.forEach { $0.resume(returning: isAvailable) }
    }

    deinit {
        monitor.cancel()
    }
}

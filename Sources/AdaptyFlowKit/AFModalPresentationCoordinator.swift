// AFModalPresentationCoordinator.swift
// AdaptyFlowKit SDK
//
// Prevents AdaptyFlowKit-owned modal flows from being stacked on each other.

import Foundation

@MainActor
final class AFModalPresentationCoordinator {

    enum Kind: Equatable {
        case paywall
        case rating
    }

    struct Lease: Equatable {
        fileprivate let id: UUID
        let kind: Kind
    }

    static let shared = AFModalPresentationCoordinator()

    private(set) var activeKind: Kind?
    private var activeLeaseID: UUID?

    init() {}

    func acquire(_ kind: Kind) -> Lease? {
        guard activeLeaseID == nil else { return nil }

        let lease = Lease(id: UUID(), kind: kind)
        activeLeaseID = lease.id
        activeKind = kind
        return lease
    }

    func release(_ lease: Lease) {
        guard activeLeaseID == lease.id else { return }
        activeLeaseID = nil
        activeKind = nil
    }
}

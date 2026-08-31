# Changelog

## 1.0.3

- Verified compatibility with Adapty SDK 4.1.2 — no source changes required.
- Correct the Adapty SDK dependency range to `4.0.0..<5.0.0`. The previous lower
  bound (`3.15.0`) referenced a version that was never released, and the kit uses
  4.x-only APIs (`Adapty.getFlow`, `AdaptyUI.getFlowConfiguration`,
  `AdaptyFlowController`) that do not exist in 3.x.
- Fix the stale `AdaptyFlowKit.version` constant, which still reported `1.0.1`.

## 1.0.2

- Prevent RatingKit, PaywallKit, and duplicate RatingKit requests from stacking
  AdaptyFlowKit-owned modal presentations.
- Keep RatingKit interactive when another controller temporarily covers it.
- Release the shared presentation lock when UIKit silently rejects a rating
  presentation during a transition.
- Prevent Adapty and StoreKit paywall continuations from hanging when UIKit
  silently rejects presentation.
- Expose `AFRatingKit.shared.isPresenting` for optional app-level UI gating.

## 1.0.1

- Widen the supported Adapty SDK dependency range to `3.15.0..<5.0.0`.

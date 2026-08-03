# Changelog

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

// AFAnimatedPageControl.swift
// AdaptyFlowKit SDK
//
// Animated page control with smooth width transitions.
// Extracted from AFOnboardingViewController for better code organization.

import UIKit

// MARK: - AFAnimatedPageControl

final class AFAnimatedPageControl: UIControl {

    var numberOfPages: Int = 0 { didSet { rebuild() } }
    var currentPage: Int = 0   { didSet { updateDots() } }
    var activeColor: UIColor   = .systemRed
    var inactiveColor: UIColor = UIColor(white: 0.9, alpha: 1)

    private var dots: [UIView] = []
    private var widthConstraints: [NSLayoutConstraint] = []

    private let activeWidth: CGFloat   = 24
    private let inactiveWidth: CGFloat = 8
    private let dotHeight: CGFloat     = 8
    private let spacing: CGFloat       = 6

    override init(frame: CGRect) { super.init(frame: frame) }
    required init?(coder: NSCoder) { super.init(coder: coder) }
    
    override var intrinsicContentSize: CGSize {
        guard numberOfPages > 0 else { return .zero }
        let totalWidth = activeWidth
            + CGFloat(numberOfPages - 1) * inactiveWidth
            + CGFloat(numberOfPages - 1) * spacing
        return CGSize(width: totalWidth, height: dotHeight)
    }

    private func rebuild() {
        dots.forEach { $0.removeFromSuperview() }
        dots = []
        widthConstraints = []
        var prev: UIView? = nil

        for i in 0..<numberOfPages {
            let dot = UIView()
            dot.layer.cornerRadius = dotHeight / 2
            dot.backgroundColor = i == currentPage ? activeColor : inactiveColor
            dot.translatesAutoresizingMaskIntoConstraints = false
            dot.isUserInteractionEnabled = true
            let tap = UITapGestureRecognizer(target: self, action: #selector(dotTapped(_:)))
            dot.addGestureRecognizer(tap)
            dot.tag = i
            addSubview(dot)

            let width = i == currentPage ? activeWidth : inactiveWidth

            let wc = dot.widthAnchor.constraint(equalToConstant: width)
            wc.priority = .defaultHigh
            widthConstraints.append(wc)

            NSLayoutConstraint.activate([
                dot.centerYAnchor.constraint(equalTo: centerYAnchor),
                dot.heightAnchor.constraint(equalToConstant: dotHeight),
                wc,
            ])

            if let prev = prev {
                let spacing = dot.leadingAnchor.constraint(equalTo: prev.trailingAnchor, constant: spacing)
                spacing.priority = .defaultHigh
                spacing.isActive = true
            } else {
                dot.leadingAnchor.constraint(equalTo: leadingAnchor).isActive = true
            }

            dots.append(dot)
            prev = dot
        }

        if let last = dots.last {
            let trailing = last.trailingAnchor.constraint(equalTo: trailingAnchor)
            trailing.priority = .defaultHigh
            trailing.isActive = true
        }
    }

    private func updateDots() {
        guard dots.count == numberOfPages else { return }
        UIView.animate(withDuration: 0.3, delay: 0, usingSpringWithDamping: 0.7, initialSpringVelocity: 0.5) {
            for (i, dot) in self.dots.enumerated() {
                let isActive = i == self.currentPage
                self.widthConstraints[i].constant = isActive ? self.activeWidth : self.inactiveWidth
                dot.backgroundColor = isActive ? self.activeColor : self.inactiveColor
            }
            self.layoutIfNeeded()
        }
    }

    @objc private func dotTapped(_ gesture: UITapGestureRecognizer) {
        guard let dot = gesture.view else { return }
        currentPage = dot.tag
        sendActions(for: .valueChanged)
    }
}

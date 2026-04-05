//
// OnboardingViewController.swift
// AdaptyFlowKit SDK
//
//
//

import Foundation
import UIKit

// MARK: - Model

/// Model for a single onboarding page.
/// Pass an array of these pages to AFDefaultOnboardingAdapter to configure content.
public struct AFOnboardingPage {
    public let title: String
    public let subtitle: String
    
    /// SF Symbol name (e.g. "star.fill") or image name from Assets
    public let iconName: String
    
    /// If true - iconName is an image name from Assets, if false - SF Symbol
    public let isCustomImage: Bool
    
    public let iconBackgroundColor: UIColor
    
    /// Optional action executed when Continue is tapped on this page.
    /// Use for permission requests (notifications, location, camera, etc.).
    /// Called BEFORE transitioning to the next page.
    public let onContinue: (() -> Void)?
    
    public init(
        title: String,
        subtitle: String,
        iconName: String,
        iconBackgroundColor: UIColor,
        isCustomImage: Bool = false,
        onContinue: (() -> Void)? = nil
    ) {
        self.title = title
        self.subtitle = subtitle
        self.iconName = iconName
        self.isCustomImage = isCustomImage
        self.iconBackgroundColor = iconBackgroundColor
        self.onContinue = onContinue
    }
}

// MARK: - AFOnboardingViewController

final class AFOnboardingViewController: UIViewController {

    // MARK: - Completion Handler
    
    var onCompletion: (() -> Void)?

    // MARK: - Data

    private let pages: [AFOnboardingPage]
    
    // MARK: - Default Pages
    
    private static let defaultPages: [AFOnboardingPage] = [
        AFOnboardingPage(
            title: "title 1",
            subtitle: "subtitle 1",
            iconName: "star.fill",
            iconBackgroundColor: .systemBlue,
            isCustomImage: false,
            onContinue: nil
        ),
        AFOnboardingPage(
            title: "title 2",
            subtitle: "subtitle 2",
            iconName: "heart.fill",
            iconBackgroundColor: .systemBlue,
            isCustomImage: false,
            onContinue: nil
        ),
        AFOnboardingPage(
            title: "title 3",
            subtitle: "subtitle 3",
            iconName: "bolt.fill",
            iconBackgroundColor: .systemBlue,
            isCustomImage: false,
            onContinue: nil
        )
    ]

    private var currentIndex: Int = 0
    private var isAnimating: Bool = false

    // MARK: - Accent Color

    private let accentColor: UIColor

    // MARK: - UI Elements

    private let skipButton: UIButton = {
        let btn = UIButton(type: .system)
        btn.setTitle("Skip", for: .normal)
        btn.titleLabel?.font = .systemFont(ofSize: 16, weight: .medium)
        btn.setTitleColor(.systemGray, for: .normal)
        btn.translatesAutoresizingMaskIntoConstraints = false
        return btn
    }()
    
    private let backButton: UIButton = {
        let btn = UIButton(type: .system)
        btn.setTitle("Back", for: .normal)
        btn.titleLabel?.font = .systemFont(ofSize: 16, weight: .medium)
        btn.setTitleColor(.systemGray, for: .normal)
        btn.translatesAutoresizingMaskIntoConstraints = false
        btn.alpha = 0
        return btn
    }()

    // ScrollView for content
    private let scrollView: UIScrollView = {
        let sv = UIScrollView()
        sv.showsVerticalScrollIndicator = true
        sv.showsHorizontalScrollIndicator = false
        sv.translatesAutoresizingMaskIntoConstraints = false
        return sv
    }()
    
    // Container for stack view
    private let contentStackView: UIStackView = {
        let stack = UIStackView()
        stack.axis = .vertical
        stack.alignment = .fill
        stack.spacing = 20
        stack.translatesAutoresizingMaskIntoConstraints = false
        return stack
    }()

    private let illustrationImageView: UIImageView = {
        let iv = UIImageView()
        iv.contentMode = .scaleAspectFit
        iv.clipsToBounds = true
        iv.translatesAutoresizingMaskIntoConstraints = false
        return iv
    }()

    private let titleLabel: UILabel = {
        let lbl = UILabel()
        lbl.numberOfLines = 0
        lbl.textColor = UIColor.label
        lbl.textAlignment = .center
        lbl.translatesAutoresizingMaskIntoConstraints = false
        return lbl
    }()

    private let subtitleLabel: UILabel = {
        let lbl = UILabel()
        lbl.numberOfLines = 0
        lbl.font = .systemFont(ofSize: 16, weight: .regular)
        lbl.textColor = .secondaryLabel
        lbl.textAlignment = .center
        lbl.lineBreakMode = .byWordWrapping
        lbl.translatesAutoresizingMaskIntoConstraints = false
        return lbl
    }()

    private lazy var pageControl: AFAnimatedPageControl = {
        let pc = AFAnimatedPageControl()
        pc.numberOfPages = pages.count
        pc.currentPage = 0
        pc.activeColor = accentColor
        pc.inactiveColor = UIColor(white: 0.9, alpha: 1)
        pc.translatesAutoresizingMaskIntoConstraints = false
        pc.addTarget(self, action: #selector(pageControlTapped(_:)), for: .valueChanged)
        return pc
    }()

    private lazy var primaryButton: UIButton = {
        let btn = UIButton(type: .system)
        btn.layer.cornerRadius = 16
        btn.backgroundColor = accentColor
        btn.setTitleColor(.white, for: .normal)
        btn.titleLabel?.font = .systemFont(ofSize: 16, weight: .semibold)
        btn.translatesAutoresizingMaskIntoConstraints = false
        btn.addTarget(self, action: #selector(primaryButtonTapped), for: .touchUpInside)
        btn.layer.shadowColor = accentColor.withAlphaComponent(0.35).cgColor
        btn.layer.shadowOffset = CGSize(width: 0, height: 4)
        btn.layer.shadowRadius = 12
        btn.layer.shadowOpacity = 1
        return btn
    }()

    private var primaryButtonHeightConstraint: NSLayoutConstraint!

    // MARK: - Initialization
    
    /// Creates onboarding with custom pages.
    /// - Parameters:
    ///   - pages: Array of onboarding pages. If empty or nil, default pages are used.
    ///   - accentColor: Color for buttons and page control. If nil, .systemBlue is used
    init(pages: [AFOnboardingPage]? = nil, accentColor: UIColor? = nil) {
        // Validation: use custom pages if they're not empty, otherwise use defaults
        if let customPages = pages, !customPages.isEmpty {
            self.pages = customPages
        } else {
            self.pages = Self.defaultPages
        }
        
        // Use custom accent color or default .systemBlue
        self.accentColor = accentColor ?? .systemBlue
        
        super.init(nibName: nil, bundle: nil)
    }
    
    required init?(coder: NSCoder) {
        self.pages = Self.defaultPages
        self.accentColor = .systemBlue
        super.init(coder: coder)
    }

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        print("[AFOnboardingViewController]  viewDidLoad - pages count: \(pages.count)")
        setupUI()
        setupGestures()
        configure(with: pages[currentIndex], animated: false, direction: .forward)
        print("[AFOnboardingViewController]  Setup complete")
    }
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        print("[AFOnboardingViewController]  viewDidAppear - controller is visible")
        print("[AFOnboardingViewController]  View frame: \(view.frame)")
        print("[AFOnboardingViewController]  View subviews count: \(view.subviews.count)")
        print("[AFOnboardingViewController]  View background: \(view.backgroundColor?.description ?? "nil")")
        
        // Debug: List all subviews
        for (index, subview) in view.subviews.enumerated() {
            print("[AFOnboardingViewController]   └─ Subview[\(index)]: \(type(of: subview)) - frame: \(subview.frame), alpha: \(subview.alpha)")
        }
    }

    // MARK: - Setup

    private func setupUI() {
        view.backgroundColor = .systemBackground

        // Add main components
        view.addSubview(backButton)
        view.addSubview(skipButton)
        view.addSubview(scrollView)
        view.addSubview(pageControl)
        view.addSubview(primaryButton)
        
        // Add stack view to scroll view
        scrollView.addSubview(contentStackView)
        
        // Add content to stack: image, title, subtitle
        contentStackView.addArrangedSubview(illustrationImageView)
        contentStackView.addArrangedSubview(titleLabel)
        contentStackView.addArrangedSubview(subtitleLabel)
        
        // Add spacer view at the bottom of stack
        let spacerView = UIView()
        spacerView.translatesAutoresizingMaskIntoConstraints = false
        spacerView.setContentHuggingPriority(.defaultLow, for: .vertical)
        contentStackView.addArrangedSubview(spacerView)

        primaryButtonHeightConstraint = primaryButton.heightAnchor.constraint(equalToConstant: 54)

        NSLayoutConstraint.activate([
            // Back button - top left corner
            backButton.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 16),
            backButton.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24),
            
            // Skip button - top right corner
            skipButton.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 16),
            skipButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24),

            // ScrollView - below buttons, above page control
            scrollView.topAnchor.constraint(equalTo: skipButton.bottomAnchor, constant: 16),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: pageControl.topAnchor, constant: -16),
            
            // Content stack view inside scroll view
            contentStackView.topAnchor.constraint(equalTo: scrollView.topAnchor),
            contentStackView.leadingAnchor.constraint(equalTo: scrollView.leadingAnchor, constant: 24),
            contentStackView.trailingAnchor.constraint(equalTo: scrollView.trailingAnchor, constant: -24),
            contentStackView.bottomAnchor.constraint(equalTo: scrollView.bottomAnchor),
            contentStackView.widthAnchor.constraint(equalTo: scrollView.widthAnchor, constant: -48),
            
            // Image - full width, maintain aspect ratio
            illustrationImageView.widthAnchor.constraint(equalTo: contentStackView.widthAnchor),
            
            // Title padding
            titleLabel.widthAnchor.constraint(equalTo: contentStackView.widthAnchor),
            
            // Subtitle padding
            subtitleLabel.widthAnchor.constraint(equalTo: contentStackView.widthAnchor),

            // Page control - above primary button
            pageControl.bottomAnchor.constraint(equalTo: primaryButton.topAnchor, constant: -24),
            pageControl.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            pageControl.heightAnchor.constraint(equalToConstant: 8),

            // Primary button - at bottom
            primaryButton.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -24),
            primaryButton.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 32),
            primaryButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -32),
            primaryButtonHeightConstraint,
        ])

        backButton.addTarget(self, action: #selector(backButtonTapped), for: .touchUpInside)
        skipButton.addTarget(self, action: #selector(skipTapped), for: .touchUpInside)
    }

    private func setupGestures() {
        let swipeLeft = UISwipeGestureRecognizer(target: self, action: #selector(handleSwipe(_:)))
        swipeLeft.direction = .left
        let swipeRight = UISwipeGestureRecognizer(target: self, action: #selector(handleSwipe(_:)))
        swipeRight.direction = .right
        view.addGestureRecognizer(swipeLeft)
        view.addGestureRecognizer(swipeRight)
    }

    // MARK: - Configuration

    enum TransitionDirection {
        case forward, backward
    }

    /// Animatable content views — ordered so stagger looks natural top→bottom.
    private var contentViews: [UIView] {
        [contentStackView]
    }

    private func configure(
        with page: AFOnboardingPage,
        animated: Bool,
        direction: TransitionDirection
    ) {
        let slideOffset: CGFloat = direction == .forward ? 60 : -60

        // ---------- helpers ----------

        let applyStaticContent = {
            self.pageControl.currentPage = self.currentIndex

            let isFirst = self.currentIndex == 0
            let isLast  = self.currentIndex == self.pages.count - 1

            // Show/hide skip button
            self.skipButton.alpha = isLast ? 0 : 1
            
            // Show/hide back button
            self.animateBackButton(show: !isFirst, animated: animated)
            
            // Update primary button title
            self.primaryButton.setTitle(isLast ? "Get Started" : "Continue", for: .normal)
        }

        let applyPageContent = {
            // Load image: custom from Assets or SF Symbol
            if page.isCustomImage {
                // Custom image from Assets - full width, maintain aspect ratio
                if let image = UIImage(named: page.iconName) {
                    self.illustrationImageView.image = image
                    self.illustrationImageView.contentMode = .scaleAspectFit
                    
                    // Calculate height based on aspect ratio to maintain proportions
                    let aspectRatio = image.size.height / image.size.width
                    let imageWidth = self.view.bounds.width - 48 // minus padding
                    let imageHeight = imageWidth * aspectRatio
                    
                    // Remove previous height constraint if exists
                    self.illustrationImageView.constraints.forEach { constraint in
                        if constraint.firstAttribute == .height {
                            constraint.isActive = false
                        }
                    }
                    
                    // Set new height constraint
                    let heightConstraint = self.illustrationImageView.heightAnchor.constraint(equalToConstant: imageHeight)
                    heightConstraint.priority = .defaultHigh
                    heightConstraint.isActive = true
                }
                self.illustrationImageView.tintColor = nil
            } else {
                // SF Symbol
                let config = UIImage.SymbolConfiguration(pointSize: 120, weight: .thin)
                self.illustrationImageView.image = UIImage(systemName: page.iconName, withConfiguration: config)
                self.illustrationImageView.contentMode = .scaleAspectFit
                self.illustrationImageView.tintColor = page.iconBackgroundColor
                
                // Fixed height for SF Symbols
                self.illustrationImageView.constraints.forEach { $0.isActive = false }
                let heightConstraint = self.illustrationImageView.heightAnchor.constraint(equalToConstant: 200)
                heightConstraint.isActive = true
            }

            // Title font - system font, bold and prominent
            self.titleLabel.font = .systemFont(ofSize: 32, weight: .bold)
            self.titleLabel.text = page.title
            
            // Subtitle - system font, standard iOS size for body text
            self.subtitleLabel.font = .systemFont(ofSize: 17, weight: .regular)
            self.subtitleLabel.text = page.subtitle
            
            // Reset scroll position to top
            self.scrollView.setContentOffset(.zero, animated: false)
        }

        guard animated else {
            applyPageContent()
            applyStaticContent()
            return
        }

        isAnimating = true

        // 1. Slide + fade OUT current content
        let outOffset: CGFloat = -slideOffset
        let outDuration: TimeInterval = 0.22

        UIView.animate(
            withDuration: outDuration,
            delay: 0,
            options: [.curveEaseIn]
        ) {
            for (i, v) in self.contentViews.enumerated() {
                let staggeredOffset = outOffset - CGFloat(i) * 6
                v.transform = CGAffineTransform(translationX: staggeredOffset, y: 0)
                v.alpha = 0
            }
        } completion: { _ in

            // 2. Update content while invisible
            applyPageContent()
            applyStaticContent()

            // 3. Pre-position new content on the opposite side (ready to slide in)
            for v in self.contentViews {
                v.transform = CGAffineTransform(translationX: slideOffset, y: 0)
                v.alpha = 0
            }

            // 4. Slide + fade IN — staggered per element
            let inDuration: TimeInterval = 0.38
            let staggerDelay: TimeInterval = 0.045

            for (i, v) in self.contentViews.enumerated() {
                UIView.animate(
                    withDuration: inDuration,
                    delay: Double(i) * staggerDelay,
                    usingSpringWithDamping: 0.82,
                    initialSpringVelocity: 0.3,
                    options: [.curveEaseOut]
                ) {
                    v.transform = .identity
                    v.alpha = 1
                } completion: { _ in
                    if i == self.contentViews.count - 1 {
                        self.isAnimating = false
                    }
                }
            }

            // 5. Animate illustration icon scale bounce
            self.illustrationImageView.transform = CGAffineTransform(scaleX: 0.75, y: 0.75)
            UIView.animate(
                withDuration: 0.5,
                delay: 0,
                usingSpringWithDamping: 0.6,
                initialSpringVelocity: 0.4,
                options: []
            ) {
                self.illustrationImageView.transform = .identity
            }
        }
    }

    // MARK: - Back Button Animation

    private func animateBackButton(show: Bool, animated: Bool) {
        guard animated else {
            backButton.alpha = show ? 1 : 0
            return
        }

        if show {
            // Fade in back button
            UIView.animate(
                withDuration: 0.3,
                delay: 0,
                options: [.curveEaseOut]
            ) {
                self.backButton.alpha = 1
            }
        } else {
            // Fade out back button
            UIView.animate(
                withDuration: 0.2,
                delay: 0,
                options: [.curveEaseIn]
            ) {
                self.backButton.alpha = 0
            }
        }
    }

    // MARK: - Navigation

    private func goToNext() {
        guard !isAnimating else { 
            print("[AFOnboardingViewController]  goToNext blocked - animation in progress")
            return 
        }
        guard currentIndex < pages.count - 1 else { 
            print("[AFOnboardingViewController]  Last page reached - calling finish()")
            finish()
            return 
        }
        print("[AFOnboardingViewController]  Going to next page: \(currentIndex) -> \(currentIndex + 1)")
        currentIndex += 1
        configure(with: pages[currentIndex], animated: true, direction: .forward)
    }

    private func goToPrevious() {
        guard !isAnimating, currentIndex > 0 else { return }
        print("[AFOnboardingViewController]  Going to previous page: \(currentIndex) -> \(currentIndex - 1)")
        currentIndex -= 1
        configure(with: pages[currentIndex], animated: true, direction: .backward)
    }

    private func finish() {
        print("[AFOnboardingViewController]  finish() called - notifying completion handler")
        print("[AFOnboardingViewController]  onCompletion callback exists: \(onCompletion != nil)")
        onCompletion?()
        print("[AFOnboardingViewController]  onCompletion callback invoked")
    }

    // MARK: - Actions

    @objc private func primaryButtonTapped() {
        print("[AFOnboardingViewController]  Primary button tapped - current page: \(currentIndex)")
        animateButtonPress(primaryButton)
        
        // Call optional action for current page
        pages[currentIndex].onContinue?()
        
        goToNext()
    }

    @objc private func backButtonTapped() {
        print("[AFOnboardingViewController]  Back button tapped")
        goToPrevious()
    }

    @objc private func skipTapped() {
        print("[AFOnboardingViewController]  Skip button tapped")
        finish()
    }

    @objc private func pageControlTapped(_ sender: AFAnimatedPageControl) {
        let target = sender.currentPage
        guard target != currentIndex, !isAnimating else { return }
        let direction: TransitionDirection = target > currentIndex ? .forward : .backward
        currentIndex = target
        configure(with: pages[currentIndex], animated: true, direction: direction)
    }

    @objc private func handleSwipe(_ gesture: UISwipeGestureRecognizer) {
        switch gesture.direction {
        case .left:  goToNext()
        case .right: goToPrevious()
        default: break
        }
    }

    // MARK: - Helpers

    private func animateButtonPress(_ button: UIButton) {
        UIView.animate(withDuration: 0.1, animations: {
            button.transform = CGAffineTransform(scaleX: 0.97, y: 0.97)
        }) { _ in
            UIView.animate(withDuration: 0.1) {
                button.transform = .identity
            }
        }
    }
}

// MARK: - UILabel Letter Spacing Helper

private extension UILabel {
    func letterSpacing(_ value: CGFloat) {
        guard let text = self.text else { return }
        let attributed = NSAttributedString(
            string: text,
            attributes: [.kern: value]
        )
        self.attributedText = attributed
    }
}
// MARK: - Preview

#if DEBUG
import SwiftUI

@available(iOS 13.0, *)
struct AFOnboardingViewController_Preview: PreviewProvider {
    static var previews: some View {
        OnboardingPreviewWrapper()
            .ignoresSafeArea()
    }
    
    struct OnboardingPreviewWrapper: UIViewControllerRepresentable {
        func makeUIViewController(context: Context) -> AFOnboardingViewController {
            return AFOnboardingViewController(pages: nil)
        }
        
        func updateUIViewController(_ uiViewController: AFOnboardingViewController, context: Context) {
        }
    }
}
#endif


// AFDefaultPaywallAdapter.swift
// AdaptyFlowKit SDK
//
// Simple, clean paywall without images and trial toggle.
// Integrates with one line: fallbackUI: DefaultPaywallAdapter.self

import UIKit

// MARK: - DefaultPaywallAdapter

public final class AFDefaultPaywallAdapter: UIViewController, AFPaywallKitUI, UIAdaptivePresentationControllerDelegate, UISheetPresentationControllerDelegate {

    // MARK: - Static Configuration
    //
    // Set before showing paywall — usually in AppDelegate or PaywallKit.configure().

    /// URL Privacy Policy. If `nil` — button is inactive (but visible).
    public static var privacyURL: URL? = nil

    /// URL Terms of Use. Default - standard Apple EULA.
    public static var termsURL: URL? = URL(string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/")

    // MARK: - AFPaywallKitUI

    @MainActor
    public static func make(context: AFPaywallUIContext) -> UIViewController {
        let vc = AFDefaultPaywallAdapter()
        vc.context = context
        vc.modalPresentationStyle = .fullScreen
        return vc
    }

    // MARK: - Properties

    private var context: AFPaywallUIContext!
    private var selectedProduct: AFPaywallProduct?
    private var didClose = false
    private var pendingHeaderView: UIView?

    private var accentColor: UIColor { context.accentColor }

    // MARK: - UI

    private lazy var closeButton: UIButton = {
        let b = UIButton(type: .system)
        let cfg = UIImage.SymbolConfiguration(pointSize: 16, weight: .semibold)
        b.setImage(UIImage(systemName: "xmark", withConfiguration: cfg), for: .normal)
        b.tintColor = .tertiaryLabel
        b.backgroundColor = .clear
        b.translatesAutoresizingMaskIntoConstraints = false
        b.addTarget(self, action: #selector(closeTapped), for: .touchUpInside)
        return b
    }()

    private lazy var tableView: UITableView = {
        let tv = UITableView(frame: .zero, style: .plain)
        tv.separatorStyle = .none
        tv.backgroundColor = .clear
        tv.showsVerticalScrollIndicator = false
        tv.rowHeight = 82
        tv.translatesAutoresizingMaskIntoConstraints = false
        tv.dataSource = self
        tv.delegate = self
        tv.register(PlanCell.self, forCellReuseIdentifier: PlanCell.reuseId)
        return tv
    }()

    private lazy var continueButton: UIButton = {
        let b = UIButton(type: .system)
        b.setTitle("Continue", for: .normal)
        b.titleLabel?.font = .systemFont(ofSize: 17, weight: .semibold)
        b.setTitleColor(.white, for: .normal)
        b.setTitleColor(UIColor.white.withAlphaComponent(0.5), for: .disabled)
        b.backgroundColor = self.accentColor
        b.layer.cornerRadius = 16
        b.layer.cornerCurve = .continuous
        b.isEnabled = false
        b.alpha = 0.5
        b.translatesAutoresizingMaskIntoConstraints = false
        b.addTarget(self, action: #selector(continueTapped), for: .touchUpInside)
        return b
    }()

    private lazy var bottomStack: UIStackView = {
        let s = UIStackView(arrangedSubviews: [termsButton, privacyButton, restoreButton])
        s.axis = .horizontal
        s.spacing = 0
        s.distribution = .fillEqually
        s.translatesAutoresizingMaskIntoConstraints = false
        return s
    }()

    private lazy var termsButton   = makeTextButton("Terms of Use",   action: #selector(termsTapped))
    private lazy var privacyButton = makeTextButton("Privacy Policy", action: #selector(privacyTapped))
    private lazy var restoreButton = makeTextButton("Restore",        action: #selector(restoreTapped))

    private lazy var loadingOverlay: UIView = {
        let v = UIView()
        v.backgroundColor = UIColor.black.withAlphaComponent(0.35)
        v.isHidden = true
        v.translatesAutoresizingMaskIntoConstraints = false

        let spinner = UIActivityIndicatorView(style: .large)
        spinner.color = .white
        spinner.startAnimating()
        spinner.translatesAutoresizingMaskIntoConstraints = false
        v.addSubview(spinner)
        NSLayoutConstraint.activate([
            spinner.centerXAnchor.constraint(equalTo: v.centerXAnchor),
            spinner.centerYAnchor.constraint(equalTo: v.centerYAnchor)
        ])
        return v
    }()

    // MARK: - Lifecycle

    public override func viewDidLoad() {
        super.viewDidLoad()
        setupLayout()
        buildTableHeader()
        selectDefault()
        observeState()
    }

    public override func viewSafeAreaInsetsDidChange() {
        super.viewSafeAreaInsetsDidChange()
        let top = view.safeAreaInsets.top + 16 + 32 + 20
        tableView.contentInset.top = top
        tableView.scrollIndicatorInsets.top = top
    }

    public override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        let targetWidth = tableView.bounds.width
        guard targetWidth > 0 else { return }

        // First layout: assign the header now that tableView has a real width,
        // avoiding UIView-Encapsulated-Layout-Width == 0 conflicts.
        if let pending = pendingHeaderView {
            let height = pending.systemLayoutSizeFitting(
                CGSize(width: targetWidth, height: UIView.layoutFittingCompressedSize.height),
                withHorizontalFittingPriority: .required,
                verticalFittingPriority: .fittingSizeLevel
            ).height
            pending.frame = CGRect(x: 0, y: 0, width: targetWidth, height: height)
            tableView.tableHeaderView = pending
            pendingHeaderView = nil
            return
        }

        // Subsequent layouts (e.g. rotation): resize existing header.
        guard let header = tableView.tableHeaderView else { return }
        let height = header.systemLayoutSizeFitting(
            CGSize(width: targetWidth, height: UIView.layoutFittingCompressedSize.height),
            withHorizontalFittingPriority: .required,
            verticalFittingPriority: .fittingSizeLevel
        ).height
        if header.frame.height != height {
            header.frame = CGRect(x: 0, y: 0, width: targetWidth, height: height)
            tableView.tableHeaderView = header
        }
    }

    public override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        if isBeingDismissed && !didClose {
            didClose = true
            context.close()
        }
    }

    // MARK: - UIAdaptivePresentationControllerDelegate

    public func presentationControllerDidDismiss(_ presentationController: UIPresentationController) {
        if !didClose {
            didClose = true
            context.close()
        }
    }

    // MARK: - Layout

    private func setupLayout() {
        view.backgroundColor = .systemBackground

        // tableView fills the view; closeButton floats above it
        view.addSubview(tableView)
        view.addSubview(closeButton)
        view.addSubview(continueButton)
        view.addSubview(bottomStack)
        view.addSubview(loadingOverlay)

        NSLayoutConstraint.activate([

            // Close — fixed top-right, floats above tableView
            closeButton.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 16),
            closeButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
            closeButton.widthAnchor.constraint(equalToConstant: 32),
            closeButton.heightAnchor.constraint(equalToConstant: 32),

            // Bottom bar — pinned to safeArea bottom
            bottomStack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            bottomStack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
            bottomStack.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -16),

            // Continue button — fixed above bottom bar
            continueButton.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            continueButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
            continueButton.bottomAnchor.constraint(equalTo: bottomStack.topAnchor, constant: -12),
            continueButton.heightAnchor.constraint(equalToConstant: 54),

            // TableView — from view top to continueButton; contentInset handles close button gap
            tableView.topAnchor.constraint(equalTo: view.topAnchor),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: continueButton.topAnchor, constant: -8),

            // Loading overlay — full screen
            loadingOverlay.topAnchor.constraint(equalTo: view.topAnchor),
            loadingOverlay.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            loadingOverlay.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            loadingOverlay.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
    }

    // MARK: - Table header (title + subtitle)

    private func buildTableHeader() {
        let title    = context.title
        let subtitle = context.subtitle
        // Skip header if both are nil or empty strings
        guard !(title ?? "").isEmpty || !(subtitle ?? "").isEmpty else { return }

        let header = UIView()

        let titleLabel = UILabel()
        titleLabel.text = title
        titleLabel.font = .systemFont(ofSize: 28, weight: .bold)
        titleLabel.textColor = .label
        titleLabel.textAlignment = .center
        titleLabel.numberOfLines = 0
        titleLabel.translatesAutoresizingMaskIntoConstraints = false

        let subtitleLabel = UILabel()
        subtitleLabel.text = subtitle
        subtitleLabel.font = .systemFont(ofSize: 15)
        subtitleLabel.textColor = .secondaryLabel
        subtitleLabel.textAlignment = .center
        subtitleLabel.numberOfLines = 0
        subtitleLabel.translatesAutoresizingMaskIntoConstraints = false

        let stack = UIStackView(arrangedSubviews: [titleLabel, subtitleLabel])
        stack.axis = .vertical
        stack.spacing = 8
        stack.alignment = .center
        stack.translatesAutoresizingMaskIntoConstraints = false
        header.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: header.topAnchor, constant: 16),
            stack.leadingAnchor.constraint(equalTo: header.leadingAnchor, constant: 32),
            stack.trailingAnchor.constraint(equalTo: header.trailingAnchor, constant: -32),
            stack.bottomAnchor.constraint(equalTo: header.bottomAnchor, constant: -16),
        ])

        // Don't assign to tableHeaderView yet — defer to viewDidLayoutSubviews
        // so tableView has a real width and avoids UIView-Encapsulated-Layout-Width==0 conflicts.
        pendingHeaderView = header
    }

    // MARK: - Selection

    private func selectDefault() {
        let product = context.products.first(where: { $0.isPopular }) ?? context.products.first
        guard let product else { return }
        select(product)
    }

    private func select(_ product: AFPaywallProduct) {
        selectedProduct = product
        tableView.reloadData()

        let title = product.introductoryOffer != nil ? "Try Free & Subscribe" : "Continue"
        UIView.performWithoutAnimation {
            continueButton.setTitle(title, for: .normal)
            continueButton.layoutIfNeeded()
        }
        continueButton.isEnabled = true
        UIView.animate(withDuration: 0.2) { self.continueButton.alpha = 1 }
    }

    // MARK: - State

    private func observeState() {
        context.onStateChange = { [weak self] state in
            self?.apply(state)
        }
    }

    private func apply(_ state: AFPaywallUIState) {
        switch state {
        case .idle:
            setLoading(false)
        case .purchasing, .restoring, .loading:
            setLoading(true)
        case .success:
            setLoading(false)
        case .error(let message):
            setLoading(false)
            let alert = UIAlertController(title: nil, message: message, preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "OK", style: .default))
            present(alert, animated: true)
        }
    }

    private func setLoading(_ loading: Bool) {
        loadingOverlay.isHidden = !loading
        continueButton.isEnabled = !loading
        tableView.isUserInteractionEnabled = !loading
    }

    // MARK: - Actions

    @objc private func continueTapped() {
        guard let product = selectedProduct else { return }
        context.purchase(product)
    }

    @objc private func restoreTapped() {
        context.restore()
    }

    @objc private func closeTapped() {
        didClose = true
        context.close()
    }

    @objc private func termsTapped() {
        guard let url = AFDefaultPaywallAdapter.termsURL else { return }
        UIApplication.shared.open(url)
    }

    @objc private func privacyTapped() {
        guard let url = AFDefaultPaywallAdapter.privacyURL else { return }
        UIApplication.shared.open(url)
    }

    // MARK: - Helpers

    private func makeTextButton(_ title: String, action: Selector) -> UIButton {
        let b = UIButton(type: .system)
        b.setTitle(title, for: .normal)
        b.titleLabel?.font = .systemFont(ofSize: 12)
        b.titleLabel?.numberOfLines = 2
        b.titleLabel?.textAlignment = .center
        b.titleLabel?.lineBreakMode = .byWordWrapping
        b.setTitleColor(.tertiaryLabel, for: .normal)
        b.addTarget(self, action: action, for: .touchUpInside)
        return b
    }
}

// MARK: - UITableViewDataSource, UITableViewDelegate

extension AFDefaultPaywallAdapter: UITableViewDataSource, UITableViewDelegate {

    public func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        context.products.count
    }

    public func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: PlanCell.reuseId, for: indexPath) as! PlanCell
        let product = context.products[indexPath.row]
        cell.configure(product: product, accentColor: accentColor, isSelected: product.id == selectedProduct?.id)
        return cell
    }

    public func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: false)
        select(context.products[indexPath.row])
    }
}

// MARK: - PlanCell

private final class PlanCell: UITableViewCell {

    static let reuseId = "PlanCell"

    private var planButton: PlanButton?

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        backgroundColor = .clear
        selectionStyle = .none
    }

    required init?(coder: NSCoder) { fatalError() }

    func configure(product: AFPaywallProduct, accentColor: UIColor, isSelected: Bool) {
        planButton?.removeFromSuperview()

        let btn = PlanButton(product: product, accentColor: accentColor)
        btn.isUserInteractionEnabled = false
        contentView.addSubview(btn)

        NSLayoutConstraint.activate([
            btn.topAnchor.constraint(equalTo: contentView.topAnchor),
            btn.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 20),
            btn.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -20),
            btn.heightAnchor.constraint(equalToConstant: 72),
            btn.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -10),
        ])

        btn.setSelected(isSelected)
        planButton = btn
    }
}

// MARK: - PlanButton

private final class PlanButton: UIControl {

    // MARK: - Properties

    let product: AFPaywallProduct
    private let accentColor: UIColor
    private var isSelectedState = false

    // MARK: - UI

    private lazy var container: UIView = {
        let v = UIView()
        v.backgroundColor = .secondarySystemBackground
        v.layer.cornerRadius = 16
        v.layer.cornerCurve = .continuous
        v.layer.borderWidth = 2
        v.layer.borderColor = UIColor.clear.cgColor
        v.isUserInteractionEnabled = false
        v.translatesAutoresizingMaskIntoConstraints = false
        return v
    }()

    private lazy var nameLabel: UILabel = {
        let l = UILabel()
        l.font = .systemFont(ofSize: 16, weight: .semibold)
        l.textColor = .label
        return l
    }()

    private lazy var detailLabel: UILabel = {
        let l = UILabel()
        l.font = .systemFont(ofSize: 13)
        l.textColor = .secondaryLabel
        return l
    }()

    private lazy var priceLabel: UILabel = {
        let l = UILabel()
        l.font = .systemFont(ofSize: 15, weight: .medium)
        l.textColor = .secondaryLabel
        l.textAlignment = .right
        return l
    }()

    private lazy var checkmark: UIImageView = {
        let cfg = UIImage.SymbolConfiguration(pointSize: 20, weight: .medium)
        let iv = UIImageView(image: UIImage(systemName: "checkmark.circle.fill", withConfiguration: cfg))
        iv.tintColor = self.accentColor
        iv.alpha = 0
        iv.translatesAutoresizingMaskIntoConstraints = false
        return iv
    }()

    private lazy var popularBadge: PaddedLabel = {
        let l = PaddedLabel()
        l.text = "MOST POPULAR"
        l.font = .systemFont(ofSize: 10, weight: .bold)
        l.textColor = .white
        l.backgroundColor = self.accentColor
        l.layer.cornerRadius = 6
        l.layer.cornerCurve = .continuous
        l.layer.masksToBounds = true
        l.isHidden = !product.isPopular
        l.translatesAutoresizingMaskIntoConstraints = false
        return l
    }()

    // MARK: - Init

    init(product: AFPaywallProduct, accentColor: UIColor) {
        self.product = product
        self.accentColor = accentColor
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        setupUI()
        configure()
    }

    required init?(coder: NSCoder) { fatalError() }

    // MARK: - Setup

    private func setupUI() {
        addSubview(container)
        addSubview(popularBadge)

        let leftStack = UIStackView(arrangedSubviews: [nameLabel, detailLabel])
        leftStack.axis = .vertical
        leftStack.spacing = 3

        let row = UIStackView(arrangedSubviews: [leftStack, priceLabel, checkmark])
        row.axis = .horizontal
        row.alignment = .center
        row.spacing = 12
        row.translatesAutoresizingMaskIntoConstraints = false

        checkmark.setContentHuggingPriority(.required, for: .horizontal)
        checkmark.setContentCompressionResistancePriority(.required, for: .horizontal)
        priceLabel.setContentHuggingPriority(.required, for: .horizontal)
        priceLabel.setContentCompressionResistancePriority(.required, for: .horizontal)

        container.addSubview(row)

        NSLayoutConstraint.activate([
            container.topAnchor.constraint(equalTo: topAnchor, constant: 6),
            container.leadingAnchor.constraint(equalTo: leadingAnchor),
            container.trailingAnchor.constraint(equalTo: trailingAnchor),
            container.bottomAnchor.constraint(equalTo: bottomAnchor),

            row.topAnchor.constraint(equalTo: container.topAnchor, constant: 14),
            row.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 16),
            row.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -16),
            row.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -14),

            checkmark.widthAnchor.constraint(equalToConstant: 24),
            checkmark.heightAnchor.constraint(equalToConstant: 24),

            popularBadge.centerYAnchor.constraint(equalTo: container.topAnchor),
            popularBadge.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 16),
        ])
    }

    private func configure() {
        nameLabel.text = product.displayName

        if let offer = product.introductoryOffer {
            detailLabel.text = offer
            detailLabel.textColor = self.accentColor
        } else if let perMonth = product.pricePerMonth {
            detailLabel.text = perMonth
        } else {
            detailLabel.text = product.subscriptionPeriod.displayString
        }

        priceLabel.text = product.displayPrice
    }

    // MARK: - Selection

    func setSelected(_ selected: Bool) {
        isSelectedState = selected

        UIView.animate(withDuration: 0.2, delay: 0, options: .curveEaseInOut) {
            if selected {
                self.container.backgroundColor = self.accentColor.withAlphaComponent(0.07)
                self.container.layer.borderColor = self.accentColor.cgColor
                self.nameLabel.textColor = .label
                self.priceLabel.textColor = self.accentColor
                self.checkmark.alpha = 1
            } else {
                self.container.backgroundColor = .secondarySystemBackground
                self.container.layer.borderColor = UIColor.clear.cgColor
                self.nameLabel.textColor = .label
                self.priceLabel.textColor = .secondaryLabel
                self.checkmark.alpha = 0
            }
        }
    }

    // MARK: - Touch

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesBegan(touches, with: event)
        UIView.animate(withDuration: 0.1) {
            self.container.transform = CGAffineTransform(scaleX: 0.97, y: 0.97)
        }
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesEnded(touches, with: event)
        UIView.animate(withDuration: 0.12, delay: 0, usingSpringWithDamping: 0.7, initialSpringVelocity: 4) {
            self.container.transform = .identity
        }
        sendActions(for: .touchUpInside)
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesCancelled(touches, with: event)
        UIView.animate(withDuration: 0.1) { self.container.transform = .identity }
    }
}

// MARK: - PaddedLabel

private final class PaddedLabel: UILabel {
    var insets = UIEdgeInsets(top: 3, left: 8, bottom: 3, right: 8)

    override func drawText(in rect: CGRect) {
        super.drawText(in: rect.inset(by: insets))
    }

    override var intrinsicContentSize: CGSize {
        let s = super.intrinsicContentSize
        return CGSize(
            width:  s.width  + insets.left + insets.right,
            height: s.height + insets.top  + insets.bottom
        )
    }
}

// MARK: - AFSubscriptionPeriod Extension

private extension AFSubscriptionPeriod {
    var displayString: String {
        switch self {
        case .weekly:    return "Weekly"
        case .monthly:   return "Monthly"
        case .quarterly: return "Quarterly"
        case .yearly:    return "Yearly"
        case .lifetime:  return "Lifetime"
        case .unknown:   return ""
        }
    }
}

// 聊天工具栏：模型选择 / 思考开关 / 搜索开关，支持响应式换行与弹性动画
import UIKit

protocol ChatToolbarViewDelegate: AnyObject {
    func toolbarDidTapModelSelector(_ toolbar: ChatToolbarView)
    func toolbarDidTapThinking(_ toolbar: ChatToolbarView)
    func toolbarDidTapSearch(_ toolbar: ChatToolbarView)
}

final class ChatToolbarView: UIView {

    weak var delegate: ChatToolbarViewDelegate?

    private enum LayoutMode {
        case singleLine
        case wrapped
    }

    private let horizontalInset: CGFloat = 12
    private let verticalInset: CGFloat = 8
    private let itemSpacing: CGFloat = 8
    private let pillHeight: CGFloat = 28
    private var layoutMode: LayoutMode = .singleLine
    private var didLayoutOnce = false
    private var lastKnownWidth: CGFloat = 0

    // MARK: - Subviews
    let modelButton: UIButton = {
        let b = UIButton(type: .system)
        b.titleLabel?.font = UIFont.systemFont(ofSize: 13, weight: .medium)
        b.titleLabel?.lineBreakMode = .byTruncatingTail
        b.layer.cornerRadius = 12
        b.layer.borderWidth  = 1
        b.contentEdgeInsets  = UIEdgeInsets(top: 4, left: 10, bottom: 4, right: 10)
        b.translatesAutoresizingMaskIntoConstraints = false
        b.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return b
    }()

    let thinkingButton: UIButton = {
        let b = UIButton(type: .system)
        b.titleLabel?.font = UIFont.systemFont(ofSize: 12)
        b.titleLabel?.lineBreakMode = .byTruncatingTail
        b.layer.cornerRadius = 12
        b.layer.borderWidth  = 1
        b.contentEdgeInsets  = UIEdgeInsets(top: 4, left: 8, bottom: 4, right: 8)
        b.isHidden = true
        b.translatesAutoresizingMaskIntoConstraints = false
        b.setContentCompressionResistancePriority(.defaultHigh, for: .horizontal)
        return b
    }()

    let searchButton: UIButton = {
        let b = UIButton(type: .system)
        b.titleLabel?.font = UIFont.systemFont(ofSize: 12)
        b.titleLabel?.lineBreakMode = .byTruncatingTail
        b.layer.cornerRadius = 12
        b.layer.borderWidth  = 1
        b.contentEdgeInsets  = UIEdgeInsets(top: 4, left: 8, bottom: 4, right: 8)
        b.isHidden = true
        b.translatesAutoresizingMaskIntoConstraints = false
        b.setContentCompressionResistancePriority(.defaultHigh, for: .horizontal)
        return b
    }()

    private let topRow: UIStackView = {
        let sv = UIStackView()
        sv.axis = .horizontal
        sv.alignment = .center
        sv.spacing = 8
        sv.translatesAutoresizingMaskIntoConstraints = false
        return sv
    }()

    private let bottomRow: UIStackView = {
        let sv = UIStackView()
        sv.axis = .horizontal
        sv.alignment = .center
        sv.spacing = 8
        sv.translatesAutoresizingMaskIntoConstraints = false
        return sv
    }()

    private let rootStack: UIStackView = {
        let sv = UIStackView()
        sv.axis = .vertical
        sv.alignment = .fill
        sv.spacing = 8
        sv.translatesAutoresizingMaskIntoConstraints = false
        return sv
    }()

    private let topSpacer = UIView()
    private let bottomSpacer = UIView()

    // MARK: - Init
    override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
        applyTheme()
        NotificationCenter.default.addObserver(self,
            selector: #selector(themeChanged),
            name: ThemeManager.didChange, object: nil)
    }
    required init?(coder: NSCoder) { fatalError() }
    deinit { NotificationCenter.default.removeObserver(self) }

    override var intrinsicContentSize: CGSize {
        CGSize(width: UIView.noIntrinsicMetric, height: preferredHeight)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let width = bounds.width.rounded(.down)
        if abs(width - lastKnownWidth) > 0.5 {
            lastKnownWidth = width
            updateLayoutMode(animated: didLayoutOnce)
        }
        didLayoutOnce = true
    }

    private var preferredHeight: CGFloat {
        switch layoutMode {
        case .singleLine:
            return verticalInset * 2 + pillHeight
        case .wrapped:
            return verticalInset * 2 + pillHeight * 2 + itemSpacing
        }
    }

    private func setup() {
        layer.borderWidth = 0.5

        topSpacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        topSpacer.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        bottomSpacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        bottomSpacer.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        addSubview(rootStack)
        rootStack.addArrangedSubview(topRow)
        rootStack.addArrangedSubview(bottomRow)

        NSLayoutConstraint.activate([
            rootStack.topAnchor.constraint(equalTo: topAnchor, constant: verticalInset),
            rootStack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: horizontalInset),
            rootStack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -horizontalInset),
            rootStack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -verticalInset),

            modelButton.heightAnchor.constraint(equalToConstant: pillHeight),
            thinkingButton.heightAnchor.constraint(equalToConstant: pillHeight),
            searchButton.heightAnchor.constraint(equalToConstant: pillHeight)
        ])

        rebuildRows()

        modelButton.addTarget(self, action: #selector(tapModel),    for: .touchUpInside)
        thinkingButton.addTarget(self, action: #selector(tapThink), for: .touchUpInside)
        searchButton.addTarget(self, action: #selector(tapSearch),  for: .touchUpInside)
    }

    private func clearArrangedSubviews(in stackView: UIStackView) {
        for subview in stackView.arrangedSubviews {
            stackView.removeArrangedSubview(subview)
            subview.removeFromSuperview()
        }
    }

    private var hasThinkingVisible: Bool { !thinkingButton.isHidden }
    private var hasSearchVisible: Bool { !searchButton.isHidden }
    private var hasSecondaryControls: Bool { hasThinkingVisible || hasSearchVisible }

    private func rebuildRows() {
        clearArrangedSubviews(in: topRow)
        clearArrangedSubviews(in: bottomRow)

        switch layoutMode {
        case .singleLine:
            topRow.addArrangedSubview(modelButton)
            if hasThinkingVisible { topRow.addArrangedSubview(thinkingButton) }
            if hasSearchVisible {
                topRow.addArrangedSubview(topSpacer)
                topRow.addArrangedSubview(searchButton)
            }
            bottomRow.isHidden = true
            bottomRow.alpha = 0

        case .wrapped:
            topRow.addArrangedSubview(modelButton)
            topRow.addArrangedSubview(topSpacer)

            if hasSecondaryControls {
                if hasThinkingVisible { bottomRow.addArrangedSubview(thinkingButton) }
                if hasSearchVisible {
                    bottomRow.addArrangedSubview(searchButton)
                }
                bottomRow.addArrangedSubview(bottomSpacer)
                bottomRow.isHidden = false
                bottomRow.alpha = 1
            } else {
                bottomRow.isHidden = true
                bottomRow.alpha = 0
            }
        }
    }

    private func desiredLayoutMode(for width: CGFloat) -> LayoutMode {
        guard width > 0 else { return layoutMode }
        guard hasSecondaryControls else { return .singleLine }

        let contentWidth = max(0, width - horizontalInset * 2)
        let modelWidth = modelButton.intrinsicContentSize.width
        let thinkingWidth = hasThinkingVisible ? thinkingButton.intrinsicContentSize.width : 0
        let searchWidth = hasSearchVisible ? searchButton.intrinsicContentSize.width : 0

        let spacingCount: CGFloat
        switch (hasThinkingVisible, hasSearchVisible) {
        case (true, true):   spacingCount = 3   // model + think + spacer + search
        case (true, false):  spacingCount = 1   // model + think
        case (false, true):  spacingCount = 2   // model + spacer + search
        case (false, false): spacingCount = 0
        }

        let singleLineWidth = modelWidth + thinkingWidth + searchWidth + spacingCount * itemSpacing
        return singleLineWidth <= contentWidth ? .singleLine : .wrapped
    }

    private func updateLayoutMode(animated: Bool, forceRebuild: Bool = false) {
        let targetMode = desiredLayoutMode(for: bounds.width)
        if targetMode == layoutMode {
            if forceRebuild {
                rebuildRows()
            }
            invalidateIntrinsicContentSize()
            superview?.setNeedsLayout()
            return
        }

        layoutMode = targetMode
        rebuildRows()
        invalidateIntrinsicContentSize()
        setNeedsLayout()
        superview?.setNeedsLayout()

        let animations = {
            self.superview?.layoutIfNeeded()
            self.layoutIfNeeded()
        }

        if animated, window != nil {
            UIView.animate(withDuration: 0.42,
                           delay: 0,
                           usingSpringWithDamping: 0.82,
                           initialSpringVelocity: 0.25,
                           options: [.allowUserInteraction, .beginFromCurrentState]) {
                animations()
            }
        } else {
            animations()
        }
    }

    private func refreshLayout(animated: Bool = true) {
        if bounds.width > 0 {
            updateLayoutMode(animated: animated, forceRebuild: true)
        } else {
            setNeedsLayout()
            invalidateIntrinsicContentSize()
        }
    }

    // MARK: - Theme
    @objc private func themeChanged() { applyTheme() }

    func applyTheme() {
        backgroundColor = .agToolbarBackground
        layer.borderColor = UIColor.agSeparator.cgColor

        let modelColor = UIColor.themed(
            light: UIColor(red: 0.2, green: 0.2, blue: 0.6, alpha: 1),
            dark:  UIColor(red: 0.5, green: 0.6, blue: 0.95, alpha: 1))
        modelButton.setTitleColor(modelColor, for: .normal)
        modelButton.layer.borderColor = UIColor.themed(
            light: UIColor(red: 0.7, green: 0.75, blue: 0.95, alpha: 1),
            dark:  UIColor(red: 0.35, green: 0.42, blue: 0.72, alpha: 1)).cgColor
    }

    // MARK: - Public update methods
    func setModel(_ name: String) {
        modelButton.setTitle("⚙ \(name) ▾", for: .normal)
        refreshLayout()
    }

    func setThinkingVisible(_ visible: Bool) {
        thinkingButton.isHidden = !visible
        refreshLayout()
    }

    func setThinkingEnabled(_ enabled: Bool) {
        let color: UIColor = enabled
            ? UIColor.themed(light: UIColor(red: 0.2, green: 0.55, blue: 0.2, alpha: 1),
                             dark:  UIColor(red: 0.35, green: 0.80, blue: 0.40, alpha: 1))
            : UIColor.themed(light: .gray, dark: UIColor(white: 0.55, alpha: 1))
        thinkingButton.setTitleColor(color, for: .normal)
        thinkingButton.layer.borderColor = color.cgColor
        thinkingButton.setTitle(enabled ? "💭 思考 ON" : "💭 思考 OFF", for: .normal)
        refreshLayout()
    }

    func setSearchVisible(_ visible: Bool) {
        searchButton.isHidden = !visible
        refreshLayout()
    }

    func setSearchLabel(_ label: String) {
        let isOff = label == "关闭搜索"
        let color: UIColor = isOff
            ? UIColor.themed(light: .gray, dark: UIColor(white: 0.55, alpha: 1))
            : UIColor.themed(light: UIColor(red: 0.0, green: 0.48, blue: 0.8, alpha: 1),
                             dark:  UIColor(red: 0.2, green: 0.65, blue: 1.0, alpha: 1))
        searchButton.setTitleColor(color, for: .normal)
        searchButton.layer.borderColor = color.cgColor
        searchButton.setTitle("🔍 \(label)", for: .normal)
        refreshLayout()
    }

    // MARK: - Actions
    @objc private func tapModel()  { delegate?.toolbarDidTapModelSelector(self) }
    @objc private func tapThink()  { delegate?.toolbarDidTapThinking(self) }
    @objc private func tapSearch() { delegate?.toolbarDidTapSearch(self) }

    // MARK: - Thinking capability heuristic
    static func isThinkingCapable(_ model: String) -> Bool {
        let lower = model.lowercased()
        let patterns = ["-r1", "o1-", "o3-", "o4-", "think", "reason",
                        "qwq", "qvq", "gemini-2.0-flash-think", "deepseek-r"]
        return patterns.contains { lower.contains($0) }
    }
}

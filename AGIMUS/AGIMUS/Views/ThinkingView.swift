// 可折叠的思考内容展示组件，兼容流式实时更新，支持深色模式
import UIKit

final class ThinkingView: UIView {

    var onToggle: (() -> Void)?

    // MARK: - Subviews
    private let headerButton: UIButton = {
        let b = UIButton(type: .system)
        b.contentHorizontalAlignment = .left
        b.titleLabel?.font = UIFont.systemFont(ofSize: 13, weight: .medium)
        b.translatesAutoresizingMaskIntoConstraints = false
        return b
    }()

    private let chevron: UILabel = {
        let l = UILabel()
        l.font = UIFont.systemFont(ofSize: 11)
        l.text = "▶"
        l.translatesAutoresizingMaskIntoConstraints = false
        return l
    }()

    private let contentTextView: UITextView = {
        let tv = UITextView()
        tv.isEditable = false
        tv.isScrollEnabled = true
        tv.font = UIFont.monospacedBody(size: 12)
        tv.backgroundColor = .clear
        tv.textContainerInset = UIEdgeInsets(top: 4, left: 8, bottom: 8, right: 8)
        tv.translatesAutoresizingMaskIntoConstraints = false
        return tv
    }()

    private var contentHeightConstraint: NSLayoutConstraint!
    private var isExpanded = false
    private let collapsedHeight: CGFloat = 0
    private let expandedHeight: CGFloat  = 180

    // MARK: - Init
    override init(frame: CGRect) {
        super.init(frame: frame)
        layer.cornerRadius = 10
        layer.borderWidth  = 0.5
        translatesAutoresizingMaskIntoConstraints = false
        setup()
        applyTheme()
        NotificationCenter.default.addObserver(self,
            selector: #selector(themeChanged),
            name: ThemeManager.didChange, object: nil)
    }
    required init?(coder: NSCoder) { fatalError() }
    deinit { NotificationCenter.default.removeObserver(self) }

    private func setup() {
        addSubview(headerButton)
        addSubview(chevron)
        addSubview(contentTextView)

        contentHeightConstraint = contentTextView.heightAnchor.constraint(equalToConstant: collapsedHeight)

        NSLayoutConstraint.activate([
            headerButton.topAnchor.constraint(equalTo: topAnchor),
            headerButton.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            headerButton.trailingAnchor.constraint(equalTo: chevron.leadingAnchor, constant: -4),
            headerButton.heightAnchor.constraint(equalToConstant: 32),

            chevron.centerYAnchor.constraint(equalTo: headerButton.centerYAnchor),
            chevron.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
            chevron.widthAnchor.constraint(equalToConstant: 16),

            contentTextView.topAnchor.constraint(equalTo: headerButton.bottomAnchor),
            contentTextView.leadingAnchor.constraint(equalTo: leadingAnchor),
            contentTextView.trailingAnchor.constraint(equalTo: trailingAnchor),
            contentTextView.bottomAnchor.constraint(equalTo: bottomAnchor),
            contentHeightConstraint
        ])

        headerButton.addTarget(self, action: #selector(toggle), for: .touchUpInside)
    }

    // MARK: - Theme
    @objc private func themeChanged() { applyTheme() }

    func applyTheme() {
        backgroundColor = .agThinkingBackground
        layer.borderColor = UIColor.agThinkingBorder.cgColor
        headerButton.setTitleColor(.agThinkingHeader, for: .normal)
        chevron.textColor = .agThinkingHeader
        contentTextView.textColor = .agThinkingText
    }

    // MARK: - Public

    func configure(content: String, isStreaming: Bool, isExpanded: Bool) {
        contentTextView.text = content
        if isStreaming {
            headerButton.setTitle(L("💭  思考中…", "💭  Thinking…"), for: .normal)
        } else {
            headerButton.setTitle(L("💭  思考过程（\(content.count) 字）",
                                    "💭  Reasoning (\(content.count) chars)"),
                                  for: .normal)
        }
        setExpanded(isExpanded, animated: false)
    }

    func appendThinkingChunk(_ chunk: String) {
        contentTextView.text += chunk
        headerButton.setTitle(L("💭  思考中…(\(contentTextView.text.count) 字)",
                                "💭  Thinking… (\(contentTextView.text.count) chars)"),
                              for: .normal)
    }

    // MARK: - Expand / Collapse

    private func setExpanded(_ expanded: Bool, animated: Bool) {
        isExpanded = expanded
        contentHeightConstraint.constant = expanded ? expandedHeight : collapsedHeight
        contentTextView.isHidden = !expanded
        chevron.text = expanded ? "▼" : "▶"
        if animated {
            UIView.animate(withDuration: 0.2) { self.superview?.layoutIfNeeded() }
        }
    }

    @objc private func toggle() {
        setExpanded(!isExpanded, animated: true)
        onToggle?()
    }
}

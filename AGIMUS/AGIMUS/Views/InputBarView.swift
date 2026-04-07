// 底部输入栏：可伸缩 TextView + 发送 / 停止按钮，支持深色模式
import UIKit

protocol InputBarViewDelegate: AnyObject {
    func inputBarDidTapSend(_ bar: InputBarView, text: String)
    func inputBarDidTapStop(_ bar: InputBarView)
}

final class InputBarView: UIView {

    weak var delegate: InputBarViewDelegate?

    // MARK: - Subviews
    let textView: UITextView = {
        let tv = UITextView()
        tv.font = UIFont.systemFont(ofSize: 16)
        tv.layer.cornerRadius = 18
        tv.layer.borderWidth = 1
        tv.textContainerInset = UIEdgeInsets(top: 9, left: 10, bottom: 9, right: 10)
        tv.isScrollEnabled = false
        tv.translatesAutoresizingMaskIntoConstraints = false
        return tv
    }()

    private let placeholderLabel: UILabel = {
        let l = UILabel()
        l.text = "发消息…"
        l.font = UIFont.systemFont(ofSize: 16)
        l.textColor = UIColor.lightGray
        l.translatesAutoresizingMaskIntoConstraints = false
        l.isUserInteractionEnabled = false
        return l
    }()

    private let sendButton: UIButton = {
        let b = UIButton(type: .system)
        b.setTitle("↑", for: .normal)
        b.titleLabel?.font = UIFont.boldSystemFont(ofSize: 22)
        b.backgroundColor = UIColor.agBubbleUser
        b.setTitleColor(.white, for: .normal)
        b.layer.cornerRadius = 18
        b.translatesAutoresizingMaskIntoConstraints = false
        return b
    }()

    private let stopButton: UIButton = {
        let b = UIButton(type: .system)
        b.setTitle("■", for: .normal)
        b.titleLabel?.font = UIFont.boldSystemFont(ofSize: 18)
        b.backgroundColor = UIColor.agBubbleUser
        b.setTitleColor(.white, for: .normal)
        b.layer.cornerRadius = 18
        b.isHidden = true
        b.translatesAutoresizingMaskIntoConstraints = false
        return b
    }()

    private var textViewHeightConstraint: NSLayoutConstraint!
    private let minHeight: CGFloat = 36
    private let maxHeight: CGFloat = 120

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

    private func setup() {
        addSubview(textView)
        textView.addSubview(placeholderLabel)
        addSubview(sendButton)
        addSubview(stopButton)

        textViewHeightConstraint = textView.heightAnchor.constraint(equalToConstant: minHeight)

        NSLayoutConstraint.activate([
            textView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            textView.topAnchor.constraint(equalTo: topAnchor, constant: 8),
            textView.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -8),
            textViewHeightConstraint,

            sendButton.leadingAnchor.constraint(equalTo: textView.trailingAnchor, constant: 8),
            sendButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            sendButton.bottomAnchor.constraint(equalTo: textView.bottomAnchor),
            sendButton.widthAnchor.constraint(equalToConstant: 36),
            sendButton.heightAnchor.constraint(equalToConstant: 36),

            stopButton.leadingAnchor.constraint(equalTo: textView.trailingAnchor, constant: 8),
            stopButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            stopButton.bottomAnchor.constraint(equalTo: textView.bottomAnchor),
            stopButton.widthAnchor.constraint(equalToConstant: 36),
            stopButton.heightAnchor.constraint(equalToConstant: 36),

            placeholderLabel.leadingAnchor.constraint(equalTo: textView.leadingAnchor, constant: 14),
            placeholderLabel.topAnchor.constraint(equalTo: textView.topAnchor, constant: 9)
        ])

        textView.delegate = self
        sendButton.addTarget(self, action: #selector(didTapSend), for: .touchUpInside)
        stopButton.addTarget(self, action: #selector(didTapStop), for: .touchUpInside)
    }

    // MARK: - Theme
    @objc private func themeChanged() { applyTheme() }

    func applyTheme() {
        backgroundColor = .agInputBackground
        layer.borderWidth = 0.5
        layer.borderColor = UIColor.agSeparator.cgColor

        textView.backgroundColor = .agInputBackground
        textView.textColor = .agTextBot
        textView.layer.borderColor = UIColor.agSeparator.cgColor

        sendButton.backgroundColor = .agBubbleUser
        stopButton.backgroundColor = .agBubbleUser
    }

    // MARK: - Public
    func setGenerating(_ generating: Bool) {
        sendButton.isHidden = generating
        stopButton.isHidden = !generating
    }

    func clear() {
        textView.text = ""
        placeholderLabel.isHidden = false
        updateHeight()
    }

    // MARK: - Actions
    @objc private func didTapSend() {
        let text = textView.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        delegate?.inputBarDidTapSend(self, text: text)
    }

    @objc private func didTapStop() {
        delegate?.inputBarDidTapStop(self)
    }

    // MARK: - Height
    private func updateHeight() {
        let size = textView.sizeThatFits(CGSize(width: textView.bounds.width, height: .greatestFiniteMagnitude))
        let h = min(maxHeight, max(minHeight, size.height))
        if textViewHeightConstraint.constant != h {
            textViewHeightConstraint.constant = h
            textView.isScrollEnabled = size.height > maxHeight
            UIView.animate(withDuration: 0.15) { self.superview?.layoutIfNeeded() }
        }
    }
}

extension InputBarView: UITextViewDelegate {
    func textViewDidChange(_ textView: UITextView) {
        placeholderLabel.isHidden = !textView.text.isEmpty
        updateHeight()
    }
}

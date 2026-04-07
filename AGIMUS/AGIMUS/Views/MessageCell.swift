// 聊天室风格消息行：全宽、左对齐，直接 Auto Layout（不用 UIStackView 主布局）
import UIKit

protocol MessageCellDelegate: AnyObject {
    func messageCellDidTapRetry(_ cell: MessageCell)
    func messageCellDidTapCopy(_ cell: MessageCell, text: String)
    func messageCellDidToggleThinking(_ cell: MessageCell)
}

final class MessageCell: UITableViewCell {
    static let reuseID = "MessageCell"
    weak var delegate: MessageCellDelegate?

    // MARK: - 打字动画（三点循环）
    private var typingTimer: Timer?
    private var typingStep  = 0
    private let typingPhases = ["●", "● ●", "● ● ●", ""]

    // MARK: - Subviews

    private let senderLabel: UILabel = {
        let l = UILabel()
        l.font = UIFont.systemFont(ofSize: 11, weight: .semibold)
        l.translatesAutoresizingMaskIntoConstraints = false
        return l
    }()

    private let thinkingView = ThinkingView()

    /// 使用 UILabel + 直接 Auto Layout 约束，避免 UIStackView 宽度传递问题导致的空白
    private let contentLabel: UILabel = {
        let l = UILabel()
        l.numberOfLines = 0
        l.translatesAutoresizingMaskIntoConstraints = false
        return l
    }()

    private let metadataLabel: UILabel = {
        let l = UILabel()
        l.font = UIFont.systemFont(ofSize: 10)
        l.textColor = UIColor(white: 0.55, alpha: 1)
        l.numberOfLines = 1
        l.translatesAutoresizingMaskIntoConstraints = false
        return l
    }()

    private let retryButton: UIButton = {
        let b = UIButton(type: .system)
        b.setTitle("重试", for: .normal)
        b.setTitleColor(UIColor(red: 0.75, green: 0.15, blue: 0.15, alpha: 1), for: .normal)
        b.titleLabel?.font = UIFont.systemFont(ofSize: 12)
        b.contentHorizontalAlignment = .left
        b.translatesAutoresizingMaskIntoConstraints = false
        return b
    }()

    private let copyButton: UIButton = {
        let b = UIButton(type: .system)
        b.setTitle("复制", for: .normal)
        b.setTitleColor(UIColor(white: 0.5, alpha: 1), for: .normal)
        b.titleLabel?.font = UIFont.systemFont(ofSize: 12)
        b.contentHorizontalAlignment = .left
        b.translatesAutoresizingMaskIntoConstraints = false
        return b
    }()

    /// 操作按钮横排（水平 UIStackView，不参与主垂直布局）
    private let actionRow: UIStackView = {
        let sv = UIStackView()
        sv.axis = .horizontal
        sv.spacing = 16
        sv.alignment = .center
        sv.translatesAutoresizingMaskIntoConstraints = false
        return sv
    }()

    /// 元数据 + 操作行合并到底部垂直 UIStackView，利用其自动折叠隐藏视图的特性
    private let bottomStack: UIStackView = {
        let sv = UIStackView()
        sv.axis = .vertical
        sv.spacing = 2
        sv.alignment = .fill
        sv.translatesAutoresizingMaskIntoConstraints = false
        return sv
    }()

    // MARK: - 动态约束（思考视图显隐切换 contentLabel 顶部锚点）
    private var contentTopNoThinking: NSLayoutConstraint!
    private var contentTopWithThinking: NSLayoutConstraint!

    // MARK: - Init
    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        setup()
    }
    required init?(coder: NSCoder) { fatalError() }

    private func setup() {
        selectionStyle = .none
        backgroundColor = .clear

        // Action row 内容
        actionRow.addArrangedSubview(retryButton)
        actionRow.addArrangedSubview(copyButton)
        let spacer = UIView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        actionRow.addArrangedSubview(spacer)

        // Bottom stack = metadataLabel + actionRow
        bottomStack.addArrangedSubview(metadataLabel)
        bottomStack.addArrangedSubview(actionRow)

        // 添加到 contentView
        contentView.addSubview(senderLabel)
        contentView.addSubview(thinkingView)
        contentView.addSubview(contentLabel)
        contentView.addSubview(bottomStack)

        let pad: CGFloat = 14

        // contentLabel 的两条互斥顶部约束
        contentTopNoThinking   = contentLabel.topAnchor.constraint(equalTo: senderLabel.bottomAnchor, constant: 6)
        contentTopWithThinking = contentLabel.topAnchor.constraint(equalTo: thinkingView.bottomAnchor, constant: 8)

        NSLayoutConstraint.activate([
            // ── 发送方标签 ─────────────────────────────────────────────
            senderLabel.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 10),
            senderLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: pad),
            senderLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -pad),

            // ── 思考视图（紧跟 senderLabel，显隐由 configure 控制）────
            thinkingView.topAnchor.constraint(equalTo: senderLabel.bottomAnchor, constant: 6),
            thinkingView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: pad),
            thinkingView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -pad),

            // ── 正文（明确的 leading/trailing，确保 UILabel 知道自身宽度）
            contentTopNoThinking,   // 初始激活；thinking 可见时换成 contentTopWithThinking
            contentLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: pad),
            contentLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -pad),

            // ── 底部堆栈（元数据 + 操作按钮），底部锚定 contentView ──
            bottomStack.topAnchor.constraint(equalTo: contentLabel.bottomAnchor, constant: 4),
            bottomStack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: pad),
            bottomStack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -pad),
            bottomStack.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -10),
        ])

        thinkingView.onToggle = { [weak self] in
            guard let self = self else { return }
            self.delegate?.messageCellDidToggleThinking(self)
        }
        retryButton.addTarget(self, action: #selector(didTapRetry), for: .touchUpInside)
        copyButton.addTarget(self, action: #selector(didTapCopy), for: .touchUpInside)
    }

    // MARK: - Configure

    func configure(with message: ChatMessage,
                   isGenerating: Bool = false,
                   isThinkingExpanded: Bool = false) {
        stopTypingAnimation()   // cell 复用时先停动画，按需重启
        let isUser = message.role == .user

        // ── 背景色（支持深色模式）──────────────────────────────────
        contentView.backgroundColor = isUser ? .agCellUser : .agCellBot

        // ── 发送方标签 ───────────────────────────────────────────────
        if isUser {
            senderLabel.text      = "You"
            senderLabel.textColor = UIColor.themed(
                light: UIColor(red: 0.20, green: 0.40, blue: 0.80, alpha: 1),
                dark:  UIColor(red: 0.45, green: 0.65, blue: 1.00, alpha: 1))
        } else {
            senderLabel.text      = message.modelName ?? "AI"
            senderLabel.textColor = UIColor.themed(
                light: UIColor(red: 0.20, green: 0.50, blue: 0.30, alpha: 1),
                dark:  UIColor(red: 0.40, green: 0.78, blue: 0.50, alpha: 1))
        }

        // ── 思考视图 ────────────────────────────────────────────────
        let hasThinking = !isUser && message.thinkingContent != nil
        thinkingView.isHidden = !hasThinking
        if hasThinking {
            thinkingView.configure(content: message.thinkingContent ?? "",
                                   isStreaming: isGenerating,
                                   isExpanded: isThinkingExpanded)
        }

        // 切换 contentLabel 顶部约束
        contentTopNoThinking.isActive   = !hasThinking
        contentTopWithThinking.isActive = hasThinking

        // ── 消息正文 ────────────────────────────────────────────────
        if isUser {
            contentLabel.attributedText = nil
            contentLabel.text           = message.content
            contentLabel.font           = UIFont.systemFont(ofSize: 15)
            contentLabel.textColor      = message.isError
                ? UIColor.themed(light: UIColor(red: 0.55, green: 0.10, blue: 0.10, alpha: 1),
                                 dark:  UIColor(red: 0.85, green: 0.35, blue: 0.35, alpha: 1))
                : .agTextBot
        } else {
            // 内容为空 + 生成中 → 显示打字动画（流式第一包到来前 / 非流式等待中通用）
            if message.content.isEmpty && isGenerating {
                if let thinking = message.thinkingContent, !thinking.isEmpty {
                    // 推理模型：thinking 已到但 content 还未到，渲染思考内容 + 光标
                    contentLabel.text           = nil
                    contentLabel.attributedText = MarkdownRenderer.shared.render(thinking + "▌")
                } else {
                    // 纯等待状态：三点打字动画
                    contentLabel.attributedText = nil
                    contentLabel.font      = UIFont.systemFont(ofSize: 18, weight: .medium)
                    contentLabel.textColor = UIColor.themed(
                        light: UIColor(white: 0.62, alpha: 1),
                        dark:  UIColor(white: 0.48, alpha: 1))
                    contentLabel.text = typingPhases[0]
                    startTypingAnimation()
                }
            } else {
                // 有内容（或生成已结束）
                let cursor = isGenerating ? "▌" : ""
                let body   = message.content + cursor
                if body.isEmpty {
                    // 生成已结束但内容为空：兜底回退
                    if let thinking = message.thinkingContent, !thinking.isEmpty {
                        contentLabel.text           = nil
                        contentLabel.attributedText = MarkdownRenderer.shared.render(thinking)
                    } else {
                        contentLabel.attributedText = nil
                        contentLabel.text           = "（回复为空，请检查 API 配置或模型设置）"
                        contentLabel.font           = UIFont.italicSystemFont(ofSize: 13)
                        contentLabel.textColor      = UIColor.themed(light: UIColor(white:0.55,alpha:1),
                                                                     dark:  UIColor(white:0.45,alpha:1))
                    }
                } else {
                    contentLabel.text           = nil
                    contentLabel.attributedText = MarkdownRenderer.shared.render(body)
                }
            }
        }

        // ── 元数据 ──────────────────────────────────────────────────
        if !isUser {
            let meta = message.metadataLine
            metadataLabel.text    = meta
            metadataLabel.isHidden = meta.isEmpty
        } else {
            metadataLabel.text    = nil
            metadataLabel.isHidden = true
        }

        // ── 操作按钮 ────────────────────────────────────────────────
        retryButton.isHidden = !message.isError
        copyButton.isHidden  = isUser || isGenerating
        actionRow.isHidden   = retryButton.isHidden && copyButton.isHidden
    }

    // MARK: - 打字动画
    private func startTypingAnimation() {
        typingStep = 0
        updateTypingDots()
        typingTimer?.invalidate()
        typingTimer = Timer.scheduledTimer(withTimeInterval: 0.45, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            self.typingStep = (self.typingStep + 1) % self.typingPhases.count
            self.updateTypingDots()
        }
    }

    private func updateTypingDots() {
        contentLabel.attributedText = nil
        contentLabel.text = typingPhases[typingStep]
    }

    private func stopTypingAnimation() {
        typingTimer?.invalidate()
        typingTimer = nil
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        stopTypingAnimation()
    }

    // MARK: - Actions
    @objc private func didTapRetry() { delegate?.messageCellDidTapRetry(self) }
    @objc private func didTapCopy()  {
        let text = contentLabel.attributedText?.string ?? contentLabel.text ?? ""
        delegate?.messageCellDidTapCopy(self, text: text)
    }
}

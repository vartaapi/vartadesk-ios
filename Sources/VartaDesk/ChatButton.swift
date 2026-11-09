import UIKit

/**
 * The round chat button in the corner of any screen of the business's app
 * (DK25b), like the launcher on its website: the business's colour, a red
 * count of replies not read yet, and a tap opens the chat's Home.
 *
 * While it is on screen it listens for replies (for someone who has chatted
 * before), so the count moves by itself; off screen, it listens to nothing.
 */
final class ChatButton: UIView, DeskListener {
    static let tag = 0x7d25
    private let client: DeskClient
    private let circle = UIButton(type: .custom)
    private let badge = PaddedLabel()

    init(client: DeskClient) {
        self.client = client
        super.init(frame: .zero)
        tag = Self.tag
        circle.backgroundColor = Ink.brand
        circle.layer.cornerRadius = 29
        circle.layer.shadowColor = UIColor.black.cgColor
        circle.layer.shadowOpacity = 0.28
        circle.layer.shadowRadius = 10
        circle.layer.shadowOffset = CGSize(width: 0, height: 5)
        circle.setImage(UIImage(systemName: "bubble.left.fill", withConfiguration: UIImage.SymbolConfiguration(pointSize: 23, weight: .medium)), for: .normal)
        circle.tintColor = .white
        circle.accessibilityLabel = "Chat with us"
        circle.addAction(UIAction { [weak self] _ in
            VartaDesk.open(from: self?.owner())
        }, for: .touchUpInside)
        badge.inset = UIEdgeInsets(top: 0, left: 5, bottom: 0, right: 5)
        badge.font = .boldSystemFont(ofSize: 11)
        badge.textColor = .white
        badge.textAlignment = .center
        badge.backgroundColor = Ink.red
        badge.layer.cornerRadius = 10
        badge.layer.borderWidth = 1.5
        badge.layer.borderColor = UIColor.white.cgColor
        badge.clipsToBounds = true
        badge.isHidden = true
        badge.isUserInteractionEnabled = false
        addSubview(circle)
        addSubview(badge)
        for v in [circle, badge] as [UIView] { v.translatesAutoresizingMaskIntoConstraints = false }
        NSLayoutConstraint.activate([
            circle.topAnchor.constraint(equalTo: topAnchor),
            circle.bottomAnchor.constraint(equalTo: bottomAnchor),
            circle.leadingAnchor.constraint(equalTo: leadingAnchor),
            circle.trailingAnchor.constraint(equalTo: trailingAnchor),
            circle.widthAnchor.constraint(equalToConstant: 58),
            circle.heightAnchor.constraint(equalToConstant: 58),
            badge.topAnchor.constraint(equalTo: circle.topAnchor, constant: -4),
            badge.trailingAnchor.constraint(equalTo: circle.trailingAnchor, constant: 4),
            badge.heightAnchor.constraint(equalToConstant: 20),
            badge.widthAnchor.constraint(greaterThanOrEqualToConstant: 20),
        ])
        // Hidden until the business's colour has loaded, so it never flashes green.
        alpha = 0
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("Use VartaDesk.showChatButton(in:)") }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window == nil {
            client.removeListener(self)
            return
        }
        client.addListener(self)
        // The look, and (for someone who has chatted before) their unread replies.
        client.open(quiet: true, fresh: 30)
        deskChanged()
    }

    func deskChanged() {
        guard let look = client.look else { return }
        circle.backgroundColor = look.color
        circle.accessibilityLabel = "Chat with \(look.name)"
        let n = client.unread
        badge.text = n > 9 ? "9+" : "\(n)"
        badge.isHidden = n == 0
        circle.accessibilityValue = n > 0 ? "\(n) unread" : nil
        if alpha == 0 { UIView.animate(withDuration: 0.2) { self.alpha = 1 } }
    }

    func deskError(_ message: String) {}

    /** The screen it sits on, to show the chat over. */
    private func owner() -> UIViewController? {
        var r: UIResponder? = self
        while let next = r?.next {
            if let vc = next as? UIViewController { return vc }
            r = next
        }
        return nil
    }
}

/** The app's own unread listener: called when the number changes. */
final class UnreadHook: DeskListener {
    private let client: DeskClient
    private let listener: (Int) -> Void
    private var last = -1

    init(client: DeskClient, listener: @escaping (Int) -> Void) {
        self.client = client
        self.listener = listener
    }

    func deskChanged() {
        let n = client.unread
        guard n != last else { return }
        last = n
        listener(n)
    }

    func deskError(_ message: String) {}
}

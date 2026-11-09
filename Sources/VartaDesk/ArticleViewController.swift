import UIKit

/**
 * One help article (DK25b): its title, folder and text, the three faces to
 * say whether it helped, and a way on to the chat. Pictures inside articles
 * are left out for now; the text and links show.
 */
final class ArticleViewController: UIViewController {
    private let client: DeskClient
    private let slug: String
    private let body = UIStackView()
    private var reaction: String?
    private var faces: [UIButton] = []

    init(client: DeskClient, slug: String) {
        self.client = client
        self.slug = slug
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("Opened from Home") }

    override func viewDidLoad() {
        super.viewDidLoad()
        overrideUserInterfaceStyle = .light
        view.backgroundColor = .white
        title = "Help"
        plainBar(navigationItem)
        let scroll = UIScrollView()
        body.axis = .vertical
        body.spacing = 6
        body.isLayoutMarginsRelativeArrangement = true
        body.directionalLayoutMargins = NSDirectionalEdgeInsets(top: 18, leading: 20, bottom: 28, trailing: 20)
        body.addArrangedSubview(makeLabel("Loading…", size: 14, color: Ink.muted))
        scroll.addSubview(body)
        view.addSubview(scroll)
        for v in [scroll, body] as [UIView] { v.translatesAutoresizingMaskIntoConstraints = false }
        NSLayoutConstraint.activate([
            scroll.topAnchor.constraint(equalTo: view.topAnchor),
            scroll.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            scroll.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            body.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor),
            body.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor),
            body.leadingAnchor.constraint(equalTo: scroll.frameLayoutGuide.leadingAnchor),
            body.trailingAnchor.constraint(equalTo: scroll.frameLayoutGuide.trailingAnchor),
        ])
        client.article(slug) { [weak self] a, err in
            guard let self else { return }
            if let a { self.show(a) } else { self.showError(err) }
        }
    }

    private func showError(_ err: String?) {
        body.arrangedSubviews.forEach { $0.removeFromSuperview() }
        body.addArrangedSubview(makeLabel(err ?? "This article isn't available.", size: 14, color: Ink.muted))
    }

    private func show(_ a: [String: Any]) {
        body.arrangedSubviews.forEach { $0.removeFromSuperview() }
        body.addArrangedSubview(makeLabel(a["title"] as? String ?? "", size: 23, bold: true))
        if let folder = a["folder"] as? String, !folder.isEmpty {
            body.addArrangedSubview(makeLabel(folder, size: 12.5, color: Ink.faint))
        }
        let text = UITextView()
        text.isEditable = false
        text.isScrollEnabled = false
        text.backgroundColor = .clear
        text.textContainerInset = UIEdgeInsets(top: 10, left: 0, bottom: 0, right: 0)
        text.textContainer.lineFragmentPadding = 0
        text.attributedText = Self.html(a["html"] as? String ?? "")
        text.linkTextAttributes = [.foregroundColor: client.look?.color ?? Ink.brand, .underlineStyle: NSUnderlineStyle.single.rawValue]
        body.addArrangedSubview(text)

        // Did it help?
        let line = UIView()
        line.backgroundColor = Ink.line
        line.heightAnchor.constraint(equalToConstant: 1).isActive = true
        body.setCustomSpacing(22, after: text)
        body.addArrangedSubview(line)
        body.setCustomSpacing(16, after: line)
        let ask = makeLabel("Did this answer your question?", size: 13.5, color: Ink.muted)
        ask.textAlignment = .center
        body.addArrangedSubview(ask)
        let row = UIStackView()
        row.spacing = 10
        for (key, face, name) in [("sad", "😞", "No"), ("neutral", "😐", "A little"), ("happy", "😃", "Yes")] {
            let b = UIButton(type: .custom)
            b.setTitle(face, for: .normal)
            b.titleLabel?.font = .systemFont(ofSize: 24)
            b.layer.cornerRadius = 20
            b.layer.borderWidth = 1
            b.layer.borderColor = Ink.border.cgColor
            b.accessibilityLabel = name
            b.widthAnchor.constraint(equalToConstant: 58).isActive = true
            b.heightAnchor.constraint(equalToConstant: 44).isActive = true
            b.addAction(UIAction { [weak self, weak b] _ in
                guard let self, let b else { return }
                self.client.react(self.slug, key, previous: self.reaction)
                self.reaction = key
                self.faces.forEach { $0.alpha = $0 === b ? 1 : 0.45 }
            }, for: .touchUpInside)
            faces.append(b)
            row.addArrangedSubview(b)
        }
        let center = UIStackView(arrangedSubviews: [row])
        center.axis = .vertical
        center.alignment = .center
        body.addArrangedSubview(center)
        body.setCustomSpacing(22, after: center)

        var c = UIButton.Configuration.filled()
        c.title = "Still need help? Send us a message"
        c.baseBackgroundColor = client.look?.color ?? Ink.brand
        c.baseForegroundColor = .white
        c.cornerStyle = .medium
        c.contentInsets = NSDirectionalEdgeInsets(top: 14, leading: 14, bottom: 14, trailing: 14)
        c.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { var t = $0; t.font = .boldSystemFont(ofSize: 15); return t }
        let chat = UIButton(configuration: c, primaryAction: UIAction { [weak self] _ in
            guard let self else { return }
            self.navigationController?.pushViewController(ChatViewController(client: self.client), animated: true)
        })
        body.addArrangedSubview(chat)
    }

    /** The article's HTML as styled text, in the system font. Pictures are taken out: they would show as empty boxes. */
    static func html(_ raw: String) -> NSAttributedString {
        let clean = raw.replacingOccurrences(of: "<img[^>]*>", with: "", options: [.regularExpression, .caseInsensitive])
        let page = "<style>body{font-family:-apple-system;font-size:16px;line-height:1.45;color:#33333D}h1,h2,h3{color:#1E1E24}h1{font-size:22px}h2{font-size:19px}h3{font-size:17px}</style>" + clean
        guard let data = page.data(using: .utf8),
              let s = try? NSMutableAttributedString(data: data, options: [.documentType: NSAttributedString.DocumentType.html, .characterEncoding: String.Encoding.utf8.rawValue], documentAttributes: nil)
        else { return NSAttributedString(string: clean) }
        // HTML leaves a blank line at the end.
        while s.string.hasSuffix("\n") { s.deleteCharacters(in: NSRange(location: s.length - 1, length: 1)) }
        return s
    }
}

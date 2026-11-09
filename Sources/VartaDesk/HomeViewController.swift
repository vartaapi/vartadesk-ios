import UIKit

/**
 * Home (DK25b), what VartaDesk.open() shows first, as on the website chat:
 * the business's greeting in its colour, the conversation (start it or carry
 * on), the help centre with a search, and the person's tickets.
 */
final class HomeViewController: UIViewController, DeskListener, UITextFieldDelegate {
    private let client: DeskClient
    private let scroll = UIScrollView()
    private let page = UIStackView()
    private var help: [DeskArticleItem]?
    private var results: [DeskArticleItem]?
    private var query = ""
    private var searchTimer: Timer?
    private var search: UITextField?
    private let articles = UIStackView()

    init(client: DeskClient) {
        self.client = client
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("Use VartaDesk.open()") }

    override func viewDidLoad() {
        super.viewDidLoad()
        overrideUserInterfaceStyle = .light
        view.backgroundColor = Ink.page
        // The greeting's colour runs up behind the status bar, and when pulled down.
        scroll.contentInsetAdjustmentBehavior = .never
        scroll.alwaysBounceVertical = true
        scroll.keyboardDismissMode = .onDrag
        page.axis = .vertical
        page.spacing = 12
        scroll.addSubview(page)
        view.addSubview(scroll)
        for v in [scroll, page] as [UIView] { v.translatesAutoresizingMaskIntoConstraints = false }
        NSLayoutConstraint.activate([
            scroll.topAnchor.constraint(equalTo: view.topAnchor),
            scroll.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scroll.bottomAnchor.constraint(equalTo: view.keyboardLayoutGuide.topAnchor),
            page.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor),
            page.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor, constant: -16),
            page.leadingAnchor.constraint(equalTo: scroll.frameLayoutGuide.leadingAnchor),
            page.trailingAnchor.constraint(equalTo: scroll.frameLayoutGuide.trailingAnchor),
        ])
        articles.axis = .vertical
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        navigationController?.setNavigationBarHidden(true, animated: animated)
        client.addListener(self)
        client.open()
        draw()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        navigationController?.setNavigationBarHidden(false, animated: animated)
        client.removeListener(self)
    }

    override var preferredStatusBarStyle: UIStatusBarStyle { .lightContent }

    func deskChanged() {
        // Not while they type in the search: redrawing would take the box away from under them.
        if search?.isFirstResponder == true { return drawResults() }
        draw()
    }

    func deskError(_ message: String) {
        Toast.show(message, in: view)
    }

    // MARK: Drawing

    private func draw() {
        let look = client.look
        page.arrangedSubviews.forEach { $0.removeFromSuperview() }
        let color = look?.color ?? Ink.brand

        // The greeting, on the business's colour.
        let hero = UIView()
        hero.backgroundColor = color
        let initial = makeLabel(String((look?.name ?? "").trimmingCharacters(in: .whitespaces).prefix(1)).uppercased(), size: 17, color: .white, bold: true)
        initial.textAlignment = .center
        initial.backgroundColor = UIColor(white: 1, alpha: 0.19)
        initial.layer.cornerRadius = 9
        initial.clipsToBounds = true
        let close = UIButton(type: .system)
        close.setImage(UIImage(systemName: "xmark", withConfiguration: UIImage.SymbolConfiguration(pointSize: 17, weight: .semibold)), for: .normal)
        close.tintColor = .white
        close.accessibilityLabel = "Close"
        close.addAction(UIAction { [weak self] _ in self?.dismiss(animated: true) }, for: .touchUpInside)
        let greeting = makeLabel(look?.greeting ?? "", size: 27, color: UIColor(white: 1, alpha: 0.72), bold: true)
        let intro = makeLabel(look?.intro ?? "", size: 21, color: .white, bold: true)
        for v in [initial, close, greeting, intro] as [UIView] {
            v.translatesAutoresizingMaskIntoConstraints = false
            hero.addSubview(v)
        }
        NSLayoutConstraint.activate([
            // Clear of the status bar when full screen; just below the sheet's edge when it slides up.
            initial.topAnchor.constraint(equalTo: hero.safeAreaLayoutGuide.topAnchor, constant: 18),
            initial.leadingAnchor.constraint(equalTo: hero.leadingAnchor, constant: 20),
            initial.widthAnchor.constraint(equalToConstant: 36),
            initial.heightAnchor.constraint(equalToConstant: 36),
            close.centerYAnchor.constraint(equalTo: initial.centerYAnchor),
            close.trailingAnchor.constraint(equalTo: hero.trailingAnchor, constant: -10),
            close.widthAnchor.constraint(equalToConstant: 44),
            close.heightAnchor.constraint(equalToConstant: 44),
            greeting.topAnchor.constraint(equalTo: initial.bottomAnchor, constant: 26),
            greeting.leadingAnchor.constraint(equalTo: hero.leadingAnchor, constant: 20),
            greeting.trailingAnchor.constraint(equalTo: hero.trailingAnchor, constant: -20),
            intro.topAnchor.constraint(equalTo: greeting.bottomAnchor, constant: 4),
            intro.leadingAnchor.constraint(equalTo: greeting.leadingAnchor),
            intro.trailingAnchor.constraint(equalTo: greeting.trailingAnchor),
            intro.bottomAnchor.constraint(equalTo: hero.bottomAnchor, constant: -66),
        ])
        page.addArrangedSubview(hero)
        // The cards ride up over the bottom of the greeting.
        page.setCustomSpacing(-50, after: hero)

        guard let look else {
            let c = card()
            c.addArrangedSubview(makeLabel("Loading…", size: 14, color: Ink.muted))
            page.addArrangedSubview(inset(c))
            return
        }

        // The conversation.
        if client.started, let last = client.messages.last {
            let c = card()
            c.addArrangedSubview(caption("Your conversation"))
            let avatar = makeLabel(String(look.name.trimmingCharacters(in: .whitespaces).prefix(1)).uppercased(), size: 14, color: .white, bold: true)
            avatar.textAlignment = .center
            avatar.backgroundColor = color
            avatar.layer.cornerRadius = 18
            avatar.clipsToBounds = true
            avatar.widthAnchor.constraint(equalToConstant: 36).isActive = true
            avatar.heightAnchor.constraint(equalToConstant: 36).isActive = true
            let unread = client.unread
            let preview = (last.fromMe ? "You: " : "") + (last.body ?? last.mediaFilename.map { "📎 \($0)" } ?? "📎 A file")
            let words = UIStackView(arrangedSubviews: [
                makeLabel(look.name, size: 15, bold: true, lines: 1),
                makeLabel(preview, size: 13, color: unread > 0 ? Ink.text : Ink.muted, bold: unread > 0, lines: 1),
            ])
            words.axis = .vertical
            words.spacing = 2
            let side = UIStackView(arrangedSubviews: [makeLabel(shortTime(last.createdAt), size: 12, color: Ink.faint, lines: 1)])
            side.axis = .vertical
            side.alignment = .trailing
            side.spacing = 4
            if unread > 0 {
                let badge = makeLabel("\(unread)", size: 11, color: .white, bold: true)
                badge.textAlignment = .center
                badge.backgroundColor = Ink.red
                badge.layer.cornerRadius = 10
                badge.clipsToBounds = true
                badge.widthAnchor.constraint(equalToConstant: 20).isActive = true
                badge.heightAnchor.constraint(equalToConstant: 20).isActive = true
                side.addArrangedSubview(badge)
            }
            side.setContentHuggingPriority(.required, for: .horizontal)
            side.setContentCompressionResistancePriority(.required, for: .horizontal)
            let r = UIStackView(arrangedSubviews: [avatar, words, side])
            r.spacing = 12
            r.alignment = .center
            r.isLayoutMarginsRelativeArrangement = true
            r.directionalLayoutMargins = NSDirectionalEdgeInsets(top: 10, leading: 0, bottom: 2, trailing: 0)
            tappable(r, label: "Your conversation with \(look.name)") { [weak self] in self?.openChat() }
            c.addArrangedSubview(r)
            page.addArrangedSubview(inset(c))
        }
        let send = card()
        let status: String
        if look.open { status = "We usually reply \(look.reply)" }
        else if let back = look.backAt { status = "We're away. Back \(back)" }
        else { status = "We're away right now" }
        send.addArrangedSubview(row(client.started ? "Continue the conversation" : "Send us a message", status, color, dot: look.open ? Ink.green : Ink.amber) { [weak self] in self?.openChat() })
        page.addArrangedSubview(inset(send))

        // Help: a search, and the first articles.
        if look.helpArticles > 0 {
            let c = card()
            let box = UITextField()
            box.placeholder = "Search for help"
            box.attributedPlaceholder = NSAttributedString(string: "Search for help", attributes: [.foregroundColor: Ink.text, .font: UIFont.boldSystemFont(ofSize: 15)])
            box.font = .systemFont(ofSize: 15)
            box.textColor = Ink.text
            box.backgroundColor = Ink.field
            box.layer.cornerRadius = 10
            box.returnKeyType = .search
            box.clearButtonMode = .whileEditing
            box.autocorrectionType = .no
            box.autocapitalizationType = .none
            box.text = query
            box.delegate = self
            let glass = UIImageView(image: UIImage(systemName: "magnifyingglass"))
            glass.tintColor = color
            glass.contentMode = .center
            glass.frame = CGRect(x: 0, y: 0, width: 38, height: 20)
            box.rightView = glass
            box.rightViewMode = .unlessEditing
            box.leftView = UIView(frame: CGRect(x: 0, y: 0, width: 14, height: 10))
            box.leftViewMode = .always
            box.heightAnchor.constraint(equalToConstant: 44).isActive = true
            box.addTarget(self, action: #selector(searchChanged), for: .editingChanged)
            box.accessibilityLabel = "Search for help"
            search = box
            c.addArrangedSubview(box)
            c.addArrangedSubview(articles)
            page.addArrangedSubview(inset(c))
            if help == nil { client.loadHelp { [weak self] in self?.help = $0; self?.drawResults() } }
            drawResults()
        } else {
            search = nil
        }

        // Tickets: raise one, and follow the ones raised.
        if look.ticketForm {
            let c = card()
            c.addArrangedSubview(caption("Tickets"))
            for t in client.tickets.prefix(5) {
                let words = UIStackView(arrangedSubviews: [
                    makeLabel(t.subject, size: 14.5, bold: true, lines: 1),
                    makeLabel(t.name, size: 12, color: Ink.faint, lines: 1),
                ])
                words.axis = .vertical
                words.spacing = 2
                let done = t.status == "resolved"
                let pill = PaddedLabel()
                pill.inset = UIEdgeInsets(top: 3, left: 7, bottom: 3, right: 7)
                pill.attributedText = NSAttributedString(string: t.statusWords.uppercased(), attributes: [.kern: 0.6, .font: UIFont.boldSystemFont(ofSize: 10)])
                pill.textColor = done ? Ink.done : color
                pill.backgroundColor = done ? Ink.doneWash : Ink.openWash
                pill.layer.cornerRadius = 4
                pill.clipsToBounds = true
                pill.setContentHuggingPriority(.required, for: .horizontal)
                pill.setContentCompressionResistancePriority(.required, for: .horizontal)
                let r = UIStackView(arrangedSubviews: [words, pill])
                r.alignment = .center
                r.spacing = 10
                r.isLayoutMarginsRelativeArrangement = true
                r.directionalLayoutMargins = NSDirectionalEdgeInsets(top: 10, leading: 0, bottom: 4, trailing: 0)
                tappable(r, label: "\(t.subject), \(t.statusWords)") { [weak self] in self?.showTicket(t) }
                c.addArrangedSubview(r)
            }
            let raise = row("Raise a ticket", "Tell us about a problem and follow it here", color) { [weak self] in
                guard let self else { return }
                self.navigationController?.pushViewController(TicketViewController(client: self.client), animated: true)
            }
            c.addArrangedSubview(raise)
            page.addArrangedSubview(inset(c))
        }

        // "We run on VartaAPI Desk" on the free plan.
        if look.branding {
            let b = UILabel()
            let s = NSMutableAttributedString(string: "We run on ", attributes: [.foregroundColor: Ink.faint, .font: UIFont.systemFont(ofSize: 11.5)])
            s.append(NSAttributedString(string: "VartaAPI Desk", attributes: [.foregroundColor: Ink.orange, .font: UIFont.boldSystemFont(ofSize: 11.5)]))
            b.attributedText = s
            b.textAlignment = .center
            tappable(b, label: "We run on VartaAPI Desk") {
                if let u = URL(string: "https://www.vartaapi.com/?ref=desk-ios") { UIApplication.shared.open(u) }
            }
            page.addArrangedSubview(b)
        }
    }

    // MARK: Search

    @objc private func searchChanged() {
        searchSoon(search?.text ?? "", final: false)
    }

    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        searchSoon(textField.text ?? "", final: true)
        textField.resignFirstResponder()
        return true
    }

    private func searchSoon(_ q: String, final: Bool) {
        query = q
        searchTimer?.invalidate()
        let trimmed = q.trimmingCharacters(in: .whitespaces)
        guard trimmed.count >= 2 else {
            results = nil
            return drawResults()
        }
        let go = { [weak self] in
            self?.client.searchHelp(trimmed, final: final) { found in
                guard let self, self.query == q else { return }
                self.results = found
                self.drawResults()
            }
        }
        // Typing: wait for a pause. Search pressed: at once, and a miss is reported to the business.
        if final { go() } else { searchTimer = Timer.scheduledTimer(withTimeInterval: 0.35, repeats: false) { _ in go() } }
    }

    private func drawResults() {
        articles.arrangedSubviews.forEach { $0.removeFromSuperview() }
        guard let shown = results ?? help.map({ Array($0.prefix(4)) }) else { return }
        if results != nil && shown.isEmpty {
            let none = makeLabel("No articles match. Send us a message instead.", size: 13.5, color: Ink.muted)
            let wrap = UIStackView(arrangedSubviews: [none])
            wrap.isLayoutMarginsRelativeArrangement = true
            wrap.directionalLayoutMargins = NSDirectionalEdgeInsets(top: 12, leading: 0, bottom: 4, trailing: 0)
            articles.addArrangedSubview(wrap)
            return
        }
        for a in shown {
            let r = row(a.title, nil, client.look?.color ?? Ink.text, bold: false) { [weak self] in
                guard let self else { return }
                self.navigationController?.pushViewController(ArticleViewController(client: self.client, slug: a.slug), animated: true)
            }
            articles.addArrangedSubview(r)
        }
    }

    // MARK: Pieces

    private func card() -> UIStackView {
        let c = UIStackView()
        c.axis = .vertical
        c.isLayoutMarginsRelativeArrangement = true
        c.directionalLayoutMargins = NSDirectionalEdgeInsets(top: 14, leading: 16, bottom: 14, trailing: 16)
        c.backgroundColor = .white
        c.layer.cornerRadius = 12
        c.layer.shadowColor = UIColor.black.cgColor
        c.layer.shadowOpacity = 0.08
        c.layer.shadowRadius = 8
        c.layer.shadowOffset = CGSize(width: 0, height: 2)
        return c
    }

    /** A card, 14 points in from the screen's sides. */
    private func inset(_ c: UIView) -> UIView {
        let wrap = UIView()
        wrap.addSubview(c)
        c.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            c.topAnchor.constraint(equalTo: wrap.topAnchor),
            c.bottomAnchor.constraint(equalTo: wrap.bottomAnchor),
            c.leadingAnchor.constraint(equalTo: wrap.safeAreaLayoutGuide.leadingAnchor, constant: 14),
            c.trailingAnchor.constraint(equalTo: wrap.safeAreaLayoutGuide.trailingAnchor, constant: -14),
        ])
        return wrap
    }

    private func caption(_ s: String) -> UILabel {
        let l = UILabel()
        l.attributedText = NSAttributedString(string: s.uppercased(), attributes: [.kern: 1.0, .font: UIFont.monospacedSystemFont(ofSize: 10.5, weight: .semibold), .foregroundColor: Ink.faint])
        return l
    }

    /** A line to tap: a title, an optional line under it, and an arrow in the business's colour. */
    private func row(_ title: String, _ sub: String?, _ color: UIColor, bold: Bool = true, dot: UIColor? = nil, _ action: @escaping () -> Void) -> UIView {
        let words = UIStackView(arrangedSubviews: [makeLabel(title, size: bold ? 14.5 : 14.5, bold: bold)])
        words.axis = .vertical
        words.spacing = 2
        if let sub {
            let s = makeLabel(sub, size: 13, color: Ink.muted)
            if let dot {
                let d = UIView()
                d.backgroundColor = dot
                d.layer.cornerRadius = 4
                d.widthAnchor.constraint(equalToConstant: 8).isActive = true
                d.heightAnchor.constraint(equalToConstant: 8).isActive = true
                let line = UIStackView(arrangedSubviews: [d, s])
                line.spacing = 6
                line.alignment = .center
                words.addArrangedSubview(line)
            } else {
                words.addArrangedSubview(s)
            }
        }
        let arrow = UIImageView(image: UIImage(systemName: "chevron.right", withConfiguration: UIImage.SymbolConfiguration(pointSize: 14, weight: .semibold)))
        arrow.tintColor = color
        arrow.setContentHuggingPriority(.required, for: .horizontal)
        let r = UIStackView(arrangedSubviews: [words, arrow])
        r.alignment = .center
        r.spacing = 10
        r.isLayoutMarginsRelativeArrangement = true
        r.directionalLayoutMargins = NSDirectionalEdgeInsets(top: 10, leading: 0, bottom: 10, trailing: 0)
        tappable(r, label: title, action)
        return r
    }

    private func tappable(_ v: UIView, label: String, _ action: @escaping () -> Void) {
        v.isUserInteractionEnabled = true
        v.addGestureRecognizer(Tap(action))
        v.isAccessibilityElement = true
        v.accessibilityLabel = label
        v.accessibilityTraits = .button
    }

    private func showTicket(_ t: DeskTicket) {
        var words = "\(t.name) · \(t.statusWords)"
        if let d = t.details, !d.isEmpty { words += "\n\n\(d)" }
        words += "\n\nWe email you when it's resolved. To add something, send us a message."
        let a = UIAlertController(title: t.subject, message: words, preferredStyle: .alert)
        a.addAction(UIAlertAction(title: "Close", style: .cancel))
        a.addAction(UIAlertAction(title: "Send a message", style: .default) { [weak self] _ in self?.openChat() })
        present(a, animated: true)
    }

    private func openChat() {
        navigationController?.pushViewController(ChatViewController(client: client), animated: true)
    }
}

import UIKit

/**
 * Raise a ticket (DK25b), the same short form as the website chat: what it's
 * about, what happened, and an email to follow it by, asked only when the
 * chat doesn't have one yet.
 */
final class TicketViewController: UIViewController {
    private let client: DeskClient
    private let subject = UITextField()
    private let details = UITextView()
    private var mail: UITextField?
    private let error = makeLabel("", size: 13, color: Ink.error)
    private var send: UIButton!

    init(client: DeskClient) {
        self.client = client
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("Opened from Home") }

    override func viewDidLoad() {
        super.viewDidLoad()
        overrideUserInterfaceStyle = .light
        view.backgroundColor = .white
        title = "Raise a ticket"
        plainBar(navigationItem)

        let form = UIStackView()
        form.axis = .vertical
        form.spacing = 6
        form.isLayoutMarginsRelativeArrangement = true
        form.directionalLayoutMargins = NSDirectionalEdgeInsets(top: 10, leading: 18, bottom: 24, trailing: 18)

        func heading(_ s: String) {
            let l = makeLabel(s, size: 13, color: Ink.body, bold: true)
            if let last = form.arrangedSubviews.last { form.setCustomSpacing(16, after: last) }
            form.addArrangedSubview(l)
        }
        func style(_ v: UIView) {
            v.layer.cornerRadius = 8
            v.layer.borderWidth = 1
            v.layer.borderColor = Ink.border.cgColor
            v.backgroundColor = .white
        }
        func field(_ f: UITextField, hint: String) {
            f.attributedPlaceholder = NSAttributedString(string: hint, attributes: [.foregroundColor: Ink.faint])
            f.font = .systemFont(ofSize: 15)
            f.textColor = Ink.text
            f.leftView = UIView(frame: CGRect(x: 0, y: 0, width: 12, height: 10))
            f.leftViewMode = .always
            f.heightAnchor.constraint(equalToConstant: 44).isActive = true
            style(f)
        }

        heading("What is it about?")
        field(subject, hint: "For example: my order hasn't arrived")
        subject.autocapitalizationType = .sentences
        subject.accessibilityLabel = "What is it about?"
        form.addArrangedSubview(subject)

        heading("What happened?")
        details.font = .systemFont(ofSize: 15)
        details.textColor = Ink.text
        details.textContainerInset = UIEdgeInsets(top: 10, left: 8, bottom: 10, right: 8)
        details.accessibilityLabel = "What happened?"
        style(details)
        details.heightAnchor.constraint(equalToConstant: 110).isActive = true
        form.addArrangedSubview(details)
        let hint = makeLabel("Order number, dates, anything that helps", size: 12, color: Ink.faint)
        form.addArrangedSubview(hint)

        if client.email == nil {
            heading("Your email")
            let m = UITextField()
            field(m, hint: "So we can tell you how it's going")
            m.keyboardType = .emailAddress
            m.textContentType = .emailAddress
            m.autocapitalizationType = .none
            m.autocorrectionType = .no
            m.accessibilityLabel = "Your email"
            form.addArrangedSubview(m)
            mail = m
        }

        form.setCustomSpacing(12, after: form.arrangedSubviews.last!)
        form.addArrangedSubview(error)
        var c = UIButton.Configuration.filled()
        c.title = "Send"
        c.baseBackgroundColor = client.look?.color ?? Ink.brand
        c.baseForegroundColor = .white
        c.cornerStyle = .medium
        c.contentInsets = NSDirectionalEdgeInsets(top: 13, leading: 14, bottom: 13, trailing: 14)
        c.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { var t = $0; t.font = .boldSystemFont(ofSize: 15); return t }
        send = UIButton(configuration: c, primaryAction: UIAction { [weak self] _ in self?.submit() })
        form.setCustomSpacing(8, after: error)
        form.addArrangedSubview(send)

        let scroll = UIScrollView()
        scroll.keyboardDismissMode = .interactive
        scroll.addSubview(form)
        view.addSubview(scroll)
        for v in [scroll, form] as [UIView] { v.translatesAutoresizingMaskIntoConstraints = false }
        NSLayoutConstraint.activate([
            scroll.topAnchor.constraint(equalTo: view.topAnchor),
            scroll.bottomAnchor.constraint(equalTo: view.keyboardLayoutGuide.topAnchor),
            scroll.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            form.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor),
            form.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor),
            form.leadingAnchor.constraint(equalTo: scroll.frameLayoutGuide.leadingAnchor),
            form.trailingAnchor.constraint(equalTo: scroll.frameLayoutGuide.trailingAnchor),
        ])
    }

    private func submit() {
        let subj = (subject.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if subj.count < 3 {
            error.text = "Say in a few words what it's about."
            return
        }
        if let mail, (mail.text ?? "").trimmingCharacters(in: .whitespaces).range(of: "^[^@\\s]+@[^@\\s]+\\.[^@\\s]+$", options: .regularExpression) == nil {
            error.text = "Add your email so we can tell you how it's going."
            return
        }
        error.text = ""
        send.isEnabled = false
        view.endEditing(true)
        client.raiseTicket(subject: subj, details: details.text ?? "", mail: mail?.text) { [weak self] err in
            guard let self else { return }
            self.send.isEnabled = true
            if let err { return self.error.text = err }
            let home = self.navigationController?.viewControllers.first
            self.navigationController?.popViewController(animated: true)
            if let v = home?.view { Toast.show("Ticket raised. We'll keep you posted here and by email.", in: v) }
        }
    }
}

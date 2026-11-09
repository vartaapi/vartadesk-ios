import PhotosUI
import SafariServices
import UIKit
import UniformTypeIdentifiers

/**
 * The chat screen (DK25a): the business's name and reply time at the top,
 * the conversation, and a box to write in. Drawn in code with UIKit, so the
 * kit brings nothing else into the business's app, and styled like the
 * website chat: the business's colour for the person's own messages, light
 * grey for the team's. Always light, like the website chat.
 *
 * Photos and files (DK25c): the 📎 offers the camera, the photo library and
 * the Files app. None of them needs a permission from the person except the
 * camera, which needs the app's own camera line (NSCameraUsageDescription).
 */
final class ChatViewController: UIViewController, DeskListener, UITextViewDelegate, UIScrollViewDelegate {
    private let client: DeskClient
    private let scroll = UIScrollView()
    private let list = UIStackView()
    private let input = UITextView()
    private let placeholder = UILabel()
    private let send = UIButton(type: .system)
    private let attach = UIButton(type: .system)
    private let titleLabel = UILabel()
    private let subtitle = UILabel()
    private let avatar = UILabel()
    private let spinner = UIActivityIndicatorView(style: .medium)
    private var inputHeight: NSLayoutConstraint!
    private var shown = 0
    /** The newest message is in sight: keep it there as pictures load and messages change. */
    private var stick = true

    init(client: DeskClient) {
        self.client = client
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("Use VartaDesk.openChat()") }

    override func viewDidLoad() {
        super.viewDidLoad()
        overrideUserInterfaceStyle = .light
        navigationController?.overrideUserInterfaceStyle = .light
        view.backgroundColor = .white
        build()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        client.chatVisible = true
        client.addListener(self)
        client.open(fresh: 10)
        deskChanged()
        NotificationCenter.default.addObserver(self, selector: #selector(becameActive), name: UIApplication.didBecomeActiveNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(keyboardShown), name: UIResponder.keyboardDidShowNotification, object: nil)
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        client.markSeen()
        DeskNotify.clear(client: client)
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        client.chatVisible = false
        client.removeListener(self)
        NotificationCenter.default.removeObserver(self, name: UIApplication.didBecomeActiveNotification, object: nil)
        NotificationCenter.default.removeObserver(self, name: UIResponder.keyboardDidShowNotification, object: nil)
    }

    @objc private func becameActive() {
        client.markSeen()
    }

    // The keyboard took the bottom of the screen: keep the newest messages in sight.
    @objc private func keyboardShown() {
        scrollToBottom(animated: true)
    }

    // MARK: Updates from the client

    func deskChanged() {
        let look = client.look
        if client.loading && look == nil { spinner.startAnimating() } else { spinner.stopAnimating() }
        if let look {
            titleLabel.text = look.name
            avatar.text = String(look.name.trimmingCharacters(in: .whitespaces).prefix(1)).uppercased()
            avatar.backgroundColor = look.color
            send.backgroundColor = look.color
            if let typing = client.teamTyping { subtitle.text = "\(typing) is typing…" }
            else if look.open { subtitle.text = "Usually replies \(look.reply)" }
            else if let back = look.backAt { subtitle.text = "Back \(back)" }
            else { subtitle.text = "Away right now" }
        }
        drawMessages()
        if client.unread > 0, view.window != nil, UIApplication.shared.applicationState == .active { client.markSeen() }
    }

    func deskError(_ message: String) {
        toast(message)
    }

    // MARK: Drawing

    private func build() {
        // Header: the business's initial, its name and reply time; Done closes.
        avatar.textAlignment = .center
        avatar.textColor = .white
        avatar.font = .boldSystemFont(ofSize: 15)
        avatar.backgroundColor = UIColor(red: 0, green: 0x4C / 255, blue: 0x3D / 255, alpha: 1)
        avatar.layer.cornerRadius = 17
        avatar.clipsToBounds = true
        avatar.widthAnchor.constraint(equalToConstant: 34).isActive = true
        avatar.heightAnchor.constraint(equalToConstant: 34).isActive = true
        titleLabel.font = .boldSystemFont(ofSize: 16)
        titleLabel.textColor = Ink.text
        titleLabel.text = "Chat"
        subtitle.font = .systemFont(ofSize: 12.5)
        subtitle.textColor = Ink.muted
        let names = UIStackView(arrangedSubviews: [titleLabel, subtitle])
        names.axis = .vertical
        let head = UIStackView(arrangedSubviews: [avatar, names])
        head.spacing = 10
        head.alignment = .center
        navigationItem.titleView = head
        if navigationController?.viewControllers.first === self {
            navigationItem.leftBarButtonItem = UIBarButtonItem(barButtonSystemItem: .close, target: self, action: #selector(close))
        }
        let bar = UINavigationBarAppearance()
        bar.configureWithOpaqueBackground()
        bar.backgroundColor = .white
        bar.shadowColor = Ink.line
        navigationItem.standardAppearance = bar
        navigationItem.scrollEdgeAppearance = bar

        // The conversation.
        scroll.alwaysBounceVertical = true
        scroll.delegate = self
        scroll.keyboardDismissMode = .interactive
        list.axis = .vertical
        list.spacing = 5
        list.isLayoutMarginsRelativeArrangement = true
        list.directionalLayoutMargins = NSDirectionalEdgeInsets(top: 14, leading: 14, bottom: 14, trailing: 14)
        scroll.addSubview(list)
        view.addSubview(scroll)
        spinner.hidesWhenStopped = true
        view.addSubview(spinner)

        // The box to write in.
        let composer = UIView()
        composer.backgroundColor = .white
        let line = UIView()
        line.backgroundColor = Ink.line
        input.font = .systemFont(ofSize: 16)
        input.textColor = Ink.text
        input.backgroundColor = Ink.field
        input.layer.cornerRadius = 19
        input.textContainerInset = UIEdgeInsets(top: 9, left: 10, bottom: 9, right: 10)
        input.isScrollEnabled = false
        input.delegate = self
        input.accessibilityLabel = "Write a message"
        placeholder.text = "Write a message…"
        placeholder.font = .systemFont(ofSize: 16)
        placeholder.textColor = Ink.faint
        input.addSubview(placeholder)
        send.setImage(UIImage(systemName: "arrow.up", withConfiguration: UIImage.SymbolConfiguration(pointSize: 16, weight: .bold)), for: .normal)
        send.tintColor = .white
        send.backgroundColor = UIColor(red: 0, green: 0x4C / 255, blue: 0x3D / 255, alpha: 1)
        send.layer.cornerRadius = 19
        send.accessibilityLabel = "Send"
        send.addTarget(self, action: #selector(submit), for: .touchUpInside)
        attach.setImage(UIImage(systemName: "paperclip", withConfiguration: UIImage.SymbolConfiguration(pointSize: 19, weight: .regular)), for: .normal)
        attach.tintColor = Ink.muted
        attach.accessibilityLabel = "Send a photo or a file"
        attach.showsMenuAsPrimaryAction = true
        attach.menu = UIMenu(children: [
            UIAction(title: "Take a photo", image: UIImage(systemName: "camera")) { [weak self] _ in self?.takePhoto() },
            UIAction(title: "Choose a photo", image: UIImage(systemName: "photo.on.rectangle")) { [weak self] _ in self?.choosePhoto() },
            UIAction(title: "Choose a file", image: UIImage(systemName: "doc")) { [weak self] _ in self?.chooseFile() },
        ])
        [line, attach, input, send].forEach { composer.addSubview($0) }
        view.addSubview(composer)

        for v in [scroll, list, spinner, composer, line, attach, input, placeholder, send] as [UIView] {
            v.translatesAutoresizingMaskIntoConstraints = false
        }
        inputHeight = input.heightAnchor.constraint(equalToConstant: 38)
        NSLayoutConstraint.activate([
            scroll.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            scroll.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scroll.bottomAnchor.constraint(equalTo: composer.topAnchor),
            list.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor),
            list.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor),
            list.leadingAnchor.constraint(equalTo: scroll.frameLayoutGuide.leadingAnchor),
            list.trailingAnchor.constraint(equalTo: scroll.frameLayoutGuide.trailingAnchor),
            spinner.centerXAnchor.constraint(equalTo: scroll.centerXAnchor),
            spinner.centerYAnchor.constraint(equalTo: scroll.centerYAnchor),

            composer.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            composer.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            // Rides on top of the keyboard, and clear of the home bar when it is down.
            composer.bottomAnchor.constraint(equalTo: view.keyboardLayoutGuide.topAnchor),
            line.topAnchor.constraint(equalTo: composer.topAnchor),
            line.leadingAnchor.constraint(equalTo: composer.leadingAnchor),
            line.trailingAnchor.constraint(equalTo: composer.trailingAnchor),
            line.heightAnchor.constraint(equalToConstant: 1 / UIScreen.main.scale),
            input.topAnchor.constraint(equalTo: composer.topAnchor, constant: 8),
            input.bottomAnchor.constraint(equalTo: composer.bottomAnchor, constant: -8),
            attach.leadingAnchor.constraint(equalTo: composer.safeAreaLayoutGuide.leadingAnchor, constant: 6),
            attach.bottomAnchor.constraint(equalTo: input.bottomAnchor),
            attach.widthAnchor.constraint(equalToConstant: 38),
            attach.heightAnchor.constraint(equalToConstant: 38),
            input.leadingAnchor.constraint(equalTo: attach.trailingAnchor, constant: 4),
            input.trailingAnchor.constraint(equalTo: send.leadingAnchor, constant: -8),
            inputHeight,
            send.trailingAnchor.constraint(equalTo: composer.safeAreaLayoutGuide.trailingAnchor, constant: -10),
            send.bottomAnchor.constraint(equalTo: input.bottomAnchor),
            send.widthAnchor.constraint(equalToConstant: 38),
            send.heightAnchor.constraint(equalToConstant: 38),
            placeholder.leadingAnchor.constraint(equalTo: input.leadingAnchor, constant: 15),
            placeholder.centerYAnchor.constraint(equalTo: input.topAnchor, constant: 19),
        ])
    }

    @objc private func close() {
        dismiss(animated: true)
    }

    // The write box grows to five lines, then scrolls.
    func textViewDidChange(_ textView: UITextView) {
        placeholder.isHidden = !textView.text.isEmpty
        let fit = textView.sizeThatFits(CGSize(width: textView.bounds.width, height: .greatestFiniteMagnitude)).height
        let maxH = (textView.font?.lineHeight ?? 19) * 5 + 18
        inputHeight.constant = min(max(38, fit), maxH)
        textView.isScrollEnabled = fit > maxH
        if !textView.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { client.typing() }
    }

    @objc private func submit() {
        let text = input.text ?? ""
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        if client.closed { return toast("This chat is closed.") }
        input.text = ""
        textViewDidChange(input)
        client.send(text)
    }

    private func drawMessages() {
        let look = client.look
        let msgs = client.messages
        list.arrangedSubviews.forEach { $0.removeFromSuperview() }
        if msgs.isEmpty {
            shown = 0
            guard let look, !client.loading else { return }
            let empty = label("Ask \(look.name) anything. We'll reply here.", size: 14, color: Ink.muted)
            empty.textAlignment = .center
            empty.numberOfLines = 0
            let pad = UIView()
            pad.heightAnchor.constraint(equalToConstant: 120).isActive = true
            list.addArrangedSubview(pad)
            list.addArrangedSubview(empty)
            return
        }
        var lastMine: Bool?
        for m in msgs {
            if lastMine != m.fromMe {
                let who = label(m.fromMe ? "You" : (look?.name ?? ""), size: 11.5, color: Ink.faint)
                who.textAlignment = m.fromMe ? .right : .left
                if let prev = list.arrangedSubviews.last { list.setCustomSpacing(11, after: prev) }
                list.addArrangedSubview(who)
                list.setCustomSpacing(3, after: who)
            }
            lastMine = m.fromMe
            list.addArrangedSubview(bubble(m, look: look))
            if let failed = m.failed {
                let f = label(failed, size: 12, color: Ink.error)
                f.textAlignment = .right
                list.addArrangedSubview(f)
            }
        }
        if client.closed {
            let c = label("This chat is closed.", size: 12.5, color: Ink.faint)
            c.textAlignment = .center
            list.addArrangedSubview(c)
        }
        // New messages: go to the bottom.
        if msgs.count != shown || stick { scrollToBottom(animated: shown > 0 && msgs.count != shown) }
        shown = msgs.count
    }

    private func scrollToBottom(animated: Bool) {
        stick = true
        view.layoutIfNeeded()
        let bottom = max(-scroll.adjustedContentInset.top, scroll.contentSize.height - scroll.bounds.height + scroll.adjustedContentInset.bottom)
        scroll.setContentOffset(CGPoint(x: 0, y: bottom), animated: animated)
    }

    /** One message: a rounded bubble on the person's side or the team's. */
    private func bubble(_ m: DeskMessage, look: DeskLook?) -> UIView {
        let isImage = m.type == "image" || (m.mediaMime?.hasPrefix("image/") ?? false)
        // A picture shows as itself, with any words under it in a bubble of their own.
        if isImage, let url = m.mediaUrl, !m.pending {
            let pic = picture(m, url: url)
            guard let body = m.body, !body.isEmpty else { return pic }
            var words = m
            words.mediaUrl = nil
            words.mediaFilename = nil
            words.type = "text"
            let both = UIStackView(arrangedSubviews: [pic, bubble(words, look: look)])
            both.axis = .vertical
            both.spacing = 5
            return both
        }
        let words: String
        if m.pending && isImage { words = "📷 Sending the photo…" }
        else if m.pending, let f = m.mediaFilename { words = "📎 Sending \(f)…" }
        else if isImage && m.mediaUrl != nil { words = "📷 " + (m.mediaFilename ?? "Photo") + (m.body.map { "\n\($0)" } ?? "") }
        else if let f = m.mediaFilename, m.type != "text" { words = "📎 \(f)" + (m.body.map { "\n\($0)" } ?? "") }
        else { words = m.body ?? "📎 A file" }

        let text = UILabel()
        text.numberOfLines = 0
        text.font = .systemFont(ofSize: 15.5)
        if m.mediaUrl != nil {
            text.attributedText = NSAttributedString(string: words, attributes: [.underlineStyle: NSUnderlineStyle.single.rawValue])
        } else {
            text.text = words
        }
        text.textColor = m.fromMe ? .white : Ink.text
        let box = UIView()
        box.backgroundColor = m.fromMe ? (look?.color ?? .darkGray) : Ink.bubble
        box.layer.cornerRadius = 16
        box.alpha = m.pending ? 0.6 : 1
        box.addSubview(text)
        text.translatesAutoresizingMaskIntoConstraints = false
        box.translatesAutoresizingMaskIntoConstraints = false
        let row = UIView()
        row.addSubview(box)
        NSLayoutConstraint.activate([
            text.topAnchor.constraint(equalTo: box.topAnchor, constant: 9),
            text.bottomAnchor.constraint(equalTo: box.bottomAnchor, constant: -9),
            text.leadingAnchor.constraint(equalTo: box.leadingAnchor, constant: 12),
            text.trailingAnchor.constraint(equalTo: box.trailingAnchor, constant: -12),
            box.topAnchor.constraint(equalTo: row.topAnchor),
            box.bottomAnchor.constraint(equalTo: row.bottomAnchor),
            box.widthAnchor.constraint(lessThanOrEqualTo: row.widthAnchor, multiplier: 0.78),
            m.fromMe ? box.trailingAnchor.constraint(equalTo: row.trailingAnchor) : box.leadingAnchor.constraint(equalTo: row.leadingAnchor),
        ])
        if let url = m.mediaUrl.flatMap(URL.init(string:)) {
            box.isUserInteractionEnabled = true
            box.accessibilityTraits = .link
            box.addGestureRecognizer(Tap { [weak self] in self?.openFile(url) })
        } else {
            // Hold a message to copy it.
            box.isUserInteractionEnabled = true
            box.addInteraction(UIContextMenuInteraction(delegate: Copier.shared))
            box.accessibilityValue = m.body
        }
        return row
    }

    /** A picture in the chat: loaded once, rounded, opened full size on a tap. */
    private func picture(_ m: DeskMessage, url: String) -> UIView {
        let img = UIImageView()
        img.contentMode = .scaleAspectFill
        img.clipsToBounds = true
        img.layer.cornerRadius = 14
        img.backgroundColor = Ink.bubble
        img.isAccessibilityElement = true
        img.accessibilityLabel = m.mediaFilename ?? "Picture"
        img.accessibilityTraits = .image
        img.translatesAutoresizingMaskIntoConstraints = false
        let row = UIView()
        row.addSubview(img)
        let width = img.widthAnchor.constraint(equalToConstant: 200)
        let height = img.heightAnchor.constraint(equalToConstant: 150)
        NSLayoutConstraint.activate([
            img.topAnchor.constraint(equalTo: row.topAnchor),
            img.bottomAnchor.constraint(equalTo: row.bottomAnchor),
            m.fromMe ? img.trailingAnchor.constraint(equalTo: row.trailingAnchor) : img.leadingAnchor.constraint(equalTo: row.leadingAnchor),
            width, height,
        ])
        // Its own shape, at most 240 wide and 320 tall.
        let fit = { (i: UIImage) in
            let s = min(240 / max(i.size.width, 1), 320 / max(i.size.height, 1))
            width.constant = max(90, i.size.width * s)
            height.constant = max(70, i.size.height * s)
            img.image = i
        }
        client.image(url) { [weak self, weak img] i in
            guard let i else {
                // The link ran out or the file is gone: say so rather than leave an empty box.
                let gone = makeLabel("📷 Picture not available", size: 13, color: Ink.muted)
                gone.translatesAutoresizingMaskIntoConstraints = false
                img?.addSubview(gone)
                if let img { NSLayoutConstraint.activate([gone.centerXAnchor.constraint(equalTo: img.centerXAnchor), gone.centerYAnchor.constraint(equalTo: img.centerYAnchor)]) }
                height.constant = 70
                return
            }
            fit(i)
            if self?.stick == true { self?.scrollToBottom(animated: false) }
        }
        img.isUserInteractionEnabled = true
        img.addGestureRecognizer(Tap { [weak self, weak img] in
            guard let self, let shown = img?.image else { return }
            self.present(PictureViewController(image: shown, link: URL(string: url)), animated: true)
        })
        return row
    }

    /** The person scrolled: stuck to the bottom only if they left it there. */
    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        guard scrollView.isTracking || scrollView.isDecelerating else { return }
        stick = scrollView.contentOffset.y >= scrollView.contentSize.height - scrollView.bounds.height + scrollView.adjustedContentInset.bottom - 40
    }

    /** A document: shown inside the app, with Share and Done. */
    private func openFile(_ url: URL) {
        guard url.scheme == "https" || url.scheme == "http" else { return }
        present(SFSafariViewController(url: url), animated: true)
    }

    // MARK: Photos and files (DK25c)

    private func takePhoto() {
        if client.closed { return toast("This chat is closed.") }
        // Without its own camera line the app would be stopped by iOS: say so instead.
        guard Bundle.main.object(forInfoDictionaryKey: "NSCameraUsageDescription") != nil else {
            return toast("The camera isn't set up in this app. Choose a photo instead.")
        }
        guard UIImagePickerController.isSourceTypeAvailable(.camera) else {
            return toast("There's no camera on this device. Choose a photo instead.")
        }
        let p = UIImagePickerController()
        p.sourceType = .camera
        p.delegate = self
        present(p, animated: true)
    }

    private func choosePhoto() {
        if client.closed { return toast("This chat is closed.") }
        // Apple's own photo picker: the app sees only the photo chosen, so no permission is asked.
        var c = PHPickerConfiguration()
        c.filter = .images
        c.selectionLimit = 1
        let p = PHPickerViewController(configuration: c)
        p.delegate = self
        present(p, animated: true)
    }

    private func chooseFile() {
        if client.closed { return toast("This chat is closed.") }
        let p = UIDocumentPickerViewController(forOpeningContentTypes: DeskFiles.pickerTypes, asCopy: true)
        p.delegate = self
        present(p, animated: true)
    }

    /** Make it ready away from the screen's thread, then send, or say why not. */
    private func prepareAndSend(_ work: @escaping () -> Result<DeskFiles.Ready, DeskFiles.Problem>) {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let ready = work()
            DispatchQueue.main.async {
                switch ready {
                case .success(let f): self?.client.sendFile(f)
                case .failure(let p): self?.toast(p.message)
                }
            }
        }
    }

    private func label(_ s: String, size: CGFloat, color: UIColor) -> UILabel {
        let l = UILabel()
        l.text = s
        l.font = .systemFont(ofSize: size)
        l.textColor = color
        return l
    }

    private func toast(_ message: String) {
        Toast.show(message, in: view, above: input.topAnchor)
    }
}

extension ChatViewController: PHPickerViewControllerDelegate {
    func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
        picker.dismiss(animated: true)
        guard let item = results.first?.itemProvider else { return }
        let type = item.registeredTypeIdentifiers.compactMap(UTType.init).first { $0.conforms(to: .image) } ?? .image
        let name = (item.suggestedName ?? "photo") + "." + (type.preferredFilenameExtension ?? "jpg")
        item.loadDataRepresentation(forTypeIdentifier: type.identifier) { [weak self] data, _ in
            DispatchQueue.main.async {
                guard let data else { return self?.toast("That picture couldn't be read.") ?? () }
                self?.prepareAndSend { DeskFiles.photo(data, name: name, type: type) }
            }
        }
    }
}

extension ChatViewController: UIImagePickerControllerDelegate, UINavigationControllerDelegate {
    func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
        picker.dismiss(animated: true)
        guard let img = info[.originalImage] as? UIImage else { return toast("The photo wasn't saved. Try again.") }
        let stamp = Int(Date().timeIntervalSince1970)
        prepareAndSend {
            guard let jpeg = DeskFiles.small(img, edge: 2048).jpegData(compressionQuality: 0.85) else {
                return .failure(DeskFiles.Problem("The photo wasn't saved. Try again."))
            }
            return .success(DeskFiles.Ready(name: "photo-\(stamp).jpg", mime: "image/jpeg", data: jpeg))
        }
    }

    func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
        picker.dismiss(animated: true)
    }
}

extension ChatViewController: UIDocumentPickerDelegate {
    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        guard let url = urls.first else { return }
        prepareAndSend { DeskFiles.file(url) }
    }
}

/** A picture full size: pinch to look closer, tap or swipe down to close, Share to keep it. */
final class PictureViewController: UIViewController, UIScrollViewDelegate {
    private let image: UIImage
    private let link: URL?
    private let scroll = UIScrollView()
    private let view2 = UIImageView()

    init(image: UIImage, link: URL?) {
        self.image = image
        self.link = link
        super.init(nibName: nil, bundle: nil)
        modalPresentationStyle = .fullScreen
        modalTransitionStyle = .crossDissolve
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("Opened from the chat") }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        scroll.delegate = self
        scroll.maximumZoomScale = 4
        scroll.frame = view.bounds
        scroll.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view2.image = image
        view2.contentMode = .scaleAspectFit
        view2.frame = scroll.bounds
        view2.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view2.isAccessibilityElement = true
        view2.accessibilityLabel = "Picture"
        scroll.addSubview(view2)
        view.addSubview(scroll)
        scroll.addGestureRecognizer(Tap { [weak self] in self?.dismiss(animated: true) })
        let swipe = UISwipeGestureRecognizer(target: self, action: #selector(close))
        swipe.direction = .down
        view.addGestureRecognizer(swipe)

        let close = UIButton(type: .system)
        close.setImage(UIImage(systemName: "xmark", withConfiguration: UIImage.SymbolConfiguration(pointSize: 18, weight: .semibold)), for: .normal)
        close.tintColor = .white
        close.accessibilityLabel = "Close"
        close.addTarget(self, action: #selector(self.close), for: .touchUpInside)
        let share = UIButton(type: .system)
        share.setImage(UIImage(systemName: "square.and.arrow.up", withConfiguration: UIImage.SymbolConfiguration(pointSize: 18, weight: .semibold)), for: .normal)
        share.tintColor = .white
        share.accessibilityLabel = "Share or save"
        share.addAction(UIAction { [weak self, weak share] _ in
            guard let self else { return }
            let a = UIActivityViewController(activityItems: [self.image], applicationActivities: nil)
            a.popoverPresentationController?.sourceView = share
            self.present(a, animated: true)
        }, for: .touchUpInside)
        for b in [close, share] {
            b.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview(b)
        }
        NSLayoutConstraint.activate([
            close.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 6),
            close.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 8),
            close.widthAnchor.constraint(equalToConstant: 44),
            close.heightAnchor.constraint(equalToConstant: 44),
            share.topAnchor.constraint(equalTo: close.topAnchor),
            share.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -8),
            share.widthAnchor.constraint(equalToConstant: 44),
            share.heightAnchor.constraint(equalToConstant: 44),
        ])
    }

    override var preferredStatusBarStyle: UIStatusBarStyle { .lightContent }

    func viewForZooming(in scrollView: UIScrollView) -> UIView? { view2 }

    @objc private func close() {
        dismiss(animated: true)
    }
}

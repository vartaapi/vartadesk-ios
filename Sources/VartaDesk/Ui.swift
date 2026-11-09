import UIKit

/** The kit's few colours, the same as the website chat's. */
enum Ink {
    static let text = UIColor(red: 0x1E / 255, green: 0x1E / 255, blue: 0x24 / 255, alpha: 1)
    static let body = UIColor(red: 0x33 / 255, green: 0x33 / 255, blue: 0x3D / 255, alpha: 1)
    static let muted = UIColor(red: 0x6B / 255, green: 0x6B / 255, blue: 0x78 / 255, alpha: 1)
    static let faint = UIColor(red: 0x8A / 255, green: 0x8A / 255, blue: 0x96 / 255, alpha: 1)
    static let bubble = UIColor(red: 0xF1 / 255, green: 0xF1 / 255, blue: 0xF5 / 255, alpha: 1)
    static let field = UIColor(red: 0xF3 / 255, green: 0xF3 / 255, blue: 0xF7 / 255, alpha: 1)
    static let line = UIColor(red: 0xEE / 255, green: 0xEE / 255, blue: 0xF2 / 255, alpha: 1)
    static let border = UIColor(red: 0xD9 / 255, green: 0xD9 / 255, blue: 0xE2 / 255, alpha: 1)
    static let page = UIColor(red: 0xF7 / 255, green: 0xF7 / 255, blue: 0xF9 / 255, alpha: 1)
    static let error = UIColor(red: 0xC0 / 255, green: 0x36 / 255, blue: 0x2C / 255, alpha: 1)
    static let red = UIColor(red: 0xE5 / 255, green: 0x3E / 255, blue: 0x3E / 255, alpha: 1)
    static let green = UIColor(red: 0x1F / 255, green: 0x9D / 255, blue: 0x55 / 255, alpha: 1)
    static let amber = UIColor(red: 0xC9 / 255, green: 0xA2 / 255, blue: 0x27 / 255, alpha: 1)
    static let done = UIColor(red: 0x17 / 255, green: 0x80 / 255, blue: 0x4A / 255, alpha: 1)
    static let doneWash = UIColor(red: 0xE6 / 255, green: 0xF4 / 255, blue: 0xEC / 255, alpha: 1)
    static let openWash = UIColor(red: 0xEE / 255, green: 0xF0 / 255, blue: 0xFA / 255, alpha: 1)
    static let orange = UIColor(red: 0xFC / 255, green: 0x41 / 255, blue: 0x00 / 255, alpha: 1)
    /** VartaAPI's green, until the business's own colour has loaded. */
    static let brand = UIColor(red: 0, green: 0x4C / 255, blue: 0x3D / 255, alpha: 1)
}

/** A label in one line of code. */
func makeLabel(_ s: String, size: CGFloat, color: UIColor = Ink.text, bold: Bool = false, lines: Int = 0) -> UILabel {
    let l = UILabel()
    l.text = s
    l.font = bold ? .boldSystemFont(ofSize: size) : .systemFont(ofSize: size)
    l.textColor = color
    l.numberOfLines = lines
    return l
}

/** The navigation bar of the kit's screens: white, a thin line under it. */
func plainBar(_ item: UINavigationItem) {
    let bar = UINavigationBarAppearance()
    bar.configureWithOpaqueBackground()
    bar.backgroundColor = .white
    bar.shadowColor = Ink.line
    bar.titleTextAttributes = [.foregroundColor: Ink.text]
    item.standardAppearance = bar
    item.scrollEdgeAppearance = bar
}

/** "14:05" for today, "28 Oct" before. */
func shortTime(_ iso: String) -> String {
    let f = ISO8601DateFormatter()
    f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    guard let d = f.date(from: iso) ?? ISO8601DateFormatter().date(from: iso) else { return "" }
    let out = DateFormatter()
    out.dateFormat = Calendar.current.isDateInToday(d) ? "HH:mm" : "d MMM"
    return out.string(from: d)
}

/** A short note at the bottom of a screen that fades away (Android's toast). */
enum Toast {
    static func show(_ message: String, in view: UIView, above: NSLayoutYAxisAnchor? = nil) {
        let box = UIView()
        box.backgroundColor = UIColor(white: 0.12, alpha: 0.94)
        box.layer.cornerRadius = 10
        let t = makeLabel(message, size: 13.5, color: .white)
        t.textAlignment = .center
        box.addSubview(t)
        view.addSubview(box)
        for v in [box, t] as [UIView] { v.translatesAutoresizingMaskIntoConstraints = false }
        NSLayoutConstraint.activate([
            t.topAnchor.constraint(equalTo: box.topAnchor, constant: 10),
            t.bottomAnchor.constraint(equalTo: box.bottomAnchor, constant: -10),
            t.leadingAnchor.constraint(equalTo: box.leadingAnchor, constant: 14),
            t.trailingAnchor.constraint(equalTo: box.trailingAnchor, constant: -14),
            box.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            box.widthAnchor.constraint(lessThanOrEqualTo: view.widthAnchor, constant: -40),
            box.bottomAnchor.constraint(equalTo: above ?? view.safeAreaLayoutGuide.bottomAnchor, constant: -18),
        ])
        UIView.animate(withDuration: 0.3, delay: 3.5, options: []) { box.alpha = 0 } completion: { _ in box.removeFromSuperview() }
    }
}

/** A tap that runs a closure. */
final class Tap: UITapGestureRecognizer {
    private let action: () -> Void
    init(_ action: @escaping () -> Void) {
        self.action = action
        super.init(target: nil, action: nil)
        addTarget(self, action: #selector(fire))
    }
    @objc private func fire() { action() }
}

/** "Copy" when a message is held. */
final class Copier: NSObject, UIContextMenuInteractionDelegate {
    static let shared = Copier()
    func contextMenuInteraction(_ interaction: UIContextMenuInteraction, configurationForMenuAtLocation location: CGPoint) -> UIContextMenuConfiguration? {
        guard let text = interaction.view?.accessibilityValue, !text.isEmpty else { return nil }
        return UIContextMenuConfiguration(identifier: nil, previewProvider: nil) { _ in
            UIMenu(children: [UIAction(title: "Copy", image: UIImage(systemName: "doc.on.doc")) { _ in UIPasteboard.general.string = text }])
        }
    }
}

final class PaddedLabel: UILabel {
    var inset = UIEdgeInsets(top: 9, left: 12, bottom: 9, right: 12)
    override func drawText(in rect: CGRect) { super.drawText(in: rect.inset(by: inset)) }
    override var intrinsicContentSize: CGSize {
        let s = super.intrinsicContentSize
        return CGSize(width: s.width + inset.left + inset.right, height: s.height + inset.top + inset.bottom)
    }
}

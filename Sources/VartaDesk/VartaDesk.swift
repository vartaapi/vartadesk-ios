import UIKit
import UserNotifications

/**
 * VartaAPI Desk for iPhone and iPad (DK25): the business's website chat,
 * inside its own iOS app, drawn with Apple's own screens.
 *
 *     import VartaDesk
 *
 *     // Once, when the app starts (application(_:didFinishLaunchingWithOptions:)):
 *     VartaDesk.setup(workspace: "ws_xxxxxxxxxx")
 *
 *     // When someone signs in to the app. userHash is HMAC-SHA256 of the user
 *     // id with the workspace secret, made on the business's own server, the
 *     // same as for its website (Settings → Website chat → Safety):
 *     VartaDesk.login(VartaDeskUser(userId: "42", userHash: hash, name: "Asha", email: "asha@example.com"))
 *
 *     // From any button or menu: Home (the conversation, help, tickets), or straight to the chat:
 *     VartaDesk.open()
 *     VartaDesk.openChat()
 *
 *     // Or a round chat button in the corner of a screen, with the unread count (in viewDidLoad):
 *     VartaDesk.showChatButton(in: self)
 *
 *     // Or your own badge: called with the number of replies not read yet.
 *     VartaDesk.setUnreadListener { count in badge.text = "\(count)" }
 *
 *     // Notifications for replies, through Apple with your own push key (Settings →
 *     // Website chat → Notifications on the phone). In your AppDelegate:
 *     func application(_ app: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken token: Data) {
 *         VartaDesk.setPushToken(token)
 *     }
 *     // and in your UNUserNotificationCenterDelegate:
 *     willPresent:  return VartaDesk.presentationOptions(for: notification) ?? [.banner, .sound]
 *     didReceive:   if VartaDesk.handleNotificationTap(response) { return }   // ours: opens the chat
 *
 *     // When they sign out, so the next person on this phone doesn't see their chat:
 *     VartaDesk.logout()
 *
 * Without login() the chat is anonymous and stays on this phone only. With a
 * valid userHash the person shows as verified to the team and their chat
 * follows them to the website and any other device.
 *
 * Call it from the main thread, as with any UIKit code.
 */
@MainActor
public enum VartaDesk {
    /** The kit's version, sent with each call so the team's server knows it. */
    public static let version = "1.0.0"

    static var client: DeskClient?

    /** Start the kit. `apiBase` is only for testing against a server of your own. */
    public static func setup(workspace: String, apiBase: String = "https://api.vartaapi.com") {
        guard workspace.range(of: "^ws_[A-Za-z0-9]{6,40}$", options: .regularExpression) != nil else {
            preconditionFailure("VartaDesk: \"\(workspace)\" isn't a workspace id (ws_…).")
        }
        client?.close()
        unreadHook = nil
        var base = apiBase
        while base.hasSuffix("/") { base.removeLast() }
        client = DeskClient(workspace: workspace, apiBase: base)
    }

    /** Someone signed in to the app. Takes effect the next time the chat opens. */
    public static func login(_ user: VartaDeskUser) {
        need().login(user)
    }

    /** They signed out: forget their chat on this phone. */
    public static func logout() {
        need().logout()
    }

    /**
     * Show the chat's Home over `from` (or over whatever is on screen): the
     * conversation, the help centre and tickets. It slides up from the bottom
     * and the person closes it with the × at the top.
     */
    public static func open(from: UIViewController? = nil) {
        let c = need()
        present(HomeViewController(client: c), over: from)
    }

    /** Straight to the conversation itself. */
    public static func openChat(from: UIViewController? = nil) {
        let c = need()
        present(ChatViewController(client: c), over: from)
    }

    /** A round chat button in the bottom corner of `screen`, with the unread count. Call in viewDidLoad. */
    public static func showChatButton(in screen: UIViewController, left: Bool = false) {
        let c = need()
        let v = screen.view!
        if v.viewWithTag(ChatButton.tag) != nil { return }
        let b = ChatButton(client: c)
        b.translatesAutoresizingMaskIntoConstraints = false
        v.addSubview(b)
        NSLayoutConstraint.activate([
            b.bottomAnchor.constraint(equalTo: v.safeAreaLayoutGuide.bottomAnchor, constant: -16),
            left ? b.leadingAnchor.constraint(equalTo: v.safeAreaLayoutGuide.leadingAnchor, constant: 16)
                 : b.trailingAnchor.constraint(equalTo: v.safeAreaLayoutGuide.trailingAnchor, constant: -16),
        ])
    }

    /** Take the chat button off `screen`. */
    public static func hideChatButton(in screen: UIViewController) {
        screen.view.viewWithTag(ChatButton.tag)?.removeFromSuperview()
    }

    /** Team replies the person hasn't read yet (as far as this phone knows). */
    public static var unreadCount: Int { client?.unread ?? 0 }

    private static var unreadHook: UnreadHook?

    /**
     * Called on the main thread with the number of unread replies whenever it
     * changes, for a badge of your own. While set, the kit listens for replies
     * (while the app is open); pass nil to stop.
     */
    public static func setUnreadListener(_ listener: ((Int) -> Void)?) {
        let c = need()
        if let old = unreadHook { c.removeListener(old) }
        unreadHook = nil
        guard let listener else { return }
        let hook = UnreadHook(client: c, listener: listener)
        unreadHook = hook
        c.addListener(hook)
        c.open(quiet: true, fresh: 30)
        hook.deskChanged()
    }

    /**
     * This iPhone's Apple device token, from
     * application(_:didRegisterForRemoteNotificationsWithDeviceToken:). Call it
     * every time iOS gives it. The phone is registered for notifications once
     * the person has opened the chat.
     */
    public static func setPushToken(_ deviceToken: Data) {
        setPushToken(deviceToken.map { String(format: "%02x", $0) }.joined())
    }

    /** The same, as the hex text some push libraries hand over; nil stops notifications on this phone. */
    public static func setPushToken(_ token: String?) {
        let t = token?.trimmingCharacters(in: .whitespaces)
        need().setPushToken(t?.isEmpty == false ? t : nil)
    }

    /** Whether a notification is one of the kit's (a team reply), from its userInfo. */
    public static func isVartaDeskPush(_ userInfo: [AnyHashable: Any]) -> Bool {
        guard let c = client else { return false }
        return DeskNotify.isOurs(userInfo, client: c)
    }

    /**
     * For userNotificationCenter(_:willPresent:): how to show one of ours while
     * the app is open (nothing while the chat is on screen). nil when it isn't
     * ours, so your own notifications go on as before.
     */
    public static func presentationOptions(for notification: UNNotification) -> UNNotificationPresentationOptions? {
        guard let c = client else { return nil }
        return DeskNotify.presentation(notification, client: c)
    }

    /** For userNotificationCenter(_:didReceive:): opens the chat when one of ours is tapped. True when it was ours. */
    @discardableResult
    public static func handleNotificationTap(_ response: UNNotificationResponse) -> Bool {
        guard let c = client else { return false }
        return DeskNotify.tapped(response, client: c)
    }

    private static func present(_ screen: UIViewController, over from: UIViewController?) {
        guard let host = from ?? topViewController() else { return }
        let nav = UINavigationController(rootViewController: screen)
        nav.modalPresentationStyle = .pageSheet
        host.present(nav, animated: true)
    }

    private static func need() -> DeskClient {
        guard let c = client else { preconditionFailure("VartaDesk: call VartaDesk.setup(workspace:) first.") }
        return c
    }

    /** The screen in front, to show the chat over. */
    static func topViewController() -> UIViewController? {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let window = scenes.flatMap { $0.windows }.first { $0.isKeyWindow } ?? scenes.first?.windows.first
        var top = window?.rootViewController
        while let shown = top?.presentedViewController { top = shown }
        return top
    }
}

/** The person signed in to the business's app. */
public struct VartaDeskUser: Equatable, Sendable {
    public let userId: String
    public let userHash: String
    public let name: String?
    public let email: String?

    public init(userId: String, userHash: String, name: String? = nil, email: String? = nil) {
        self.userId = userId
        self.userHash = userHash
        self.name = name
        self.email = email
    }
}

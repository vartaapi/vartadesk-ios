import UIKit
import UserNotifications
import VartaDesk

/**
 * A stand-in for a business's own app: sign in, open the chat, sign out.
 *
 * Test settings come from LocalTest.plist next to this file (not in git):
 * workspace, api, userId, userHash. Without it the sample points at a
 * made-up workspace on the live server.
 */
@main
final class AppDelegate: UIResponder, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        VartaDesk.setup(workspace: Test.value("workspace", "ws_xxxxxxxxxx"), apiBase: Test.value("api", "https://api.vartaapi.com"))
        // Notifications for replies, as a business would set them up.
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        center.requestAuthorization(options: [.alert, .sound, .badge]) { granted, _ in
            guard granted else { return }
            DispatchQueue.main.async { application.registerForRemoteNotifications() }
        }
        return true
    }

    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        VartaDesk.setPushToken(deviceToken)
    }

    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        // Expected in this sample on the simulator: it isn't signed with a push entitlement.
        print("No Apple push token: \(error.localizedDescription)")
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        VartaDesk.presentationOptions(for: notification) ?? [.banner, .sound]
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        if VartaDesk.handleNotificationTap(response) { return }
        // …the app's own notifications would be handled here.
    }

    func application(_ application: UIApplication, configurationForConnecting session: UISceneSession, options: UIScene.ConnectionOptions) -> UISceneConfiguration {
        let c = UISceneConfiguration(name: nil, sessionRole: session.role)
        c.delegateClass = SceneDelegate.self
        return c
    }
}

final class SceneDelegate: UIResponder, UIWindowSceneDelegate {
    var window: UIWindow?

    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options: UIScene.ConnectionOptions) {
        guard let scene = scene as? UIWindowScene else { return }
        let w = UIWindow(windowScene: scene)
        w.rootViewController = UINavigationController(rootViewController: MainViewController())
        w.makeKeyAndVisible()
        window = w
    }
}

enum Test {
    private static let values: [String: String] = {
        guard let url = Bundle.main.url(forResource: "LocalTest", withExtension: "plist"),
              let dict = NSDictionary(contentsOf: url) as? [String: String] else { return [:] }
        return dict
    }()

    static func value(_ key: String, _ fallback: String = "") -> String { values[key] ?? fallback }
}

final class MainViewController: UIViewController {
    private let who = UILabel()
    private let unread = UILabel()

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Sample shop"
        view.backgroundColor = .systemBackground
        who.text = "Not signed in"
        who.font = .systemFont(ofSize: 15)
        who.textAlignment = .center

        let signIn = button("Sign in as test user") { [weak self] in
            VartaDesk.login(VartaDeskUser(userId: Test.value("userId"), userHash: Test.value("userHash"), name: "iPhone Tester", email: "iphone.tester@example.com"))
            self?.who.text = "Signed in as \(Test.value("userId"))"
        }
        signIn.isEnabled = !Test.value("userId").isEmpty
        let chat = button("Chat with us") { VartaDesk.open() }
        let direct = button("Open the chat itself") { VartaDesk.openChat() }
        // Without a signed build there is no real Apple token: a made-up one, the same shape.
        let testToken = button("Use a test notification token") {
            VartaDesk.setPushToken(String(repeating: "ab12", count: 16))
        }
        let signOut = button("Sign out") { [weak self] in
            VartaDesk.logout()
            self?.who.text = "Not signed in"
        }
        unread.font = .systemFont(ofSize: 14)
        unread.textColor = .secondaryLabel
        unread.textAlignment = .center
        let stack = UIStackView(arrangedSubviews: [who, signIn, chat, direct, testToken, signOut, unread])
        stack.axis = .vertical
        stack.spacing = 14
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 40),
            stack.leadingAnchor.constraint(equalTo: view.layoutMarginsGuide.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: view.layoutMarginsGuide.trailingAnchor),
        ])
        // The round chat button with the unread count, as a business would add it,
        // and the app's own badge from the unread listener.
        VartaDesk.showChatButton(in: self)
        VartaDesk.setUnreadListener { [weak self] n in self?.unread.text = "Unread replies (app's own badge): \(n)" }
    }

    private func button(_ title: String, _ action: @escaping () -> Void) -> UIButton {
        var c = UIButton.Configuration.filled()
        c.title = title
        c.cornerStyle = .large
        return UIButton(configuration: c, primaryAction: UIAction { _ in action() })
    }
}

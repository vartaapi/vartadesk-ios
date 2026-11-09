import UIKit
import UserNotifications

/**
 * Notifications for team replies (DK25d). Our server sends them through Apple
 * with the business's own push key, as ordinary notifications: iOS shows
 * them itself, one group per chat. The kit only decides what happens around
 * them: not shown while the chat is on screen, cleared when it opens, and a
 * tap opens the chat.
 */
@MainActor
enum DeskNotify {
    /** Ours, and for this workspace (an app could have the kit set up for another one before). */
    static func isOurs(_ info: [AnyHashable: Any], client: DeskClient) -> Bool {
        (info["vartadesk"] as? String) == "1" && (info["workspace"] as? String) == client.workspace
    }

    /** How to show one that arrives while the app is open: not at all while the chat is on screen. */
    static func presentation(_ n: UNNotification, client: DeskClient) -> UNNotificationPresentationOptions? {
        guard isOurs(n.request.content.userInfo, client: client) else { return nil }
        client.pushArrived()
        if client.chatVisible { return [] }
        return [.banner, .list, .sound]
    }

    /** A tap on one of ours: open the chat (or bring it forward if the kit is already on screen). */
    static func tapped(_ r: UNNotificationResponse, client: DeskClient) -> Bool {
        guard isOurs(r.notification.request.content.userInfo, client: client) else { return false }
        if client.chatVisible { return true }
        let top = VartaDesk.topViewController()
        if let nav = top as? UINavigationController, nav.viewControllers.first is HomeViewController {
            nav.pushViewController(ChatViewController(client: client), animated: true)
        } else {
            VartaDesk.openChat(from: top)
        }
        return true
    }

    /** The chat is open: its notifications have done their job. */
    static func clear(client: DeskClient) {
        let center = UNUserNotificationCenter.current()
        let workspace = client.workspace
        center.getDeliveredNotifications { list in
            let ids = list.filter {
                let info = $0.request.content.userInfo
                return (info["vartadesk"] as? String) == "1" && (info["workspace"] as? String) == workspace
            }.map(\.request.identifier)
            if !ids.isEmpty { UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: ids) }
        }
    }
}

# VartaAPI Desk for iPhone and iPad

Your [VartaAPI Desk](https://www.vartaapi.com/desk/) chat, help centre and
tickets inside your own iOS app, drawn with Apple's own screens in your
colour. A Swift package with no other libraries. iOS 15 and later.

**Full guide:** https://www.vartaapi.com/desk/ios/

## Install

In Xcode: **File → Add Package Dependencies…**, paste

```
https://github.com/vartaapi/vartadesk-ios
```

and add the **VartaDesk** library to your app.

## Use

```swift
import VartaDesk

// Once, when the app starts. Your workspace ID is on the Website chat page in VartaAPI.
VartaDesk.setup(workspace: "ws_xxxxxxxxxx")

// After sign-in. userHash is HMAC-SHA256 of the user id with your workspace
// secret, made on your server (never put the secret in the app).
VartaDesk.login(VartaDeskUser(userId: user.id, userHash: hash, name: user.name, email: user.email))

VartaDesk.open()                                         // Home: the conversation, help, tickets
VartaDesk.openChat()                                     // or straight to the chat
VartaDesk.showChatButton(in: self)                       // a round chat button with the unread count
VartaDesk.setUnreadListener { count in /* your badge */ }

VartaDesk.logout()                                       // on sign-out
```

**Photos and files** work with Apple's own pickers. "Take a photo" needs a
camera line (`NSCameraUsageDescription`) in your app's Info.plist.

**Notifications for replies** come from your own app through Apple, with your
own push key (VartaAPI → Website chat → Notifications on the phone). Then:

```swift
func application(_ app: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken token: Data) {
    VartaDesk.setPushToken(token)
}
// UNUserNotificationCenterDelegate
func userNotificationCenter(_ c: UNUserNotificationCenter, willPresent n: UNNotification) async -> UNNotificationPresentationOptions {
    VartaDesk.presentationOptions(for: n) ?? [.banner, .sound]
}
func userNotificationCenter(_ c: UNUserNotificationCenter, didReceive r: UNNotificationResponse) async {
    if VartaDesk.handleNotificationTap(r) { return }    // a reply: opens the chat
}
```

## Sample app

`Sample/VartaDeskSample.xcodeproj` is a small shop app using the kit. To try it
against your workspace, add `Sample/VartaDeskSample/LocalTest.plist` with a
`workspace` value.

## Help

Questions: chat with us at [vartaapi.com](https://www.vartaapi.com/) or write
to support@vartaapi.com. MIT licence.

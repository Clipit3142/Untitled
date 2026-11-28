#if canImport(AppKit) && canImport(UserNotifications)
import AppKit
import Synchronization
import UserNotifications
import UntitledEngine

/// System notifications (3.15). Permission is asked only from onboarding step 6 (P1). Actions work
/// from banners and Notification Center with no window open (P2).
final class NotificationPresenter: NSObject, NotificationPresenting, UNUserNotificationCenterDelegate, Sendable {
    enum Action: Sendable {
        case undo(Int64)
        case showInFinder(Int64)
        case undoAll([Int64])
        case accept(String)
        case edit(String, name: String)
        case skip(String)
        case openReview
    }

    struct Options: Sendable {
        var renamed = true
        var review = true
        var sound = false
    }

    private let options = Mutex(Options())
    private let handler = Mutex<(@Sendable (Action) -> Void)?>(nil)
    private var center: UNUserNotificationCenter { .current() }

    static let renamedCategory = "RENAMED"
    static let reviewCategory = "REVIEW"
    static let summaryCategory = "SUMMARY"
    static let burstCategory = "BURST"

    /// Registers categories and the delegate. Call in applicationWillFinishLaunching, so a launch
    /// from a notification action is not missed.
    func activate(handler: @escaping @Sendable (Action) -> Void) {
        self.handler.withLock { $0 = handler }
        center.delegate = self
        let undo = UNNotificationAction(identifier: "UNDO", title: "Undo", options: [])
        let show = UNNotificationAction(identifier: "SHOW", title: "Show in Finder", options: [.foreground])
        let accept = UNNotificationAction(identifier: "ACCEPT", title: "Accept", options: [])
        let edit = UNTextInputNotificationAction(identifier: "EDIT", title: "Edit", options: [],
                                                 textInputButtonTitle: "Rename", textInputPlaceholder: "Type a name")
        let skip = UNNotificationAction(identifier: "SKIP", title: "Skip", options: [])
        let undoAll = UNNotificationAction(identifier: "UNDO_ALL", title: "Undo All", options: [])
        let review = UNNotificationAction(identifier: "OPEN_REVIEW", title: "Review", options: [.foreground])
        center.setNotificationCategories([
            UNNotificationCategory(identifier: Self.renamedCategory, actions: [undo, show], intentIdentifiers: [], options: []),
            UNNotificationCategory(identifier: Self.reviewCategory, actions: [accept, edit, skip], intentIdentifiers: [], options: []),
            UNNotificationCategory(identifier: Self.summaryCategory, actions: [undoAll], intentIdentifiers: [], options: []),
            UNNotificationCategory(identifier: Self.burstCategory, actions: [review], intentIdentifiers: [], options: []),
        ])
    }

    func update(_ preferences: AppPreferences) {
        options.withLock { $0 = Options(renamed: preferences.notifyRenamed, review: preferences.notifyReview, sound: preferences.renameSound) }
    }

    /// Onboarding step 6 only (P1).
    func requestPermission() async -> Bool {
        (try? await center.requestAuthorization(options: [.alert, .sound])) ?? false
    }

    // MARK: NotificationPresenting

    func postRenamed(operationID: Int64, oldName: String, newName: String) {
        let current = options.withLock { $0 }
        guard current.renamed else { return }
        post(id: "op-\(operationID)", title: newName, body: "Renamed from \(oldName)", category: Self.renamedCategory,
             info: ["operationID": operationID], sound: current.sound)
    }

    func postSummary(summaryID: String, operationIDs: [Int64]) {
        let current = options.withLock { $0 }
        guard current.renamed else { return }
        post(id: "summary-\(summaryID)", title: "Renamed \(operationIDs.count) files", body: "Undo All restores every original name.",
             category: Self.summaryCategory, info: ["operationIDs": operationIDs], sound: current.sound)
    }

    func removeRenamed(operationIDs: [Int64]) {
        center.removeDeliveredNotifications(withIdentifiers: operationIDs.map { "op-\($0)" })
    }

    func postReview(itemID: String, oldName: String, proposedName: String) {
        guard options.withLock({ $0.review }) else { return }
        post(id: "review-\(itemID)", title: proposedName, body: "Proposed for \(oldName)", category: Self.reviewCategory,
             info: ["itemID": itemID], sound: false)
    }

    func postBurst(groupID: String, count: Int) {
        guard options.withLock({ $0.review }) else { return }
        post(id: "burst-\(groupID)", title: "\(count) files waiting",
             body: "Many files arrived at once, so none were renamed automatically. Review them when you're ready.",
             category: Self.burstCategory, info: [:], sound: false)
    }

    private func post(id: String, title: String, body: String, category: String, info: [String: Any], sound: Bool) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.categoryIdentifier = category
        content.userInfo = info
        content.threadIdentifier = category
        if sound { content.sound = .default }
        center.add(UNNotificationRequest(identifier: id, content: content, trigger: nil))
    }

    // MARK: UNUserNotificationCenterDelegate

    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .list, .sound]
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        let info = response.notification.request.content.userInfo
        let operationID = (info["operationID"] as? NSNumber)?.int64Value
        let operationIDs = (info["operationIDs"] as? [NSNumber])?.map(\.int64Value) ?? []
        let itemID = info["itemID"] as? String
        let action: Action?
        switch response.actionIdentifier {
        case "UNDO": action = operationID.map(Action.undo)
        case "SHOW": action = operationID.map(Action.showInFinder)
        case "UNDO_ALL": action = .undoAll(operationIDs)
        case "ACCEPT": action = itemID.map(Action.accept)
        case "EDIT":
            let text = (response as? UNTextInputNotificationResponse)?.userText ?? ""
            action = itemID.map { Action.edit($0, name: text) }
        case "SKIP": action = itemID.map(Action.skip)
        case "OPEN_REVIEW", UNNotificationDefaultActionIdentifier:
            action = operationID.map(Action.showInFinder) ?? .openReview
        default: action = nil
        }
        if let action, let handler = handler.withLock({ $0 }) { handler(action) }
    }
}
#endif

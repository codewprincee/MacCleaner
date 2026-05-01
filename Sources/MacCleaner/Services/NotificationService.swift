import Foundation
import UserNotifications

actor NotificationService {
    private let lowStorageThreshold: Int64 = 10 * 1_073_741_824 // 10 GB
    private var hasRequestedPermission = false

    func checkAndNotifyLowStorage(_ diskInfo: DiskUsageInfo) async {
        guard diskInfo.availableSpace < lowStorageThreshold else { return }

        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()

        switch settings.authorizationStatus {
        case .notDetermined:
            // Request permission only at this meaningful moment, not at app launch.
            guard !hasRequestedPermission else { return }
            hasRequestedPermission = true
            let granted = (try? await center.requestAuthorization(options: [.alert, .sound, .badge])) ?? false
            guard granted else { return }
        case .denied, .ephemeral:
            return
        case .authorized, .provisional:
            break
        @unknown default:
            return
        }

        let content = UNMutableNotificationContent()
        content.title = "Low Disk Space"
        content.body = "Only \(ByteFormatter.format(diskInfo.availableSpace)) free. Open MacCleaner to free up space."
        content.sound = .default
        content.categoryIdentifier = "LOW_STORAGE"

        let request = UNNotificationRequest(
            identifier: "low-storage-\(Date().timeIntervalSince1970)",
            content: content,
            trigger: nil
        )

        try? await center.add(request)
    }
}

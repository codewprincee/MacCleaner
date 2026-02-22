import Foundation
import UserNotifications

actor NotificationService {
    private let lowStorageThreshold: Int64 = 100 * 1_073_741_824 // 100 GB

    func requestPermission() async {
        let center = UNUserNotificationCenter.current()
        _ = try? await center.requestAuthorization(options: [.alert, .sound, .badge])
    }

    func checkAndNotifyLowStorage(_ diskInfo: DiskUsageInfo) async {
        guard diskInfo.freeSpace < lowStorageThreshold else { return }

        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        guard settings.authorizationStatus == .authorized else { return }

        let content = UNMutableNotificationContent()
        content.title = "Low Disk Space"
        content.body = "Only \(ByteFormatter.format(diskInfo.freeSpace)) free. Open MacCleaner to free up space."
        content.sound = .default
        content.categoryIdentifier = "LOW_STORAGE"

        let request = UNNotificationRequest(
            identifier: "low-storage-\(Date().timeIntervalSince1970)",
            content: content,
            trigger: nil // Deliver immediately
        )

        try? await center.add(request)
    }
}

import Foundation
import UIKit
import UserNotifications
import WidgetKit

/// §13: charging = snack time, Low Power Mode = blanket nap. App-side detection only; the
/// widget uses the last cached `DeviceSnapshot` (valid for 1 h).
@MainActor
final class DeviceStateMonitor {
    static let shared = DeviceStateMonitor()
    private var observers: [NSObjectProtocol] = []
    private(set) var current: DeviceSnapshot?

    func start() {
        guard observers.isEmpty else { update(); return }
        UIDevice.current.isBatteryMonitoringEnabled = true
        let nc = NotificationCenter.default
        let names: [Notification.Name] = [UIDevice.batteryStateDidChangeNotification,
                                          .NSProcessInfoPowerStateDidChange]
        for name in names {
            observers.append(nc.addObserver(forName: name, object: nil, queue: .main) { _ in
                Task { @MainActor in DeviceStateMonitor.shared.update() }
            })
        }
        update()
    }

    func update(now: Date = .now) {
        let state = UIDevice.current.batteryState
        let snap = DeviceSnapshot(charging: state == .charging || state == .full,
                                  lowPower: ProcessInfo.processInfo.isLowPowerModeEnabled,
                                  updatedAt: now)
        let changed = current?.charging != snap.charging || current?.lowPower != snap.lowPower
        current = snap
        LivingCache.shared.saveDevice(snap)
        if changed { WidgetCenter.shared.reloadAllTimelines() }
    }
}

/// ≤ 2 notifications per day in total (§2), opt-in, template lines only, positive only.
enum NudgePlanner {
    static let maxPerDay = 2
    /// Local (hour, minute) slots. Never at night.
    static let slots: [(hour: Int, minute: Int)] = [(11, 0), (17, 30)]

    /// Upcoming nudge times for the next `days` local days, at most `maxPerDay` per day.
    static func plannedDates(from now: Date, days: Int = 2, timeZone: TimeZone = .current) -> [Date] {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = timeZone
        var out: [Date] = []
        let today = cal.startOfDay(for: now)
        for d in 0..<max(0, days) {
            guard let day = cal.date(byAdding: .day, value: d, to: today) else { continue }
            var perDay = 0
            for s in slots where perDay < maxPerDay {
                guard let t = cal.date(bySettingHour: s.hour, minute: s.minute, second: 0, of: day), t > now else { continue }
                out.append(t)
                perDay += 1
            }
        }
        return out
    }
}

@MainActor
enum NudgeScheduler {
    static let idPrefix = "nudge-"

    static func requestPermission() async -> Bool {
        (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])) ?? false
    }

    /// Replaces all pending nudges. Off → everything removed.
    static func reschedule(enabled: Bool, creature: Creature?, now: Date = .now) async {
        let center = UNUserNotificationCenter.current()
        let pending = await center.pendingNotificationRequests()
        center.removePendingNotificationRequests(withIdentifiers: pending.map(\.identifier).filter { $0.hasPrefix(idPrefix) })
        guard enabled, let creature, CareEngine.stage(creature, at: now) != .egg else { return }
        let settings = await center.notificationSettings()
        guard settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional else { return }
        for date in NudgePlanner.plannedDates(from: now) {
            let seed = "\(creature.id)|\(Int(date.timeIntervalSince1970))"
            let category: LineCategory = ActivityStateMachine.localHour(date, .current) < 14 ? .selfCare : .encouragement
            let line = LineService.template(category, seed: seed, name: creature.name)
            let content = UNMutableNotificationContent()
            content.title = creature.name
            content.body = line.text
            let comps = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: date)
            let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
            let id = idPrefix + String(Int(date.timeIntervalSince1970))
            try? await center.add(UNNotificationRequest(identifier: id, content: content, trigger: trigger))
        }
    }
}

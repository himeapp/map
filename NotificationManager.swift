import Foundation
import UserNotifications

// MARK: - 알림 관리자 (백그라운드에서도 "탔어요/내렸어요" 받기)
//
// 앱이 백그라운드/잠금화면일 때도 도착 임박을 알리고, 알림의 액션 버튼으로
// 유저가 탑승/하차를 "선언"할 수 있게 한다. (핵심 UX: 앱이 멋대로 판단 ❌)
// iOS 16.1+ 알림 액션 방식. 다이내믹 아일랜드(Live Activity)는 다음 단계.

final class NotificationManager: NSObject {
    static let shared = NotificationManager()

    weak var viewModel: TransitViewModel?

    // 같은 단계 알림 중복 방지용 키
    private var firedKeys = Set<String>()

    enum Cat {
        static let board = "BOARD"        // 탑승 권유
        static let getOff = "GETOFF"      // 하차 권유
        static let transfer = "TRANSFER"  // 환승 하차 권유
    }
    enum Act {
        static let board = "ACT_BOARD"
        static let arrive = "ACT_ARRIVE"
        static let transfer = "ACT_TRANSFER"
    }

    /// 앱 시작 시 1회 — 델리게이트 등록 + 액션 카테고리 정의
    func configure() {
        let center = UNUserNotificationCenter.current()
        center.delegate = self

        let board = UNNotificationAction(identifier: Act.board, title: "탔어요", options: [.foreground])
        let arrive = UNNotificationAction(identifier: Act.arrive, title: "도착했어요", options: [.foreground])
        let transfer = UNNotificationAction(identifier: Act.transfer, title: "환승하러 내렸어요", options: [.foreground])

        center.setNotificationCategories([
            UNNotificationCategory(identifier: Cat.board, actions: [board], intentIdentifiers: [], options: []),
            UNNotificationCategory(identifier: Cat.getOff, actions: [arrive], intentIdentifiers: [], options: []),
            UNNotificationCategory(identifier: Cat.transfer, actions: [transfer], intentIdentifiers: [], options: []),
        ])
    }

    func requestAuthorization() {
        UNUserNotificationCenter.current()
            .requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }
    }

    /// 새 여정/단계 시작 시 중복 방지 키 초기화
    func resetFired() { firedKeys.removeAll() }

    // MARK: - 발송

    /// 하차/환승 정류소 근접 → "곧 내려요/환승해요"
    func fireGetOffApproach(stop: String, isTransfer: Bool, transferLine: String?) {
        let key = "getoff:\(stop):\(isTransfer)"
        guard !firedKeys.contains(key) else { return }
        firedKeys.insert(key)

        let content = UNMutableNotificationContent()
        if isTransfer {
            if let to = transferLine {
                content.title = "곧 \(stop)에서 \(to)\(josaRo(to)) 환승해요"
            } else {
                content.title = "곧 \(stop)에서 내려서 환승해요"
            }
            content.body = "내려서 환승할 준비하세요 · 내렸으면 눌러주세요"
            content.categoryIdentifier = Cat.transfer
        } else {
            content.title = "곧 \(stop)에서 내려요"
            content.body = "내릴 준비하세요 · 도착하면 눌러주세요"
            content.categoryIdentifier = Cat.getOff
        }
        content.sound = .default
        push(content)
    }

    /// 탈 차량 도착 임박 → "○○번 곧 도착"
    func fireBoardArrival(option: BoardableOption) {
        let key = "board:\(option.id.uuidString)"
        guard !firedKeys.contains(key) else { return }
        firedKeys.insert(key)

        let content = UNMutableNotificationContent()
        let line = option.vehicle.type == .bus ? "\(option.vehicle.number)번" : option.vehicle.number
        content.title = "\(line) 곧 도착"
        content.body = "타시면 눌러주세요"
        content.categoryIdentifier = Cat.board
        content.userInfo = ["optionID": option.id.uuidString]
        content.sound = .default
        push(content)
    }

    private func push(_ content: UNMutableNotificationContent) {
        let req = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(req)
    }
}

// MARK: - 응답 라우팅 (알림 액션 → VM 선언)

extension NotificationManager: UNUserNotificationCenterDelegate {
    // 앱이 켜져 있어도 배너로 보이게
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound])
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        let action = response.actionIdentifier
        let userInfo = response.notification.request.content.userInfo
        Task { @MainActor in
            switch action {
            case Act.board:
                if let s = userInfo["optionID"] as? String, let id = UUID(uuidString: s) {
                    self.viewModel?.boardByID(id)
                }
            case Act.arrive:
                self.viewModel?.arrive()
            case Act.transfer:
                self.viewModel?.startTransfer()
            default:
                break  // 알림 본문 탭 → 그냥 앱 열기
            }
            completionHandler()
        }
    }
}

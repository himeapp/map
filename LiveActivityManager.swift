import Foundation
import ActivityKit

// MARK: - Live Activity 관리자 (앱 쪽)
//
// VM의 상태 변화를 받아 다이내믹 아일랜드/잠금화면 Live Activity를 시작·갱신·종료한다.
// iOS 16.1 기준 API(deprecated이지만 16.1에서 동작) 사용 — 최소 지원 버전 유지.

@MainActor
final class LiveActivityManager {
    static let shared = LiveActivityManager()

    private var activity: Activity<TransitActivityAttributes>?

    /// 활성 Live Activity 시작. 이미 있으면 내용만 갱신.
    func start(destination: String, state: TransitActivityAttributes.ContentState) {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }

        if activity != nil {
            update(state: state)
            return
        }

        let attributes = TransitActivityAttributes(destination: destination)
        do {
            activity = try Activity.request(
                attributes: attributes,
                contentState: state,
                pushType: nil
            )
        } catch {
            // 시작 실패는 조용히 무시 (권한/시스템 제한 등)
        }
    }

    /// 활성 Live Activity 내용 갱신.
    func update(state: TransitActivityAttributes.ContentState) {
        guard let activity else { return }
        Task { await activity.update(using: state) }
    }

    /// Live Activity 종료(즉시 제거).
    func end() {
        guard let activity else { return }
        self.activity = nil
        Task { await activity.end(dismissalPolicy: .immediate) }
    }
}

import Foundation
import ActivityKit

// MARK: - Live Activity 속성 (앱 ↔ 위젯 익스텐션 공유)
//
// 다이내믹 아일랜드 / 잠금화면에 띄우는 "지금 이동 중" 카드의 데이터 모델.
// 앱 타깃과 위젯 익스텐션 타깃 양쪽에서 컴파일된다(project.yml 참고).
//
// 핵심 UX 원칙 유지: 여기 담긴 건 안내 표시일 뿐, 탑승/하차 판단은 항상 유저 선언.

struct TransitActivityAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        var phase: Phase
        var lineLabel: String      // "271번" / "2호선"
        var lineColorHex: String   // 노선 색 (#rrggbb)
        var headline: String       // 큰 글씨: "271번 3분 후 도착" / "성수에서 하차"
        var detail: String         // 작은 글씨: "강남역 방향" 등
        var minutes: Int?          // 카운트다운 분 (대기 중일 때만, 없으면 nil)

        enum Phase: String, Codable, Hashable {
            case waiting   // 대기: 차량 곧 도착
            case onboard   // 탑승 중: 하차역까지
            case transfer  // 환승 도보 중
        }
    }

    var destination: String   // 목적지명 (여정 동안 고정)
}

import WidgetKit
import SwiftUI

// MARK: - 위젯 익스텐션 번들 엔트리
//
// 현재는 Live Activity(다이내믹 아일랜드 + 잠금화면) 하나만 제공.
// 홈 화면 위젯이 필요해지면 여기 body에 추가하면 된다.

@main
struct HimemapWidgetBundle: WidgetBundle {
    var body: some Widget {
        TransitLiveActivity()
    }
}

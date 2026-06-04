import SwiftUI

// MARK: - App

@main
struct GajaApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}

// MARK: - ContentView

struct ContentView: View {
    @StateObject private var vm = TransitViewModel()

    var body: some View {
        ZStack {
            switch vm.appState {
            case .home, .searching:
                HomeView()

            case .routes:
                // ① 전체 경로 — 지도 위에 큰 바텀시트로 경로 목록
                ZStack(alignment: .bottom) {
                    HomeView()
                    BottomSheet(detent: .large) {
                        RouteResultsView()
                    }
                }

            case .walkingToStop:
                // 지도 위에 도보 안내 모달 (콘텐츠 높이 자동 → medium)
                ZStack(alignment: .bottom) {
                    HomeView()
                    BottomSheet {
                        WalkToStopView()
                    }
                }

            case .waiting:
                // 지도 위에 바텀시트로
                ZStack(alignment: .bottom) {
                    HomeView()
                    BottomSheet {
                        WaitingView()
                    }
                }

            case .rerouting:
                ZStack(alignment: .bottom) {
                    HomeView()
                    BottomSheet {
                        RerouteView()
                    }
                }

            case .transferWalking:
                ZStack(alignment: .bottom) {
                    HomeView()
                    BottomSheet(detent: .large) {
                        TransferView()
                    }
                }

            case .onboard:
                ZStack(alignment: .bottom) {
                    HomeView()
                    BottomSheet(detent: .large) {
                        OnboardView()
                    }
                }

            case .arrived:
                // 도착 요약은 지도를 가리는 전체 화면 시트
                ZStack(alignment: .bottom) {
                    HomeView()
                    BottomSheet(detent: .large) {
                        ArriveView()
                    }
                }

            case .intercity:
                ZStack(alignment: .bottom) {
                    HomeView()
                    BottomSheet(detent: .large) {
                        IntercityView()
                    }
                }
            }
        }
        .environmentObject(vm)
    }
}

// MARK: - Bottom Sheet 래퍼

struct BottomSheet<Content: View>: View {
    enum Detent: CaseIterable {
        case small, medium, large
        var fraction: CGFloat {
            switch self {
            case .small:  return 0.30
            case .medium: return 0.55
            case .large:  return 0.92
            }
        }
    }

    let allowed: [Detent]
    let content: () -> Content

    @State private var current: Detent
    /// 손잡이를 끄는 동안의 실시간 오프셋(아래로 끌면 +, 위로 끌면 −).
    @State private var drag: CGFloat = 0

    init(detent: Detent = .medium,
         allowed: [Detent] = [.medium, .large],
         @ViewBuilder content: @escaping () -> Content) {
        self.allowed = allowed
        self.content = content
        _current = State(initialValue: detent)
    }

    private var minFraction: CGFloat { (allowed.map(\.fraction).min() ?? 0.30) }
    private var maxFraction: CGFloat { (allowed.map(\.fraction).max() ?? 0.92) }

    var body: some View {
        GeometryReader { geo in
            let H = geo.size.height
            // 현재 디텐트 높이에서 끌고 있는 만큼 더하거나 빼고, 허용 범위로 클램프.
            let height = min(max(H * current.fraction - drag,
                                 H * minFraction),
                             H * maxFraction)

            VStack(spacing: 0) {
                // 손잡이 — 이 영역을 끌어 시트 높이를 조절한다.
                Capsule()
                    .fill(Color(.systemGray4))
                    .frame(width: 36, height: 5)
                    .padding(.top, 8)
                    .padding(.bottom, 6)
                    .frame(maxWidth: .infinity)
                    .contentShape(Rectangle())   // 손잡이 주변 전체를 잡을 수 있게
                    .gesture(
                        DragGesture(minimumDistance: 1)
                            .onChanged { value in
                                drag = value.translation.height
                            }
                            .onEnded { value in
                                // 빠르게 튕기면 더 멀리 가도록 예측 위치로 가까운 디텐트 선택.
                                let projected = H * current.fraction - value.predictedEndTranslation.height
                                let target = allowed.min(by: {
                                    abs(H * $0.fraction - projected) < abs(H * $1.fraction - projected)
                                }) ?? current
                                withAnimation(.spring(response: 0.34, dampingFraction: 0.86)) {
                                    current = target
                                    drag = 0
                                }
                            }
                    )

                content()
                    .frame(maxHeight: .infinity, alignment: .top)
            }
            .frame(maxWidth: .infinity)
            .frame(height: height)
            .background(Color(.systemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 20))
            .shadow(color: .black.opacity(0.12), radius: 16, y: -4)
            .frame(maxHeight: .infinity, alignment: .bottom)
        }
        .ignoresSafeArea()
    }
}

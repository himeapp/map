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
                // ① 전체 경로 — 지도 위 모달(작게/중간/크게)로 경로 목록
                ZStack(alignment: .bottom) {
                    HomeView()
                    BottomSheet {
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
                    BottomSheet {
                        TransferView()
                    }
                }

            case .onboard:
                ZStack(alignment: .bottom) {
                    HomeView()
                    BottomSheet {
                        OnboardView()
                    }
                }

            case .arrived:
                // 도착 요약 모달 (작게/중간/크게)
                ZStack(alignment: .bottom) {
                    HomeView()
                    BottomSheet {
                        ArriveView()
                    }
                }

            case .intercity:
                ZStack(alignment: .bottom) {
                    HomeView()
                    BottomSheet {
                        IntercityView()
                    }
                }
            }
        }
        .environmentObject(vm)
        .onAppear {
            NotificationManager.shared.configure()
            NotificationManager.shared.requestAuthorization()
        }
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

    // 기본은 "작게/중간/크게" 3단계 모달 — 전체화면(크게)이 기본은 아니고 중간에서 연다.
    init(detent: Detent = .medium,
         allowed: [Detent] = [.small, .medium, .large],
         @ViewBuilder content: @escaping () -> Content) {
        self.allowed = allowed
        self.content = content
        _current = State(initialValue: detent)
    }

    private var minFraction: CGFloat { (allowed.map(\.fraction).min() ?? 0.30) }
    private var maxFraction: CGFloat { (allowed.map(\.fraction).max() ?? 0.92) }

    // 시트가 높을수록 뒤 지도를 더 어둡게 — "지도 위 카드"가 아니라 모달 레이어로 읽히게.
    private func scrimOpacity(height: CGFloat, H: CGFloat) -> Double {
        guard H > 0 else { return 0 }
        return min(0.45, Double(height / H) * 0.5)
    }

    var body: some View {
        GeometryReader { geo in
            let H = geo.size.height
            // 현재 디텐트 높이에서 끌고 있는 만큼 더하거나 빼고, 허용 범위로 클램프.
            let height = min(max(H * current.fraction - drag,
                                 H * minFraction),
                             H * maxFraction)

            ZStack(alignment: .bottom) {
                // 딤 배경 — 이게 있어야 떠다니는 팝업이 아니라 모달처럼 보인다.
                Color.black.opacity(scrimOpacity(height: height, H: H))
                    .ignoresSafeArea()

                VStack(spacing: 0) {
                    // 손잡이 — 이 띠 전체(넉넉한 그랩 영역)를 끌어 시트 높이를 조절한다.
                    // 좌표계를 .global 로 잡아야 시트가 손가락 밑에서 리사이즈돼도
                    // translation 이 튀지 않고 매끄럽게 따라온다.
                    Capsule()
                        .fill(Color(.systemGray3))
                        .frame(width: 40, height: 5)
                        .frame(maxWidth: .infinity)
                        .frame(height: 28)
                        .contentShape(Rectangle())
                        .gesture(
                            DragGesture(minimumDistance: 0, coordinateSpace: .global)
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
                // 상단만 둥글게 + 바닥은 화면 끝까지 — 바닥에 붙은 진짜 시트로 보이게.
                .clipShape(UnevenRoundedRectangle(topLeadingRadius: 20, topTrailingRadius: 20))
                .shadow(color: .black.opacity(0.12), radius: 16, y: -4)
            }
        }
        .ignoresSafeArea()
    }
}

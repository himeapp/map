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

            case .waiting:
                // 지도 위에 바텀시트로
                ZStack(alignment: .bottom) {
                    HomeView()
                    BottomSheet {
                        WaitingView()
                    }
                }

            case .onboard:
                ZStack(alignment: .bottom) {
                    HomeView()
                    BottomSheet(detent: .large) {
                        OnboardView()
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
    enum Detent { case medium, large }
    let detent: Detent
    let content: () -> Content

    init(detent: Detent = .medium, @ViewBuilder content: @escaping () -> Content) {
        self.detent = detent
        self.content = content
    }

    var body: some View {
        GeometryReader { geo in
            VStack(spacing: 0) {
                // 손잡이
                Capsule()
                    .fill(Color(.systemGray4))
                    .frame(width: 32, height: 3)
                    .padding(.top, 10)
                    .padding(.bottom, 4)

                content()
            }
            .frame(maxWidth: .infinity)
            .background(Color(.systemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 20))
            .shadow(color: .black.opacity(0.12), radius: 16, y: -4)
            .frame(height: detent == .medium ? geo.size.height * 0.55 : geo.size.height * 0.85)
            .frame(maxHeight: .infinity, alignment: .bottom)
        }
        .ignoresSafeArea()
    }
}

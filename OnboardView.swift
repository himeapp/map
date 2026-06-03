import SwiftUI

// MARK: - 탑승 후 View (ux_stage3)

struct OnboardView: View {
    @EnvironmentObject var vm: TransitViewModel
    @ObservedObject private var location = LocationManager.shared
    @State private var emergencyOpen = false

    var body: some View {
        guard let option = vm.selectedOption else { return AnyView(EmptyView()) }
        return AnyView(content(option: option))
    }

    @ViewBuilder
    private func content(option: BoardableOption) -> some View {
        VStack(spacing: 0) {
            header
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    busBadge(option: option)
                    if let d = approachDistance(option) {
                        approachBanner(distance: d, stop: getoffName(option))
                            .padding(.bottom, 14)
                    }
                    rideInfo(option: option)
                    if option.vehicle.type == .subway {
                        SubwayRouteMap(
                            lineColor: Color(hex: option.vehicle.lineColor),
                            originName: option.originStop?.name ?? "현재역",
                            exitName: getoffName(option),
                            upcomingStops: option.afterSteps.first?.stopsCount ?? 3
                        )
                        .padding(.bottom, 8)
                    } else {
                        timeline(option: option)
                    }
                    getoffBox(option: option)
                        .padding(.top, 4)
                    if hasTransfer(option) {
                        transferButton
                            .padding(.top, 12)
                    } else {
                        arrivedButton
                            .padding(.top, 12)
                    }
                }
                .padding(.horizontal, 18)
                .padding(.top, 6)
                .padding(.bottom, 16)
            }
            emergencyArea
        }
        .background(Color.appBg)
    }

    // MARK: - 헤더

    var header: some View {
        HStack(spacing: 10) {
            Button(action: vm.exitOnboard) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.primary)
                    .frame(width: 34, height: 34)
                    .background(Color(.secondarySystemBackground))
                    .clipShape(Circle())
            }
            Text("\(vm.toPlace?.name ?? "목적지") 가는 중")
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(.secondary)
            Spacer()
            Button(action: vm.goHome) {
                Image(systemName: "xmark")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.secondary)
                    .frame(width: 34, height: 34)
                    .background(Color(.secondarySystemBackground))
                    .clipShape(Circle())
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 6)
        .padding(.bottom, 10)
        .overlay(Divider(), alignment: .bottom)
    }

    // MARK: - 버스 배지

    func busBadge(option: BoardableOption) -> some View {
        Text(option.vehicle.number)
            .font(.system(size: 15, weight: .heavy))
            .foregroundColor(.white)
            .padding(.horizontal, 12).padding(.vertical, 5)
            .background(option.vehicle.displayColor, in: Capsule())
            .padding(.bottom, 8)
    }

    // MARK: - 하차 안내 ("○○에서 내려요")

    func rideInfo(option: BoardableOption) -> some View {
        let stop = getoffName(option)
        let stops = option.afterSteps.first?.stopsCount
        return VStack(alignment: .leading, spacing: 5) {
            (Text(stop).foregroundColor(.appBlue) + Text("에서 내려요").foregroundColor(.primary))
                .font(.system(size: 24, weight: .heavy))
            if let n = stops {
                Text("\(n) 정거장 남음 · 약 \(option.afterSteps.first?.durationMinutes ?? n * 2)분 후")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.secondary)
            }
        }
        .padding(.bottom, 16)
    }

    // MARK: - 세로 타임라인 (afterSteps)

    func timeline(option: BoardableOption) -> some View {
        VStack(spacing: 0) {
            ForEach(Array(option.afterSteps.enumerated()), id: \.element.id) { i, step in
                StepRow(step: step, isLast: i == option.afterSteps.count - 1)
            }
        }
        .padding(.bottom, 8)
    }

    // MARK: - 하차 박스

    func getoffBox(option: BoardableOption) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("여기서 내리세요")
                .font(.system(size: 12, weight: .bold))
                .foregroundColor(.appBlue)
            Text("\(getoffName(option)) 정류장")
                .font(.system(size: 17, weight: .heavy))
                .foregroundColor(.primary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 14).padding(.vertical, 11)
        .background(Color.appBlue.opacity(0.08), in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.appBlue, lineWidth: 1.5))
    }

    // MARK: - 도착 완료 트리거 ("내렸어요/도착했어요")
    //
    // 앱은 하차를 자동으로 못 잡으므로(GPS 한계) 탑승과 마찬가지로 유저의 선언으로 받는다.

    var arrivedButton: some View {
        Button(action: vm.arrive) {
            HStack(spacing: 8) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 17, weight: .bold))
                Text("도착했어요")
                    .font(.system(size: 16, weight: .bold))
            }
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 15)
            .background(Color.appGreen, in: RoundedRectangle(cornerRadius: 16))
        }
        .buttonStyle(.plain)
    }

    // 환승 구간이 남았을 때: "환승하러 내렸어요" → 환승 도보 화면
    var transferButton: some View {
        Button(action: vm.startTransfer) {
            HStack(spacing: 8) {
                Image(systemName: "arrow.triangle.swap")
                    .font(.system(size: 17, weight: .bold))
                Text("환승하러 내렸어요")
                    .font(.system(size: 16, weight: .bold))
            }
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 15)
            .background(Color.appBlue, in: RoundedRectangle(cornerRadius: 16))
        }
        .buttonStyle(.plain)
    }

    private func hasTransfer(_ option: BoardableOption) -> Bool {
        option.afterSteps.contains { $0.type == .transfer }
    }

    // MARK: - 도착 임박 넛지 (위치 기반 "준비하세요" 힌트)
    //
    // 위치로 목적지 근접을 감지해 "곧 내려요" 힌트만 띄운다. 하차 판단은 여전히 유저 선언.
    // 환승 구간(마지막 leg 아님)에선 목적지가 멀어 안 뜸 → 오탐 없음.
    // 위치 권한이 없으면(거리 nil) 조용히 미표시.

    private func approachDistance(_ option: BoardableOption) -> Double? {
        guard !hasTransfer(option),
              let coord = vm.toPlace?.coordinate,
              let d = location.distance(to: coord),
              d <= 600 else { return nil }
        return d
    }

    func approachBanner(distance: Double, stop: String) -> some View {
        let meters = Int((distance / 10).rounded()) * 10  // 10m 단위 반올림
        return HStack(spacing: 11) {
            ZStack {
                Circle().fill(Color.appGreen).frame(width: 36, height: 36)
                Image(systemName: "bell.badge.fill")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundColor(.white)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text("곧 \(stop)에서 내려요")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(.primary)
                Text("약 \(meters)m 남음 · 내릴 준비하세요")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14).padding(.vertical, 12)
        .background(Color.appGreen.opacity(0.10), in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.appGreen.opacity(0.5), lineWidth: 1.5))
        .transition(.move(edge: .top).combined(with: .opacity))
        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: meters <= 100)
    }

    // MARK: - 긴급 카드 영역

    var emergencyArea: some View {
        VStack(spacing: 6) {
            if emergencyOpen {
                emergencyPanel.transition(.move(edge: .bottom).combined(with: .opacity))
            }
            emergencyCard
        }
        .padding(.horizontal, 14)
        .padding(.top, 8)
        .padding(.bottom, 14)
        .background(Color.appBg)
        .overlay(Divider(), alignment: .top)
    }

    var emergencyCard: some View {
        Button { withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) { emergencyOpen.toggle() } } label: {
            HStack(spacing: 10) {
                ZStack {
                    Circle().fill(Color.appOrange).frame(width: 36, height: 36)
                    Image(systemName: "exclamationmark").font(.system(size: 16, weight: .bold)).foregroundColor(.white)
                }
                VStack(alignment: .leading, spacing: 1) {
                    Text("문제가 있나요?").font(.system(size: 14, weight: .bold)).foregroundColor(.primary)
                    Text("경로 이탈·잘못 탑승 등").font(.system(size: 12)).foregroundColor(.secondary)
                }
                Spacer()
                Text(emergencyOpen ? "닫기" : "도움받기")
                    .font(.system(size: 12, weight: .bold)).foregroundColor(.white)
                    .padding(.horizontal, 11).padding(.vertical, 6)
                    .background(Color.appOrange, in: RoundedRectangle(cornerRadius: 10))
            }
            .padding(.horizontal, 14).padding(.vertical, 12)
            .background(Color(hex: "#fff8f0"), in: RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.appOrange, lineWidth: 1.5))
        }
        .buttonStyle(.plain)
    }

    var emergencyPanel: some View {
        VStack(spacing: 0) {
            emergencyOption(icon: "mappin.and.ellipse", tint: .appRed,
                            title: "정거장을 지나쳤어요", sub: "현재 위치에서 다시 경로 탐색") {
                emergencyOpen = false
                vm.startReroute()
            }
            Divider().padding(.leading, 14)
            emergencyOption(icon: "arrow.uturn.left", tint: .appOrange,
                            title: "반대 방향으로 탔어요", sub: "반대편에서 다시 탑승") {
                vm.exitOnboard()
            }
            Divider().padding(.leading, 14)
            emergencyOption(icon: "magnifyingglass", tint: .appBlue,
                            title: "목적지를 바꾸고 싶어요", sub: "새 목적지 검색") {
                vm.goHome(); vm.startSearch(target: .to)
            }
        }
        .background(Color(hex: "#fff8f0"), in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.appOrange, lineWidth: 1.5))
    }

    func emergencyOption(icon: String, tint: Color, title: String, sub: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12).fill(tint.opacity(0.14)).frame(width: 38, height: 38)
                    Image(systemName: icon).font(.system(size: 16, weight: .semibold)).foregroundColor(tint)
                }
                VStack(alignment: .leading, spacing: 1) {
                    Text(title).font(.system(size: 13, weight: .bold)).foregroundColor(.primary)
                    Text(sub).font(.system(size: 11.5)).foregroundColor(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.right").font(.system(size: 13, weight: .semibold)).foregroundColor(Color(.systemGray3))
            }
            .padding(.horizontal, 14).padding(.vertical, 12)
        }
        .buttonStyle(.plain)
    }

    // MARK: - 헬퍼

    private func getoffName(_ option: BoardableOption) -> String {
        if let g = option.afterSteps.first(where: { $0.type == .getOff }) {
            // "강남역에서 하차" → "강남역" 형태로 정리
            let t = g.title.replacingOccurrences(of: "에서 하차", with: "")
            if !t.isEmpty { return t }
        }
        return vm.toPlace?.name ?? "도착지"
    }
}

// MARK: - 경로 스텝 행 (세로 타임라인, HTML tlv 스타일)

struct StepRow: View {
    let step: RouteStep
    let isLast: Bool

    var dotColor: Color {
        switch step.type {
        case .getOff:   return .appBlue
        case .walk:     return Color(.systemGray3)
        case .transfer: return .appOrange
        case .board:    return .appGreen
        case .arrive:   return .appPurple
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            VStack(spacing: 0) {
                Circle().fill(dotColor).frame(width: 12, height: 12).padding(.top, 4)
                if !isLast {
                    Rectangle().fill(Color.appLine).frame(width: 2).frame(minHeight: 38)
                }
            }
            .frame(width: 16)

            VStack(alignment: .leading, spacing: 4) {
                Text(step.title).font(.system(size: 15, weight: .bold)).foregroundColor(.primary)
                if !step.description.isEmpty {
                    Text(step.description).font(.system(size: 13)).foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let detail = step.detail {
                    Text(detail).font(.system(size: 12)).foregroundColor(.secondary)
                }
                badge
            }
            .padding(.bottom, isLast ? 0 : 18)
            Spacer()
        }
    }

    var badge: some View {
        let style = badgeStyle
        return HStack(spacing: 5) {
            Image(systemName: style.icon).font(.system(size: 12))
            Text(badgeText).font(.system(size: 12, weight: .semibold))
        }
        .foregroundColor(style.fg)
        .padding(.horizontal, 10).padding(.vertical, 5)
        .background(style.bg, in: RoundedRectangle(cornerRadius: 8))
    }

    var badgeStyle: (bg: Color, fg: Color, icon: String) {
        switch step.type {
        case .getOff:   return (Color.appBlue.opacity(0.12), .appBlue, "arrow.down.circle")
        case .walk:     return (Color(.tertiarySystemBackground), .secondary, "figure.walk")
        case .transfer: return (Color.appOrange.opacity(0.12), .appOrange, "arrow.triangle.2.circlepath")
        case .board:    return (Color.appGreen.opacity(0.14), Color(hex: "#1f9e44"), "tram.fill")
        case .arrive:   return (Color.appPurple.opacity(0.12), .appPurple, "flag.fill")
        }
    }

    var badgeText: String {
        switch step.type {
        case .getOff:   return "하차"
        case .walk:     return step.durationMinutes.map { "도보 \($0)분" } ?? "도보"
        case .transfer: return "환승"
        case .board:
            let num = step.vehicle?.number ?? ""
            let stops = step.stopsCount.map { " · \($0)정거장" } ?? ""
            return num + stops
        case .arrive:   return "목적지 도착"
        }
    }
}

// MARK: - 지하철 가로 노선도 (ux_stage3_sub)
//
// 현재역(펄스) → 앞으로 갈 역들(회색) → 하차역(강조)을 가로로. 호선색은 vehicle.lineColor.
// 역별 실시간 위치 데이터가 없으므로 정거장 수(upcomingStops)로 점만 표현한다.

struct SubwayRouteMap: View {
    let lineColor: Color
    let originName: String
    let exitName: String
    let upcomingStops: Int

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            ZStack(alignment: .leading) {
                // 기준선 (지나온 = 회색, 앞으로 = 호선색은 점으로 표현하므로 라인은 호선색)
                Capsule()
                    .fill(lineColor.opacity(0.85))
                    .frame(height: 6)
                    .padding(.horizontal, 37)
                    .padding(.top, 26)

                HStack(spacing: 0) {
                    station(name: originName, kind: .current)
                    ForEach(0..<max(0, upcomingStops - 1), id: \.self) { _ in
                        station(name: "", kind: .upcoming)
                    }
                    station(name: exitName, kind: .exit)
                }
            }
        }
        .frame(height: 64)
    }

    enum StationKind { case current, upcoming, exit }

    func station(name: String, kind: StationKind) -> some View {
        VStack(spacing: 8) {
            Text(name)
                .font(.system(size: kind == .current ? 12.5 : 11,
                              weight: kind == .upcoming ? .regular : .bold))
                .foregroundColor(nameColor(kind))
                .lineLimit(1)
                .frame(height: 16)

            dot(kind)
        }
        .frame(width: 74)
    }

    @ViewBuilder
    func dot(_ kind: StationKind) -> some View {
        switch kind {
        case .current:
            Circle()
                .fill(lineColor)
                .frame(width: 20, height: 20)
                .overlay(Circle().stroke(Color(.systemBackground), lineWidth: 3))
                .overlay(Circle().stroke(lineColor.opacity(0.25), lineWidth: 5).scaleEffect(1.5))
        case .upcoming:
            Circle()
                .fill(Color(hex: "#c8ccd4"))
                .frame(width: 13, height: 13)
                .overlay(Circle().stroke(Color(.systemBackground), lineWidth: 2.5))
        case .exit:
            Circle()
                .fill(Color(.systemBackground))
                .frame(width: 16, height: 16)
                .overlay(Circle().stroke(lineColor, lineWidth: 3))
        }
    }

    func nameColor(_ kind: StationKind) -> Color {
        switch kind {
        case .current:  return lineColor
        case .upcoming: return .secondary
        case .exit:     return .primary
        }
    }
}

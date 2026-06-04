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
                        approachBanner(distance: d, stop: getoffName(option),
                                       isTransfer: hasTransfer(option),
                                       transferTo: transferLineName(option))
                            .padding(.bottom, 14)
                    }
                    rideInfo(option: option)
                    if option.vehicle.type == .subway {
                        SubwayRouteMap(
                            lineColor: Color(hex: option.vehicle.lineColor),
                            originName: option.originStop?.name ?? "현재역",
                            exitName: getoffName(option),
                            passStops: option.afterSteps.first(where: { $0.type == .getOff })?.passStops,
                            upcomingStops: option.afterSteps.first?.stopsCount ?? 3,
                            boardedAt: vm.boardedAt,
                            totalRideMinutes: option.afterSteps.first?.durationMinutes
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

    // MARK: - 버스 탑승 구간 타임라인 (지금 탄 버스 한 구간만)
    //
    // 환승·도보·도착 등 "다음 단계"는 이 화면에 섞지 않는다 — 하차 후
    // 환승/도착 화면에서 다룬다. 여기선 탑승역 → (접히는) 경유 정류장 → 하차만.

    func timeline(option: BoardableOption) -> some View {
        let getOff = option.afterSteps.first { $0.type == .getOff }
        let pass = getOff?.passStops ?? []
        let board = option.originStop?.name ?? pass.first ?? "탑승 정류장"
        let remaining = getOff?.stopsCount ?? max(0, pass.count - 1)
        return BusRideTimeline(
            boardStop: board,
            stops: pass,
            coords: getOff?.passStopCoords ?? [],
            remainingFallback: remaining
        )
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
    // 위치로 "이번 구간 하차 정류소"에 근접하면 "곧 내려요" 힌트만 띄운다.
    // 하차 판단은 여전히 유저 선언("도착했어요"/"환승하러 내렸어요" 탭).
    // 환승 구간이면 환승 정류소를, 마지막 구간이면 최종 하차역을 기준으로 함.
    // 위치 권한이 없거나 좌표를 모르면(거리 nil) 조용히 미표시.

    private func approachDistance(_ option: BoardableOption) -> Double? {
        guard let coord = getoffCoord(option),
              let d = location.distance(to: coord),
              d <= 600 else { return nil }
        return d
    }

    /// 이번 구간 하차 정류소 좌표. 경유역 좌표가 있으면 마지막(=하차역),
    /// 없을 땐 환승 구간은 좌표 미상이라 nil, 마지막 구간만 최종 목적지로 대체.
    private func getoffCoord(_ option: BoardableOption) -> Coordinate? {
        if let last = option.afterSteps.first(where: { $0.type == .getOff })?.passStopCoords?.last {
            return last
        }
        return hasTransfer(option) ? nil : vm.toPlace?.coordinate
    }

    /// 환승 스텝에서 다음에 탈 수단 표시명 ("2호선" / "271번"). 없으면 nil.
    private func transferLineName(_ option: BoardableOption) -> String? {
        guard let t = option.afterSteps.first(where: { $0.type == .transfer }),
              let v = t.vehicle else { return nil }
        return v.type == .bus ? "\(v.number)번" : v.number
    }

    func approachBanner(distance: Double, stop: String, isTransfer: Bool, transferTo: String?) -> some View {
        let meters = Int((distance / 10).rounded()) * 10  // 10m 단위 반올림
        let title: String
        if let to = transferTo {
            title = "곧 \(stop)에서 \(to)\(josaRo(to)) 환승해요"
        } else if isTransfer {
            title = "곧 \(stop)에서 내려서 환승해요"
        } else {
            title = "곧 \(stop)에서 내려요"
        }
        return HStack(spacing: 11) {
            ZStack {
                Circle().fill(Color.appGreen).frame(width: 36, height: 36)
                Image(systemName: "bell.badge.fill")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundColor(.white)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
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
        // 시트가 safe area를 무시하고 바닥까지 내려오므로, 홈 인디케이터만큼 여백을 직접 준다.
        .padding(.bottom, max(14, safeBottomInset))
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
            // "강남역 하차" / "강남역에서 하차" → "강남역" 형태로 정리
            var t = g.title.replacingOccurrences(of: "에서 하차", with: "")
            if t.hasSuffix("하차") { t = String(t.dropLast(2)) }
            t = t.trimmingCharacters(in: .whitespaces)
            if !t.isEmpty { return t }
        }
        return vm.toPlace?.name ?? "도착지"
    }

    // 기기 하단 세이프 인셋(홈 인디케이터 높이). 시트가 safe area를 무시하므로 직접 읽는다.
    private var safeBottomInset: CGFloat {
        UIApplication.shared.connectedScenes
            .compactMap { ($0 as? UIWindowScene)?.keyWindow }
            .first?.safeAreaInsets.bottom ?? 0
    }
}

// MARK: - 버스 탑승 구간 타임라인 (HTML .tlv 스타일)
//
// 탑승역(지나옴) → 현재 위치(펄스) → "앞으로 N 정거장"(접힘, 탭하면 경유역 펼침).
// 하차역은 바로 아래 getoffBox가 받는다. 다음 leg(환승/도보/도착)는 여기 두지 않는다.
//
// "지금 어디쯤?" — 버스는 지상이라 GPS가 잘 잡혀서, 내 위치에서 가장 가까운
// 경유 정류장을 현재 위치로 본다. 좌표(coords)가 없거나 위치 권한이 없거나
// 경로에서 너무 멀면(>1.5km) 위치 표시를 끄고 기존 정적 타임라인으로 폴백.

struct BusRideTimeline: View {
    let boardStop: String
    let stops: [String]            // 전체 경유 정류장 [탑승역 … 하차역]. 없을 수 있음.
    let coords: [Coordinate]       // stops와 같은 순서·길이의 좌표 (GPS 매칭용). 없으면 빈 배열.
    let remainingFallback: Int     // 이름 데이터가 없을 때 쓸 "남은 정거장 수"
    @ObservedObject private var location = LocationManager.shared
    @State private var expanded = false

    private var lastIdx: Int { max(0, stops.count - 1) }

    // GPS로 추정한 현재 위치(가장 가까운 정류장 인덱스). 신뢰 못 하면 nil.
    private var currentIndex: Int? {
        guard coords.count == stops.count, stops.count >= 2, location.current != nil else { return nil }
        var best = 0
        var bestD = Double.greatestFiniteMagnitude
        for (i, c) in coords.enumerated() {
            if let d = location.distance(to: c), d < bestD { bestD = d; best = i }
        }
        return bestD <= 1500 ? best : nil   // 경로에서 너무 멀면 오탐 방지로 미표시
    }

    var body: some View {
        Group {
            if let cur = currentIndex {
                liveTimeline(current: cur)
            } else {
                staticTimeline()
            }
        }
        .padding(.bottom, 8)
    }

    // MARK: 실시간(GPS) 타임라인

    @ViewBuilder
    private func liveTimeline(current cur: Int) -> some View {
        // 남은 정거장 수는 헤드라인("N 정거장 남음", stopsCount)을 기준으로 센다.
        // 경유역 이름 배열 길이(lastIdx)와 stopsCount가 1 어긋나도 숫자가 일치하도록.
        let remaining = max(0, remainingFallback - cur)
        let upMids = (cur + 1 <= lastIdx - 1) ? Array(stops[(cur + 1)..<lastIdx]) : []
        VStack(spacing: 0) {
            if cur == 0 {
                // 탑승역이 곧 현재 위치
                node(kind: .current, isLast: false) {
                    Text(boardStop).font(.system(size: 15, weight: .bold)).foregroundColor(.primary)
                    Text("여기서 탔어요 · 지금 여기쯤").font(.system(size: 13)).foregroundColor(.appBlue)
                }
            } else {
                node(kind: .passed, isLast: false) {
                    Text(boardStop).font(.system(size: 15, weight: .semibold)).foregroundColor(.secondary)
                    Text(cur > 1 ? "여기서 탔어요 · \(cur - 1)정거장 지나옴" : "여기서 탔어요")
                        .font(.system(size: 13)).foregroundColor(.secondary)
                }
                node(kind: .current, isLast: false) {
                    Text(stops[cur]).font(.system(size: 15, weight: .bold)).foregroundColor(.primary)
                    Text("지금 여기쯤").font(.system(size: 13)).foregroundColor(.appBlue)
                }
            }
            upcomingNode(kind: .upcoming, remaining: remaining, mids: upMids)
        }
    }

    // MARK: 정적 타임라인(폴백) — 위치 정보 없을 때 기존 동작

    @ViewBuilder
    private func staticTimeline() -> some View {
        let mids = stops.count > 2 ? Array(stops[1..<lastIdx]) : []
        // 헤드라인(stopsCount)과 항상 같은 숫자를 쓴다 — 경유역 이름은 mids로 보조 표시.
        let remaining = remainingFallback
        VStack(spacing: 0) {
            node(kind: .passed, isLast: false) {
                Text(boardStop).font(.system(size: 15, weight: .semibold)).foregroundColor(.secondary)
                Text("여기서 탔어요").font(.system(size: 13)).foregroundColor(.secondary)
            }
            // 위치를 모를 땐 "앞으로" 노드에 펄스를 줘서 이동 중임을 표현 (기존 동작)
            upcomingNode(kind: .current, remaining: remaining, mids: mids)
        }
    }

    // MARK: 공통 노드

    enum NodeKind { case passed, current, upcoming }

    @ViewBuilder
    private func node<Content: View>(kind: NodeKind, isLast: Bool, @ViewBuilder content: () -> Content) -> some View {
        HStack(alignment: .top, spacing: 14) {
            VStack(spacing: 0) {
                dot(kind).padding(.top, 4)
                if !isLast {
                    Rectangle().fill(Color.appLine).frame(width: 2).frame(minHeight: 26)
                }
            }
            .frame(width: 16)
            VStack(alignment: .leading, spacing: 2, content: content)
                .padding(.bottom, isLast ? 0 : 18)
            Spacer()
        }
    }

    @ViewBuilder
    private func dot(_ kind: NodeKind) -> some View {
        switch kind {
        case .current:
            Circle().fill(Color.appBlue).frame(width: 12, height: 12)
                .overlay(Circle().stroke(Color.appBlue.opacity(0.18), lineWidth: 4).scaleEffect(1.7))
        case .passed:
            Circle().fill(Color.appBlue).frame(width: 12, height: 12)
        case .upcoming:
            Circle().fill(Color.appBlue).frame(width: 12, height: 12)
        }
    }

    // "앞으로 N 정거장" 노드 — 접고 펼치기 (마지막 노드)
    @ViewBuilder
    private func upcomingNode(kind: NodeKind, remaining: Int, mids: [String]) -> some View {
        node(kind: kind, isLast: true) {
            if remaining <= 0 {
                Text("곧 내려요").font(.system(size: 15, weight: .bold)).foregroundColor(.primary)
            } else if mids.isEmpty {
                Text("앞으로 \(remaining) 정거장").font(.system(size: 15, weight: .bold)).foregroundColor(.primary)
            } else {
                Button {
                    withAnimation(.spring(response: 0.32, dampingFraction: 0.85)) { expanded.toggle() }
                } label: {
                    HStack(spacing: 6) {
                        Text("앞으로 \(remaining) 정거장")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundColor(.primary)
                        Image(systemName: "chevron.down")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(.secondary)
                            .rotationEffect(.degrees(expanded ? 180 : 0))
                        Spacer(minLength: 0)
                    }
                }
                .buttonStyle(.plain)

                if expanded {
                    VStack(alignment: .leading, spacing: 11) {
                        ForEach(Array(mids.enumerated()), id: \.offset) { _, s in
                            HStack(spacing: 10) {
                                Circle()
                                    .fill(Color(.systemBackground))
                                    .frame(width: 7, height: 7)
                                    .overlay(Circle().stroke(Color(.systemGray3), lineWidth: 2))
                                Text(s)
                                    .font(.system(size: 14))
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                    .padding(.top, 11)
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
        }
    }
}

// MARK: - 지하철 가로 노선도 (ux_stage3_sub)
//
// 지나온 역 → 현재 위치(펄스) → 앞으로 갈 역들 → 하차역(강조)을 가로로. 호선색은 vehicle.lineColor.
//
// "지금 어디쯤?" — 지하철은 지하라 GPS가 약하고 실시간 차량위치 API도 없어서,
// 탑승 시각(boardedAt)부터의 경과시간 ÷ 총 소요시간으로 진행 위치를 "추정"한다.
// boardedAt/소요시간이 없으면 첫 역을 현재 위치로 두는 기존 동작으로 폴백.

struct SubwayRouteMap: View {
    let lineColor: Color
    let originName: String
    let exitName: String
    // 경유역 이름들(현재역 ~ 하차역 포함). 있으면 중간역 이름까지 표시, 없으면 정거장 수로 점만.
    var passStops: [String]? = nil
    let upcomingStops: Int
    // 진행 위치 추정용 — 탑승 시각, 이 구간 총 소요(분)
    var boardedAt: Date? = nil
    var totalRideMinutes: Int? = nil

    // 칸 레이아웃 상수 — 이름 2줄(34) + 간격(8) + 점 영역(36). 점 영역은 현재역 펄스링까지 안 잘리게 넉넉히.
    private let nameHeight: CGFloat = 34
    private let gap: CGFloat = 8
    private let dotZone: CGFloat = 36
    private let colWidth: CGFloat = 78

    // 표시할 역 이름 [탑승역, 중간역…, 하차역]. 이름 데이터가 있으면 그대로, 없으면 정거장 수만큼 빈 칸.
    private var names: [String] {
        if let ps = passStops, ps.count >= 2 {
            var arr = ps
            arr[0] = originName
            arr[arr.count - 1] = exitName
            return arr
        }
        return [originName] + Array(repeating: "", count: max(0, upcomingStops - 1)) + [exitName]
    }

    // 경과시간 기반 현재 위치 인덱스 추정 (0 = 탑승역). 데이터 없으면 0.
    private func currentIndex(now: Date) -> Int {
        let lastIdx = max(0, names.count - 1)
        guard let boarded = boardedAt, let total = totalRideMinutes, total > 0 else { return 0 }
        let elapsedMin = now.timeIntervalSince(boarded) / 60.0
        let frac = min(max(elapsedMin / Double(total), 0), 1)
        return Int((frac * Double(lastIdx)).rounded())
    }

    var body: some View {
        // 5초마다 다시 그려 진행 위치를 갱신
        TimelineView(.periodic(from: .now, by: 5)) { context in
            mapBody(current: currentIndex(now: context.date))
        }
        .frame(height: nameHeight + gap + dotZone)
    }

    private func mapBody(current: Int) -> some View {
        let lastIdx = max(0, names.count - 1)
        let lineTop = nameHeight + gap + dotZone / 2 - 3
        return ScrollView(.horizontal, showsIndicators: false) {
            ZStack(alignment: .leading) {
                // 기준선(전체, 옅게)
                Capsule()
                    .fill(lineColor.opacity(0.25))
                    .frame(height: 6)
                    .padding(.horizontal, colWidth / 2)
                    .padding(.top, lineTop)
                // 지나온 구간(진하게) — 탑승역 점부터 현재 위치 점까지
                Capsule()
                    .fill(lineColor)
                    .frame(width: CGFloat(min(current, lastIdx)) * colWidth, height: 6)
                    .padding(.leading, colWidth / 2)
                    .padding(.top, lineTop)

                HStack(spacing: 0) {
                    ForEach(Array(names.enumerated()), id: \.offset) { idx, n in
                        station(name: n, kind: kind(idx: idx, last: lastIdx, current: current))
                    }
                }
            }
        }
    }

    enum StationKind { case passed, current, upcoming, exit }

    private func kind(idx: Int, last: Int, current: Int) -> StationKind {
        if idx == last { return .exit }
        if idx < current { return .passed }
        if idx == current { return .current }
        return .upcoming
    }

    func station(name: String, kind: StationKind) -> some View {
        VStack(spacing: gap) {
            // 이름: 길어도 안 잘리도록 2줄 허용 + 살짝 축소. 점 쪽(아래)으로 정렬해 점 위치 고정.
            Text(name)
                .font(.system(size: kind == .current ? 12.5 : 11,
                              weight: kind == .upcoming || kind == .passed ? .regular : .bold))
                .foregroundColor(nameColor(kind))
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.8)
                .frame(width: colWidth, height: nameHeight, alignment: .bottom)

            dot(kind)
                .frame(height: dotZone)
        }
        .frame(width: colWidth)
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
        case .passed:
            Circle()
                .fill(lineColor)
                .frame(width: 12, height: 12)
                .overlay(Circle().stroke(Color(.systemBackground), lineWidth: 2.5))
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
        case .passed:   return lineColor.opacity(0.55)
        case .upcoming: return .secondary
        case .exit:     return .primary
        }
    }
}

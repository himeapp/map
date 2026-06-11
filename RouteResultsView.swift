import SwiftUI

// ① 전체 경로 (ux_stage1) — 완성된 경로(직통·버스환승·지하철환승)를
// 총 소요 짧은 순으로 다 보여주고, 어느 길로 갈지 고르는 "계획 단계" 화면.
// 실시간 "몇 분 후"는 여기선 안 띄운다(그건 ② 집중 화면에서).
struct RouteResultsView: View {
    @EnvironmentObject var vm: TransitViewModel

    // 숨긴 경로 제외 + 총 소요 짧은 순
    private var routes: [BoardableOption] {
        vm.boardableOptions
            .filter { !vm.excludedKeys.contains($0.exclusionKey) }
            .sorted { $0.totalMinutes < $1.totalMinutes }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            odCard
            Divider().opacity(0.4)

            if vm.isLoadingRoutes {
                loadingView
            } else {
                routeList
            }
        }
        .background(Color.appBg)
    }

    // MARK: - 헤더 (back + "경로 N개 · 빠른 순")

    var header: some View {
        HStack(spacing: 10) {
            Button(action: vm.goHome) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.primary)
                    .frame(width: 36, height: 36)
                    .background(Color(.systemBackground))
                    .clipShape(Circle())
            }
            Text(routes.isEmpty ? "경로 탐색" : "경로 \(routes.count)개 · 빠른 순")
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(.secondary)
                .lineLimit(1)
            Spacer()
            Button(action: { Task { await vm.fetchRoutes() } }) {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundColor(.secondary)
                    .frame(width: 36, height: 36)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, 4)
    }

    // MARK: - 출발/도착 카드

    var odCard: some View {
        VStack(spacing: 9) {
            HStack(spacing: 10) {
                Circle().fill(Color.appBlue).frame(width: 9, height: 9)
                Text("출발").font(.system(size: 12)).foregroundColor(.secondary)
                Text(vm.fromPlace?.name ?? "현재 위치")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.primary)
                    .lineLimit(1)
                Spacer()
            }
            HStack(spacing: 10) {
                Circle().fill(Color.appPurple).frame(width: 9, height: 9)
                Text("도착").font(.system(size: 12)).foregroundColor(.secondary)
                Text(vm.toPlace?.name ?? "")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundColor(.primary)
                    .lineLimit(1)
                Spacer()
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 13)
        .background(Color(.systemBackground), in: RoundedRectangle(cornerRadius: 14))
        .padding(.horizontal, 16)
        .padding(.top, 10)
        .padding(.bottom, 10)
    }

    // MARK: - 경로 리스트

    var routeList: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                if routes.isEmpty {
                    Text("탈 수 있는 경로가 없어요")
                        .font(.system(size: 14))
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity)
                        .padding(.top, 40)
                }

                ForEach(Array(routes.enumerated()), id: \.element.id) { idx, route in
                    RouteResultRow(route: route, isRecommended: idx == 0)
                        .contentShape(Rectangle())
                        .onTapGesture { vm.chooseRoute(route) }
                        .contextMenu {
                            Button(role: .destructive) { vm.excludeOption(route) } label: {
                                Label("이 경로 빼기", systemImage: "eye.slash")
                            }
                        }
                }

                if !vm.excludedKeys.isEmpty {
                    Button(action: vm.clearExclusions) {
                        Label("숨긴 경로 \(vm.excludedKeys.count)개 다시 보기", systemImage: "eye")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.secondary)
                    }
                    .padding(.top, 4)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 24)
        }
    }

    var loadingView: some View {
        VStack(spacing: 16) {
            Spacer()
            ProgressView().scaleEffect(1.2)
            Text("경로 찾는 중...").font(.system(size: 14)).foregroundColor(.secondary)
            Spacer()
        }
    }
}

// MARK: - 경로 한 줄 (총 소요 + 도착시각 + 여정 칩 + 출발지점)

struct RouteResultRow: View {
    let route: BoardableOption
    let isRecommended: Bool

    private static let clock: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "ko_KR")
        f.dateFormat = "a h:mm"
        return f
    }()

    // 도착 예정 시각 = 지금 + 총 소요 (계획 단계 추정)
    private var arrivalText: String {
        let arrival = Date().addingTimeInterval(Double(route.totalMinutes) * 60)
        return Self.clock.string(from: arrival)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // 총 소요 + 도착시각 + 추천 배지
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("\(route.totalMinutes)")
                    .font(.system(size: 26, weight: .heavy, design: .rounded))
                    .foregroundColor(.primary)
                + Text("분")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(.primary)

                Text("· \(arrivalText) 도착")
                    .font(.system(size: 12.5))
                    .foregroundColor(.secondary)

                Spacer(minLength: 6)

                if isRecommended {
                    Text("추천")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(.appBlue)
                        .padding(.horizontal, 9).padding(.vertical, 4)
                        .background(Color.appBlue.opacity(0.12), in: Capsule())
                }
            }

            // 여정 칩 (도보·탑승 구간 순서대로)
            JourneyStrip(legs: JourneyLeg.legs(of: route))

            // 출발 지점
            HStack(spacing: 6) {
                Image(systemName: "figure.walk")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.secondary)
                Text(departureText)
                    .font(.system(size: 12.5))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.systemBackground), in: RoundedRectangle(cornerRadius: 18))
        .overlay(
            RoundedRectangle(cornerRadius: 18)
                .stroke(isRecommended ? Color.appBlue.opacity(0.25) : Color.clear, lineWidth: 1.5)
        )
    }

    private var departureText: String {
        let stop = route.originStop?.name.isEmpty == false ? route.originStop!.name : "출발 정류장"
        if let w = route.walkToStopMinutes, w > 0 {
            return "\(stop) 출발 · 도보 \(w)분"
        }
        return "\(stop) 출발"
    }
}

// MARK: - 여정 한 구간

enum JourneyLeg: Identifiable {
    case walk(min: Int)
    case ride(vehicle: Vehicle, min: Int?)

    var id: String {
        switch self {
        case .walk(let m): return "w\(m)\(UUID().uuidString.prefix(4))"
        case .ride(let v, _): return "r\(v.id)"
        }
    }

    // BoardableOption(첫 수단 + afterSteps)을 표시용 구간 시퀀스로 펼친다.
    static func legs(of option: BoardableOption) -> [JourneyLeg] {
        var result: [JourneyLeg] = []
        // 출발지 → 첫 정류장 도보
        if let w = option.walkToStopMinutes, w > 0 {
            result.append(.walk(min: w))
        }
        // 첫 탑승 수단 (탑승 시간은 afterSteps 첫 .getOff 의 durationMinutes)
        let firstRide = option.afterSteps.first.flatMap {
            $0.type == .getOff ? $0.durationMinutes : nil
        }
        result.append(.ride(vehicle: option.vehicle, min: firstRide))
        // 이후 구간 (도보 / 환승 탑승)
        for step in option.afterSteps {
            switch step.type {
            case .walk:
                result.append(.walk(min: step.durationMinutes ?? 0))
            case .transfer:
                if let v = step.vehicle {
                    result.append(.ride(vehicle: v, min: step.durationMinutes))
                }
            default:
                break
            }
        }
        return result
    }
}

struct JourneyStrip: View {
    let legs: [JourneyLeg]

    var body: some View {
        // 칩이 한 줄에 안 들어가면 세로로 줄바꿈돼 "막대처럼" 깨지므로,
        // 가로 스크롤로 흘려서 칩은 항상 제 너비(lineLimit 1)를 유지한다.
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(Array(legs.enumerated()), id: \.offset) { i, leg in
                    if i > 0 {
                        Image(systemName: "chevron.compact.right")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(Color(.systemGray3))
                    }
                    legChip(leg)
                }
            }
            .padding(.vertical, 1)
        }
    }

    @ViewBuilder
    private func legChip(_ leg: JourneyLeg) -> some View {
        switch leg {
        case .walk(let m):
            HStack(spacing: 3) {
                Image(systemName: "figure.walk").font(.system(size: 10, weight: .bold))
                Text("\(m)분").font(.system(size: 12, weight: .semibold))
            }
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
            .foregroundColor(.secondary)
            .padding(.horizontal, 8).padding(.vertical, 4)
            .background(Color(.systemGray6), in: Capsule())

        case .ride(let vehicle, let m):
            HStack(spacing: 4) {
                Text(vehicle.number)
                    .font(.system(size: 12.5, weight: .heavy, design: .rounded))
                    .monospacedDigit()
                if let m, m > 0 {
                    Text("\(m)분").font(.system(size: 12, weight: .semibold)).opacity(0.85)
                }
            }
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
            .foregroundColor(.white)
            .padding(.horizontal, 9).padding(.vertical, 4)
            .background(vehicle.displayColor, in: Capsule())
        }
    }
}

import SwiftUI

struct WaitingView: View {
    @EnvironmentObject var vm: TransitViewModel
    // "탔어요" 1차 탭 상태 — 같은 행 다시 탭하면 탑승 확정
    @State private var pendingBoardID: UUID?

    var body: some View {
        VStack(spacing: 0) {
            header
            destBar
            Divider().opacity(0.4)

            if vm.isLoadingRoutes {
                loadingView
            } else {
                busOptionsList
            }
        }
        .background(Color.appBg)
    }

    // MARK: - 헤더 (back + "○○ 가는 중")

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
            Text("\(vm.toPlace?.name ?? "목적지") 가는 중")
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

    // MARK: - 도착지 바 (도착 ○○)

    var destBar: some View {
        HStack(spacing: 10) {
            Circle().fill(Color.appPurple).frame(width: 9, height: 9)
            Text("도착").font(.system(size: 12)).foregroundColor(.secondary)
            Text(vm.toPlace?.name ?? "")
                .font(.system(size: 16, weight: .bold))
                .foregroundColor(.primary)
                .lineLimit(1)
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 13)
        .background(Color(.systemBackground), in: RoundedRectangle(cornerRadius: 14))
        .padding(.horizontal, 16)
        .padding(.bottom, 10)
    }

    // MARK: - 버스 목록 (정류장 그룹별)

    var busOptionsList: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 22) {
                if vm.departureGroups.isEmpty {
                    Text("탈 수 있는 경로가 없어요")
                        .font(.system(size: 14))
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity)
                        .padding(.top, 40)
                }

                ForEach(Array(vm.departureGroups.enumerated()), id: \.element.id) { idx, group in
                    DepartureGroupSection(
                        group: group,
                        isLead: idx == 0,
                        pendingBoardID: $pendingBoardID
                    )
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
            .padding(.top, 6)
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

// MARK: - 출발 지점 섹션 (정류장 + 거기서 탈 수 있는 수단)

struct DepartureGroupSection: View {
    @EnvironmentObject var vm: TransitViewModel
    let group: DepartureGroup
    let isLead: Bool
    @Binding var pendingBoardID: UUID?

    var body: some View {
        VStack(alignment: .leading, spacing: 11) {
            // 정류장 헤더 — "여기로 가세요"
            HStack(spacing: 8) {
                ZStack {
                    Circle().fill(Color.appBlue).frame(width: 26, height: 26)
                    Image(systemName: "figure.walk")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(.white)
                }
                Text(group.stop.name.isEmpty ? "출발 정류장" : group.stop.name)
                    .font(.system(size: 19, weight: .bold))
                    .lineLimit(1)
                if let w = group.walkMinutes {
                    Button(action: { vm.walkToStop(group) }) {
                        HStack(spacing: 4) {
                            Image(systemName: "figure.walk")
                                .font(.system(size: 11, weight: .bold))
                            Text("도보 \(w)분")
                                .font(.system(size: 13, weight: .semibold))
                            Image(systemName: "chevron.right")
                                .font(.system(size: 9, weight: .bold))
                        }
                        .foregroundColor(.appBlue)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 4)
                        .background(Color.appBlue.opacity(0.12), in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
                Spacer()
                if isLead {
                    Text("고른 길").font(.system(size: 11, weight: .bold))
                        .foregroundColor(.secondary)
                }
            }

            // 버스/지하철 행 리스트 (HTML bus-list)
            VStack(spacing: 0) {
                ForEach(Array(group.options.enumerated()), id: \.element.id) { i, option in
                    if i > 0 { Divider().padding(.leading, 16) }
                    BusRow(
                        option: option,
                        isPick: isLead && i == 0,
                        isPending: pendingBoardID == option.id
                    )
                    .contentShape(Rectangle())
                    .onTapGesture { tap(option) }
                    .contextMenu {
                        Button(role: .destructive) { vm.excludeOption(option) } label: {
                            Label("이 경로 빼기", systemImage: "eye.slash")
                        }
                    }
                }
            }
            .background(Color(.systemBackground), in: RoundedRectangle(cornerRadius: 18))
            .overlay(
                RoundedRectangle(cornerRadius: 18)
                    .stroke(isLead ? Color.appBlue.opacity(0.25) : Color.clear, lineWidth: 1.5)
            )
        }
    }

    private func tap(_ option: BoardableOption) {
        if pendingBoardID == option.id {
            vm.boardVehicle(option)        // 2차 탭 → 탑승 확정
        } else {
            pendingBoardID = option.id     // 1차 탭 → "탔어요?" 표시
        }
    }
}

// MARK: - 버스 한 행 (HTML .bus-row)

struct BusRow: View {
    let option: BoardableOption
    let isPick: Bool
    let isPending: Bool

    var body: some View {
        HStack(spacing: 11) {
            // 등급별 색 번호 (tabular)
            Text(option.vehicle.number)
                .font(.system(size: 20, weight: .heavy, design: .rounded))
                .monospacedDigit()
                .foregroundColor(option.vehicle.displayColor)
                .frame(minWidth: 54, alignment: .leading)

            // 방향 / 경유
            VStack(alignment: .leading, spacing: 1) {
                Text(option.vehicle.headsign)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.primary)
                    .lineLimit(1)
                if !option.vehicle.via.isEmpty {
                    Text(option.vehicle.via)
                        .font(.system(size: 11.5))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 6)

            if isPending {
                // "탔어요?" 확인 칩
                Text("탔어요 👆")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 12).padding(.vertical, 7)
                    .background(Color.appBlue, in: Capsule())
                    .transition(.scale.combined(with: .opacity))
            } else {
                if isPick {
                    Text("추천")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(.appBlue)
                        .padding(.horizontal, 8).padding(.vertical, 2)
                        .background(Color.appBlue.opacity(0.14), in: Capsule())
                }
                ETABadge(minutes: option.arrivalMinutes, nextMinutes: option.nextArrivalMinutes)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(isPick ? Color.appBlue.opacity(0.06) : Color.clear)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isPending)
    }
}

// MARK: - 세그먼트 필 (다른 화면에서 재사용)

struct SegmentPill: View {
    let text: String
    let colorKey: String

    var bg: Color {
        switch colorKey {
        case "subway": return Color.appGreen.opacity(0.15)
        case "bus":    return Color.appBlue.opacity(0.15)
        default:       return Color(.tertiarySystemBackground)
        }
    }
    var fg: Color {
        switch colorKey {
        case "subway": return Color(hex: "#1f9e44")
        case "bus":    return .appBlue
        default:       return .secondary
        }
    }

    var body: some View {
        Text(text)
            .font(.system(size: 11, weight: .semibold))
            .foregroundColor(fg)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(bg)
            .clipShape(RoundedRectangle(cornerRadius: 7))
    }
}

struct SectionLabel: View {
    let text: String
    var body: some View {
        HStack {
            Text(text)
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(.secondary)
                .textCase(.uppercase)
                .tracking(0.5)
            Spacer()
        }
        .padding(.horizontal, 4)
        .padding(.top, 4)
    }
}

import SwiftUI

struct WaitingView: View {
    @EnvironmentObject var vm: TransitViewModel

    var body: some View {
        VStack(spacing: 0) {
            // MARK: - 헤더
            header

            Divider().opacity(0.15)

            // MARK: - 버스 목록
            if vm.isLoadingRoutes {
                loadingView
            } else {
                busOptionsList
            }
        }
        .background(Color(.systemBackground))
    }

    // MARK: - 헤더

    var header: some View {
        HStack(spacing: 10) {
            Button(action: vm.goHome) {
                Image(systemName: "arrow.left")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.primary)
                    .frame(width: 36, height: 36)
                    .background(Color(.secondarySystemBackground))
                    .clipShape(Circle())
            }

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Circle().fill(Color.blue).frame(width: 7, height: 7)
                    Text(vm.fromPlace?.name ?? "")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.primary)
                }
                HStack(spacing: 6) {
                    Circle().fill(Color.purple).frame(width: 7, height: 7)
                    Text(vm.toPlace?.name ?? "")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.primary)
                }
            }

            Spacer()

            // 새로고침
            Button(action: {
                Task { await vm.fetchRoutes() }
            }) {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundColor(.secondary)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }

    // MARK: - 버스 목록

    var busOptionsList: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 20) {
                if vm.departureGroups.isEmpty {
                    Text("탈 수 있는 경로가 없어요")
                        .font(.system(size: 14))
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity)
                        .padding(.top, 40)
                }

                // 출발 지점(정류장/역) 단위로 — 총 소요시간 짧은 순
                ForEach(vm.departureGroups) { group in
                    DepartureGroupSection(group: group)
                }

                // 숨긴 경로 되돌리기
                if !vm.excludedKeys.isEmpty {
                    Button(action: vm.clearExclusions) {
                        Label("숨긴 경로 \(vm.excludedKeys.count)개 다시 보기", systemImage: "eye")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.secondary)
                    }
                    .padding(.top, 4)
                }
            }
            .padding(.horizontal, 14)
            .padding(.top, 10)
            .padding(.bottom, 20)
        }
    }

    // MARK: - 로딩

    var loadingView: some View {
        VStack(spacing: 16) {
            Spacer()
            ProgressView()
                .scaleEffect(1.2)
            Text("경로 찾는 중...")
                .font(.system(size: 14))
                .foregroundColor(.secondary)
            Spacer()
        }
    }
}

// MARK: - 출발 지점 섹션 (정류장 + 거기서 탈 수 있는 수단들)

struct DepartureGroupSection: View {
    @EnvironmentObject var vm: TransitViewModel
    let group: DepartureGroup

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // 출발 지점 헤더 — "여기로 가세요"
            HStack(spacing: 8) {
                Image(systemName: "figure.walk")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(.blue)
                Text(group.stop.name.isEmpty ? "출발 정류장" : group.stop.name)
                    .font(.system(size: 16, weight: .bold))
                    .lineLimit(1)
                if let w = group.walkMinutes {
                    Text("도보 \(w)분")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.blue)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Color.blue.opacity(0.12), in: Capsule())
                }
                Spacer()
                Text("최소 \(group.bestTotalMinutes)분")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }

            // 거기서 탈 수 있는 수단들
            ForEach(group.options) { option in
                BoardableCard(option: option, isBoardable: (option.arrivalMinutes ?? .max) <= 10)
                    .onTapGesture { vm.boardVehicle(option) }
                    .contextMenu {
                        Button(role: .destructive) {
                            vm.excludeOption(option)
                        } label: {
                            Label("이 경로 빼기", systemImage: "eye.slash")
                        }
                    }
            }
        }
    }
}

// MARK: - 버스 카드

struct BoardableCard: View {
    let option: BoardableOption
    let isBoardable: Bool

    var arrivalColor: Color {
        guard let m = option.arrivalMinutes else { return .secondary }
        if m <= 2 { return .green }
        if m <= 5 { return .orange }
        return .primary
    }

    var body: some View {
        VStack(spacing: 0) {
            // 탑승 가능 표시 바
            if isBoardable {
                Rectangle()
                    .fill(Color.green)
                    .frame(height: 2)
            }

            VStack(spacing: 10) {
                // MARK: 상단: 번호 + 방향 + 도착시간
                HStack(alignment: .top, spacing: 10) {
                    // 번호
                    Text(option.vehicle.number)
                        .font(.system(size: 22, weight: .bold, design: .rounded))
                        .foregroundColor(isBoardable ? .blue : .secondary)
                        .frame(minWidth: 52, alignment: .leading)

                    // 방향/경유
                    VStack(alignment: .leading, spacing: 3) {
                        Text(option.vehicle.headsign)
                            .font(.system(size: 13, weight: .semibold))
                        if !option.vehicle.via.isEmpty {
                            Text(option.vehicle.via)
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                        }
                    }

                    Spacer()

                    // 도착 시간
                    VStack(alignment: .trailing, spacing: 2) {
                        if let m = option.arrivalMinutes {
                            HStack(alignment: .lastTextBaseline, spacing: 2) {
                                Text("\(m)")
                                    .font(.system(size: 28, weight: .bold, design: .rounded))
                                    .foregroundColor(arrivalColor)
                                Text("분 후")
                                    .font(.system(size: 12))
                                    .foregroundColor(.secondary)
                            }
                        } else {
                            // 실시간 도착정보 아직 없음
                            HStack(alignment: .lastTextBaseline, spacing: 2) {
                                Text("—")
                                    .font(.system(size: 28, weight: .bold, design: .rounded))
                                    .foregroundColor(.secondary)
                                Text("분")
                                    .font(.system(size: 12))
                                    .foregroundColor(.secondary)
                            }
                        }
                        if let next = option.nextArrivalMinutes {
                            Text("다음 \(next)분")
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                        }
                    }
                }

                // MARK: 하단: 이후 경로 한 줄 미리보기 + 총 소요
                HStack(spacing: 4) {
                    ForEach(Array(previewSegments.enumerated()), id: \.offset) { i, seg in
                        if i > 0 {
                            Image(systemName: "chevron.right")
                                .font(.system(size: 9))
                                .foregroundColor(.secondary.opacity(0.5))
                        }
                        SegmentPill(text: seg.text, colorKey: seg.colorKey)
                    }
                    Spacer()
                    Text("총 \(option.totalMinutes)분")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
        }
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(isBoardable ? Color.green.opacity(0.3) : Color.clear, lineWidth: 0.5)
        )
    }

    // afterSteps에서 이후 경로 세그먼트 추출
    var previewSegments: [(text: String, colorKey: String)] {
        option.afterSteps.compactMap { step in
            switch step.type {
            case .walk:
                return (text: "도보 \(step.durationMinutes ?? 0)분", colorKey: "walk")
            case .board:
                let n = step.vehicle?.number ?? ""
                let s = step.stopsCount.map { " \($0)정거장" } ?? ""
                return (text: n + s, colorKey: step.vehicle?.type == .subway ? "subway" : "bus")
            case .transfer:
                return (text: "환승", colorKey: "walk")
            case .arrive:
                return nil
            case .getOff:
                return nil
            }
        }
    }
}

// MARK: - 세그먼트 필

struct SegmentPill: View {
    let text: String
    let colorKey: String

    var bg: Color {
        switch colorKey {
        case "subway": return Color.green.opacity(0.15)
        case "bus":    return Color.blue.opacity(0.15)
        default:       return Color(.tertiarySystemBackground)
        }
    }
    var fg: Color {
        switch colorKey {
        case "subway": return Color(red: 0.23, green: 0.62, blue: 0.27)
        case "bus":    return Color.blue
        default:       return Color.secondary
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

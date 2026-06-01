import SwiftUI

// MARK: - 탑승 후 View

struct OnboardView: View {
    @EnvironmentObject var vm: TransitViewModel

    var body: some View {
        guard let option = vm.selectedOption else { return AnyView(EmptyView()) }
        return AnyView(
            VStack(spacing: 0) {
                onboardHeader(option: option)
                Divider().opacity(0.15)
                currentVehicleCard(option: option)
                Divider().opacity(0.1)
                afterStepsList(option: option)
            }
            .background(Color(.systemBackground))
        )
    }

    // MARK: - 헤더

    func onboardHeader(option: BoardableOption) -> some View {
        HStack(spacing: 12) {
            Button(action: vm.exitOnboard) {
                Image(systemName: "arrow.left")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.primary)
                    .frame(width: 36, height: 36)
                    .background(Color(.secondarySystemBackground))
                    .clipShape(Circle())
            }
            VStack(alignment: .leading, spacing: 2) {
                Text("\(option.vehicle.number)번 탑승 중")
                    .font(.system(size: 18, weight: .bold))
                Text(vm.toPlace?.name ?? "")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
            }
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }

    // MARK: - 현재 탑승 카드

    func currentVehicleCard(option: BoardableOption) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(option.vehicle.number)
                    .font(.system(size: 26, weight: .bold, design: .rounded))
                Text(option.afterSteps.first(where: { $0.type == .getOff })?.title ?? "하차 정보")
                    .font(.system(size: 13))
                    .opacity(0.88)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                if let stops = option.afterSteps.first?.stopsCount {
                    Text("\(stops)")
                        .font(.system(size: 32, weight: .bold, design: .rounded))
                    Text("정거장 남음")
                        .font(.system(size: 11))
                        .opacity(0.8)
                }
            }
        }
        .foregroundColor(.white)
        .padding(.horizontal, 18)
        .padding(.vertical, 16)
        .background(Color.blue)
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }

    // MARK: - 이후 경로 스텝

    func afterStepsList(option: BoardableOption) -> some View {
        ScrollView {
            VStack(spacing: 0) {
                ForEach(Array(option.afterSteps.enumerated()), id: \.element.id) { i, step in
                    StepRow(
                        step: step,
                        isLast: i == option.afterSteps.count - 1
                    )
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
    }
}

// MARK: - 경로 스텝 행

struct StepRow: View {
    let step: RouteStep
    let isLast: Bool

    var dotColor: Color {
        switch step.type {
        case .getOff:   return .orange
        case .walk:     return Color(.systemGray3)
        case .transfer: return .orange
        case .board:    return .green
        case .arrive:   return .purple
        }
    }

    var lineColor: Color {
        switch step.type {
        case .getOff:   return Color(.systemGray5)
        case .walk:     return Color(.systemGray5)
        case .transfer: return Color(.systemGray5)
        case .board:    return Color.green.opacity(0.4)
        case .arrive:   return Color.clear
        }
    }

    var badgeStyle: (bg: Color, fg: Color, icon: String) {
        switch step.type {
        case .getOff:
            return (Color.orange.opacity(0.12), Color.orange, "arrow.down.circle")
        case .walk:
            return (Color(.tertiarySystemBackground), Color.secondary, "figure.walk")
        case .transfer:
            return (Color.orange.opacity(0.12), Color.orange, "arrow.triangle.2.circlepath")
        case .board:
            return (Color.green.opacity(0.12), Color(red: 0.23, green: 0.62, blue: 0.27), "tram.fill")
        case .arrive:
            return (Color.purple.opacity(0.12), Color.purple, "flag.fill")
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            // 타임라인 라인 + 점
            VStack(spacing: 0) {
                Circle()
                    .fill(dotColor)
                    .frame(width: 12, height: 12)
                    .padding(.top, 4)
                if !isLast {
                    Rectangle()
                        .fill(lineColor)
                        .frame(width: 2)
                        .frame(minHeight: 40)
                }
            }
            .frame(width: 20)

            // 내용
            VStack(alignment: .leading, spacing: 5) {
                Text(step.title)
                    .font(.system(size: 15, weight: .semibold))

                if !step.description.isEmpty {
                    Text(step.description)
                        .font(.system(size: 13))
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                // 세부 정보 (출구번호, 방향 등)
                if let detail = step.detail {
                    Text(detail)
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }

                // 배지
                let style = badgeStyle
                HStack(spacing: 5) {
                    Image(systemName: style.icon)
                        .font(.system(size: 12))
                    Text(badgeText)
                        .font(.system(size: 12, weight: .semibold))
                }
                .foregroundColor(style.fg)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(style.bg)
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }
            .padding(.bottom, isLast ? 0 : 20)

            Spacer()
        }
    }

    var badgeText: String {
        switch step.type {
        case .getOff:
            return "하차"
        case .walk:
            if let d = step.durationMinutes { return "도보 \(d)분" }
            return "도보"
        case .transfer:
            return "환승"
        case .board:
            let num = step.vehicle?.number ?? ""
            let stops = step.stopsCount.map { " · \($0)정거장" } ?? ""
            return num + stops
        case .arrive:
            return "목적지 도착"
        }
    }
}

// MARK: - 경로 타임라인 (하단 탭용)

struct RouteTimeline: View {
    let steps: [RouteStep]
    @Binding var selectedIndex: Int

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 0) {
                ForEach(Array(steps.enumerated()), id: \.element.id) { i, step in
                    HStack(spacing: 0) {
                        // 노드
                        VStack(spacing: 4) {
                            Circle()
                                .strokeBorder(nodeColor(step), lineWidth: 2)
                                .background(
                                    Circle().fill(i == selectedIndex ? nodeColor(step) : Color(.systemBackground))
                                )
                                .frame(width: 13, height: 13)
                                .scaleEffect(i == selectedIndex ? 1.35 : 1.0)
                                .animation(nil, value: selectedIndex)  // 애니메이션 없음

                            Text(stepShortName(step))
                                .font(.system(size: 9, weight: i == selectedIndex ? .bold : .regular))
                                .foregroundColor(i == selectedIndex ? .primary : .secondary)
                                .frame(maxWidth: 54)
                                .multilineTextAlignment(.center)
                                .lineLimit(2)
                        }
                        .onTapGesture { selectedIndex = i }

                        // 라인
                        if i < steps.count - 1 {
                            Rectangle()
                                .fill(lineColor(step))
                                .frame(width: 36, height: 2)
                                .padding(.bottom, 18)
                        }
                    }
                }
            }
            .padding(.horizontal, 16)
        }
    }

    func nodeColor(_ step: RouteStep) -> Color {
        switch step.type {
        case .getOff: return .orange
        case .walk: return Color(.systemGray3)
        case .transfer: return .orange
        case .board: return .green
        case .arrive: return .purple
        }
    }

    func lineColor(_ step: RouteStep) -> Color {
        switch step.type {
        case .board: return Color.green.opacity(0.5)
        default: return Color(.systemGray5)
        }
    }

    func stepShortName(_ step: RouteStep) -> String {
        switch step.type {
        case .getOff: return "하차"
        case .walk: return "도보"
        case .transfer: return "환승"
        case .board: return step.vehicle?.number ?? "탑승"
        case .arrive: return "도착"
        }
    }
}

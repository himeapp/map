import SwiftUI

// MARK: - 환승 도보 View (ux_transfer)
//
// 멀티 leg 경로에서 하차 후 다음 정류소까지 걷는 구간. 다음 탑승은 아직 안 보임.
// "○○ 하차 완료" 배너 + 회색 점선 도보 타임라인. "정류소 도착" → ② 대기 화면으로.

struct TransferView: View {
    @EnvironmentObject var vm: TransitViewModel

    var body: some View {
        let option = vm.selectedOption
        VStack(spacing: 0) {
            header
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    doneBanner(option: option)
                    walkHead(option: option)
                    timeline(option: option)
                    arrivedButton
                        .padding(.top, 16)
                }
                .padding(.horizontal, 18)
                .padding(.top, 8)
                .padding(.bottom, 24)
            }
        }
        .background(Color.appBg)
    }

    // MARK: - 헤더

    var header: some View {
        HStack(spacing: 10) {
            Button(action: { vm.appState = .onboard }) {
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
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 10)
        .overlay(Divider(), alignment: .bottom)
    }

    // MARK: - 하차 완료 배너

    func doneBanner(option: BoardableOption?) -> some View {
        let num = option?.vehicle.number ?? ""
        let stop = getoffName(option)
        return HStack(spacing: 10) {
            ZStack {
                Circle().fill(Color.appGreen).frame(width: 32, height: 32)
                Image(systemName: "checkmark")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundColor(.white)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text("\(num)번 하차 완료")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(.primary)
                Text("\(stop) · 환승 지점")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14).padding(.vertical, 12)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 14))
        .padding(.top, 8)
        .padding(.bottom, 16)
    }

    // MARK: - 환승 도보 헤드라인

    func walkHead(option: BoardableOption?) -> some View {
        let next = transferStopName(option)
        let mins = transferWalkMinutes(option)
        return VStack(alignment: .leading, spacing: 6) {
            Text("\(next)(으)로")
                .font(.system(size: 24, weight: .heavy))
                .foregroundColor(.primary)
            if let to = transferToText(option) {
                Text(to)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundColor(.appOrange)
            }
            Text(mins.map { "약 \($0)분 · 도보 이동" } ?? "도보 이동")
                .font(.system(size: 14))
                .foregroundColor(.secondary)
        }
        .padding(.bottom, 16)
    }

    // MARK: - 다음에 탈 수단 + 방면 ("2호선 성수행으로 환승해요")
    //
    // 같은 노선도 방향이 둘이라, 방면(way)을 "○○행"으로 보여줘 헷갈림을 줄인다.

    private func transferToText(_ option: BoardableOption?) -> String? {
        guard let v = option?.afterSteps.first(where: { $0.type == .transfer })?.vehicle else {
            return nil
        }
        let name = v.type == .bus ? "\(v.number)번" : v.number
        if let dir = directionLabel(v.headsign) {
            return "\(name) \(dir)\(josaRo(dir)) 환승해요"
        }
        return "\(name)\(josaRo(name)) 환승해요"
    }

    // MARK: - 세로 타임라인 (하차 → 걷는 중 → 도착 정류소)

    func timeline(option: BoardableOption?) -> some View {
        let from = getoffName(option)
        let to = transferStopName(option)
        return VStack(spacing: 0) {
            transferRow(
                dotColor: .appGreen, filled: true, dashed: false,
                title: from, sub: "하차 완료", isLast: false
            ) { EmptyView() }
            transferRow(
                dotColor: .appBlue, filled: true, dashed: true,
                title: "걷는 중", sub: "다음 정류소로 이동 중", isLast: false
            ) { EmptyView() }
            transferRow(
                dotColor: Color(.systemGray3), filled: false, dashed: false,
                title: "", sub: "", isLast: true
            ) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("도착 정류소")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(.secondary)
                    Text(to)
                        .font(.system(size: 18, weight: .heavy))
                        .foregroundColor(.primary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 14).padding(.vertical, 11)
                .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 14))
                .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color(.systemGray4), lineWidth: 1.5))
            }
        }
    }

    @ViewBuilder
    func transferRow<Content: View>(
        dotColor: Color, filled: Bool, dashed: Bool,
        title: String, sub: String, isLast: Bool,
        @ViewBuilder content: () -> Content
    ) -> some View {
        HStack(alignment: .top, spacing: 14) {
            VStack(spacing: 0) {
                Circle()
                    .fill(filled ? dotColor : Color(.systemBackground))
                    .frame(width: 12, height: 12)
                    .overlay(Circle().stroke(dotColor, lineWidth: filled ? 0 : 2))
                    .padding(.top, 4)
                if !isLast {
                    if dashed {
                        DashedLine().stroke(Color(.systemGray3), style: StrokeStyle(lineWidth: 2, dash: [3, 4]))
                            .frame(width: 2).frame(minHeight: 40)
                    } else {
                        Rectangle().fill(Color.appLine).frame(width: 2).frame(minHeight: 40)
                    }
                }
            }
            .frame(width: 16)

            VStack(alignment: .leading, spacing: 2) {
                if !title.isEmpty {
                    Text(title).font(.system(size: 16, weight: .bold)).foregroundColor(.primary)
                }
                if !sub.isEmpty {
                    Text(sub).font(.system(size: 13)).foregroundColor(.secondary)
                }
                content()
            }
            .padding(.bottom, isLast ? 0 : 18)
            Spacer(minLength: 0)
        }
    }

    // MARK: - "정류소 도착" 선언

    var arrivedButton: some View {
        Button(action: vm.arriveAtTransferStop) {
            Text("정류소에 도착했어요")
                .font(.system(size: 16, weight: .bold))
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 15)
                .background(Color.appBlue, in: RoundedRectangle(cornerRadius: 16))
        }
        .buttonStyle(.plain)
    }

    // MARK: - 헬퍼

    private func getoffName(_ option: BoardableOption?) -> String {
        if let g = option?.afterSteps.first(where: { $0.type == .getOff }) {
            let t = g.title.replacingOccurrences(of: "에서 하차", with: "")
            if !t.isEmpty { return t }
        }
        return "환승 정류소"
    }

    private func transferStopName(_ option: BoardableOption?) -> String {
        if let t = option?.afterSteps.first(where: { $0.type == .transfer }) {
            if !t.title.isEmpty { return t.title }
        }
        // 환승 후 다음 탑승 스텝의 위치
        if let b = option?.afterSteps.drop(while: { $0.type != .transfer }).first(where: { $0.type == .board }) {
            if !b.title.isEmpty { return b.title }
        }
        return "다음 정류소"
    }

    private func transferWalkMinutes(_ option: BoardableOption?) -> Int? {
        option?.afterSteps.first(where: { $0.type == .transfer || $0.type == .walk })?.durationMinutes
    }
}

// MARK: - 점선 세로선

struct DashedLine: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: rect.midX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
        return p
    }
}

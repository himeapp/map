import SwiftUI

// MARK: - 도착 완료 View (ux_arrive)
//
// 트리거: OnboardView의 "도착했어요" 탭 → vm.arrive(). 차량 추적 중단 후 이 화면으로.
// 내용: 초록 체크 히어로 + 여정 요약 카드 + 미니 타임라인 + "새 목적지 검색"/"즐겨찾기 추가".

struct ArriveView: View {
    @EnvironmentObject var vm: TransitViewModel

    var body: some View {
        let option = vm.selectedOption
        let arrivedAt = vm.arrivedAt ?? Date()
        let totalMinutes = option?.totalMinutes
        let departedAt = totalMinutes.map { arrivedAt.addingTimeInterval(TimeInterval(-$0 * 60)) }

        VStack(spacing: 0) {
            header
            ScrollView {
                VStack(spacing: 14) {
                    hero
                    summaryCard(option: option, departedAt: departedAt, arrivedAt: arrivedAt, totalMinutes: totalMinutes)
                    journeyMini(option: option)
                    actions
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 24)
            }
        }
        .background(Color.appBg)
    }

    // MARK: - 헤더 (미니멀)

    var header: some View {
        HStack {
            Spacer()
            Button(action: { vm.goHome(); vm.startSearch(target: .to) }) {
                Image(systemName: "arrow.right")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.primary)
                    .frame(width: 38, height: 38)
                    .background(Color(.secondarySystemBackground))
                    .clipShape(Circle())
            }
        }
        .padding(.horizontal, 18)
        .padding(.top, 8)
        .padding(.bottom, 10)
    }

    // MARK: - 도착 히어로

    var hero: some View {
        VStack(spacing: 0) {
            ZStack {
                Circle().fill(Color.appGreen).frame(width: 80, height: 80)
                Circle().stroke(Color.appGreen.opacity(0.15), lineWidth: 12).frame(width: 92, height: 92)
                Circle().stroke(Color.appGreen.opacity(0.06), lineWidth: 12).frame(width: 116, height: 116)
                Image(systemName: "checkmark")
                    .font(.system(size: 36, weight: .bold))
                    .foregroundColor(.white)
            }
            .padding(.bottom, 20)

            Text("도착했어요!")
                .font(.system(size: 26, weight: .heavy))
                .foregroundColor(.primary)
                .padding(.bottom, 6)

            Text(vm.toPlace?.name ?? "목적지")
                .font(.system(size: 15))
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 24)
        .padding(.bottom, 12)
    }

    // MARK: - 여정 요약 카드

    func summaryCard(option: BoardableOption?, departedAt: Date?, arrivedAt: Date, totalMinutes: Int?) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("이번 여정 요약")
                .font(.system(size: 12, weight: .bold))
                .foregroundColor(.secondary)
                .textCase(.uppercase)
                .padding(.bottom, 12)

            if let m = totalMinutes {
                summaryRow(key: "총 소요 시간", value: "\(m)분")
            }
            summaryRow(
                key: "출발",
                value: "\(departedAt.map(Self.timeText) ?? "—") · \(vm.fromPlace?.name ?? "현재 위치")"
            )
            summaryRow(
                key: "도착",
                value: "\(Self.timeText(arrivedAt)) · \(vm.toPlace?.name ?? "도착지")"
            )
            if let v = option?.vehicle {
                summaryRow(key: "이용한 교통수단", value: "\(vehicleLabel(v.type)) \(v.number)")
            }
            if let walk = option?.walkToStopMinutes, walk > 0 {
                summaryRow(key: "도보", value: "약 \(walk)분", isLast: true)
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.systemBackground), in: RoundedRectangle(cornerRadius: 20))
        .shadow(color: .black.opacity(0.06), radius: 4, y: 1)
    }

    func summaryRow(key: String, value: String, isLast: Bool = false) -> some View {
        VStack(spacing: 0) {
            HStack {
                Text(key).font(.system(size: 13)).foregroundColor(.secondary)
                Spacer()
                Text(value).font(.system(size: 14, weight: .bold)).foregroundColor(.primary)
            }
            .padding(.vertical, 10)
            if !isLast { Divider() }
        }
    }

    // MARK: - 미니 여정 타임라인

    func journeyMini(option: BoardableOption?) -> some View {
        let originName = option?.originStop?.name ?? "정류소"
        let getoffName = option?.afterSteps.first(where: { $0.type == .getOff })?
            .title.replacingOccurrences(of: "에서 하차", with: "") ?? "하차"

        return VStack(alignment: .leading, spacing: 0) {
            Text("경로")
                .font(.system(size: 12, weight: .bold))
                .foregroundColor(.secondary)
                .textCase(.uppercase)
                .padding(.bottom, 14)

            HStack(spacing: 0) {
                miniNode(color: .appBlue, label: "현재\n위치")
                miniSeg(gradient: [.appBlue, .appGreen], flex: 1)
                miniNode(color: .appGreen, label: shorten(originName))
                miniSeg(gradient: [.appGreen, .appGreen], flex: 2)
                miniNode(color: .appGreen, label: shorten(getoffName))
                miniSeg(gradient: [.appGreen, .appGreen], flex: 1)
                miniNode(color: .appGreen, label: "도착", emphasized: true)
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.systemBackground), in: RoundedRectangle(cornerRadius: 20))
        .shadow(color: .black.opacity(0.06), radius: 4, y: 1)
    }

    func miniNode(color: Color, label: String, emphasized: Bool = false) -> some View {
        VStack(spacing: 5) {
            Circle()
                .fill(color)
                .frame(width: emphasized ? 14 : 10, height: emphasized ? 14 : 10)
                .overlay(emphasized ? Circle().stroke(Color(.systemBackground), lineWidth: 2) : nil)
            Text(label)
                .font(.system(size: 11, weight: emphasized ? .bold : .regular))
                .foregroundColor(emphasized ? .appGreen : .secondary)
                .multilineTextAlignment(.center)
                .lineLimit(2)
        }
        .frame(width: 56)
    }

    func miniSeg(gradient: [Color], flex: CGFloat) -> some View {
        LinearGradient(colors: gradient, startPoint: .leading, endPoint: .trailing)
            .frame(height: 3)
            .clipShape(Capsule())
            .frame(maxWidth: .infinity)
            .layoutPriority(Double(flex))
            .padding(.bottom, 22) // 노드 라벨 높이만큼 위로 정렬
    }

    // MARK: - 액션 버튼

    var actions: some View {
        VStack(spacing: 10) {
            Button(action: { vm.goHome(); vm.startSearch(target: .to) }) {
                Text("새 목적지 검색")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 17)
                    .background(Color.appBlue, in: RoundedRectangle(cornerRadius: 16))
            }
            .buttonStyle(.plain)

            if let dest = vm.toPlace, !isSaved(dest) {
                Button(action: { saveFavorite(dest) }) {
                    HStack(spacing: 8) {
                        Image(systemName: "star")
                        Text("즐겨찾기에 추가")
                    }
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.primary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 15)
                    .background(Color(.systemBackground), in: RoundedRectangle(cornerRadius: 16))
                    .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.appLine, lineWidth: 1))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.top, 6)
    }

    // MARK: - 헬퍼

    private func isSaved(_ place: Place) -> Bool {
        vm.savedPlaces.contains { $0.name == place.name && $0.address == place.address }
    }

    private func saveFavorite(_ place: Place) {
        let fav = Place(
            name: place.name, address: place.address,
            coordinate: place.coordinate, category: .favorite
        )
        vm.savePlace(fav)
    }

    private func vehicleLabel(_ type: VehicleType) -> String {
        switch type {
        case .bus: return "버스"
        case .subway: return "지하철"
        case .walk: return "도보"
        }
    }

    private func shorten(_ name: String) -> String {
        name.count > 5 ? String(name.prefix(4)) + "…" : name
    }

    static func timeText(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "ko_KR")
        f.dateFormat = "H:mm"
        return f.string(from: date)
    }
}

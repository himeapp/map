import SwiftUI

// MARK: - 정류소까지 도보 안내 View (ux_stage_walk)
//
// ① 경로 선택 → ② 정류소 대기 사이. 지도(뒤 HomeView) 위에 하단 모달로 도보 안내.
// 실제 턴바이턴은 위치 서비스 연동 후. 현재는 도보 시간/목표 정류소·버스 ETA 요약 + "정류소 도착" 선언.

struct WalkToStopView: View {
    @EnvironmentObject var vm: TransitViewModel

    var body: some View {
        let group = vm.walkingGroup
        VStack(spacing: 0) {
            handle
            VStack(spacing: 0) {
                directionHeader(group: group)
                progressBar
                Divider().padding(.vertical, 14)
                stopRow(group: group)
                arrivedButton
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 24)
        }
        .background(Color(.systemBackground))
    }

    var handle: some View {
        Capsule()
            .fill(Color(.systemGray4))
            .frame(width: 36, height: 4)
            .padding(.top, 10)
            .padding(.bottom, 12)
    }

    // MARK: - 방향 + ETA

    func directionHeader(group: DepartureGroup?) -> some View {
        let minutes = group?.walkMinutes ?? 0
        return HStack(alignment: .top) {
            HStack(spacing: 12) {
                ZStack {
                    Circle().fill(Color.appBlue).frame(width: 46, height: 46)
                    Image(systemName: "arrow.up")
                        .font(.system(size: 20, weight: .heavy))
                        .foregroundColor(.white)
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text("정류소로 이동")
                        .font(.system(size: 20, weight: .heavy))
                        .foregroundColor(.primary)
                    Text(group?.stop.name.isEmpty == false ? "\(group!.stop.name) 방향" : "출발 정류소 방향")
                        .font(.system(size: 13))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 2) {
                HStack(alignment: .firstTextBaseline, spacing: 2) {
                    Text("\(minutes)")
                        .font(.system(size: 32, weight: .heavy))
                        .foregroundColor(.primary)
                    Text("분")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.secondary)
                }
                Text("도보 거리")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
            }
        }
        .padding(.bottom, 16)
    }

    // MARK: - 진행 바 (현재는 시작 지점)

    var progressBar: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.appLine).frame(height: 5)
                Capsule().fill(Color.appBlue).frame(width: geo.size.width * 0.15, height: 5)
            }
        }
        .frame(height: 5)
    }

    // MARK: - 목표 정류소 + 버스 ETA

    func stopRow(group: DepartureGroup?) -> some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 12).fill(Color.appBlue.opacity(0.1)).frame(width: 40, height: 40)
                Image(systemName: "bus.fill")
                    .font(.system(size: 18))
                    .foregroundColor(.appBlue)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(group?.stop.name.isEmpty == false ? group!.stop.name : "탑승 정류소")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundColor(.primary)
                    .lineLimit(1)
                Text("탑승 정류소")
                    .font(.system(size: 12.5))
                    .foregroundColor(.secondary)
            }
            Spacer(minLength: 6)
            VStack(alignment: .trailing, spacing: 3) {
                ForEach(Array((group?.options ?? []).prefix(2))) { opt in
                    busChip(opt)
                }
            }
        }
        .padding(.bottom, 16)
    }

    func busChip(_ opt: BoardableOption) -> some View {
        let tier = ArrivalTier(minutes: opt.arrivalMinutes)
        let text = opt.arrivalMinutes.map { "\(opt.vehicle.number) · \($0)분 후" } ?? opt.vehicle.number
        return Text(text)
            .font(.system(size: 12, weight: .bold))
            .foregroundColor(tier == .none ? .secondary : tier.color)
            .padding(.horizontal, 9).padding(.vertical, 3)
            .background((tier == .none ? Color.secondary : tier.color).opacity(0.12), in: Capsule())
    }

    // MARK: - "정류소 도착" 선언

    var arrivedButton: some View {
        Button(action: vm.arriveAtStop) {
            Text("정류소에 도착했어요")
                .font(.system(size: 16, weight: .bold))
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 15)
                .background(Color.appBlue, in: RoundedRectangle(cornerRadius: 16))
        }
        .buttonStyle(.plain)
    }
}

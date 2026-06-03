import SwiftUI

// MARK: - 경로 이탈 재탐색 View (ux_reroute)
//
// 트리거: 경로 이탈 감지(현재는 OnboardView 긴급카드에서 수동 진입).
// 출발 = 현재 위치(원래 출발지 유지), 도착 = 그대로. "다시 탐색" → 현 시점 경로 재조회.

struct RerouteView: View {
    @EnvironmentObject var vm: TransitViewModel

    var body: some View {
        VStack(spacing: 0) {
            handle
            ScrollView {
                VStack(spacing: 0) {
                    alertBanner
                    odCard
                    buttons
                }
                .padding(.bottom, 24)
            }
        }
        .background(Color.appBg)
    }

    var handle: some View {
        Capsule()
            .fill(Color(.systemGray4))
            .frame(width: 36, height: 4)
            .padding(.top, 10)
            .padding(.bottom, 4)
    }

    // MARK: - 이탈 알림 배너

    var alertBanner: some View {
        HStack(spacing: 11) {
            ZStack {
                Circle().fill(Color.appRed).frame(width: 36, height: 36)
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(.white)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text("경로를 벗어났어요")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundColor(.appRed)
                Text("현재 위치에서 다시 길을 찾아드릴게요")
                    .font(.system(size: 12.5))
                    .foregroundColor(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 15)
        .padding(.vertical, 13)
        .background(Color.appRed.opacity(0.08), in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.appRed.opacity(0.22), lineWidth: 1.5))
        .padding(.horizontal, 16)
        .padding(.top, 16)
    }

    // MARK: - 출발/도착 카드

    var odCard: some View {
        VStack(spacing: 0) {
            odRow(
                dot: .appBlue, label: "출발",
                name: vm.fromPlace?.name ?? "현재 위치",
                badge: "현위치", badgeColor: .appBlue, dimmed: true
            )
            Divider().padding(.leading, 54)
            odRow(
                dot: .appPurple, label: "도착",
                name: vm.toPlace?.name ?? "목적지",
                badge: "그대로", badgeColor: .appPurple, dimmed: false
            )
        }
        .padding(.vertical, 4)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 18))
        .padding(.horizontal, 16)
        .padding(.top, 14)
    }

    func odRow(dot: Color, label: String, name: String, badge: String, badgeColor: Color, dimmed: Bool) -> some View {
        HStack(spacing: 12) {
            Circle().fill(dot).frame(width: 10, height: 10)
            Text(label)
                .font(.system(size: 11.5))
                .foregroundColor(.secondary)
                .frame(width: 28, alignment: .leading)
            Text(name)
                .font(.system(size: dimmed ? 14 : 16, weight: dimmed ? .semibold : .bold))
                .foregroundColor(dimmed ? .secondary : .primary)
                .lineLimit(1)
            Spacer(minLength: 6)
            Text(badge)
                .font(.system(size: 11, weight: .bold))
                .foregroundColor(badgeColor)
                .padding(.horizontal, 8).padding(.vertical, 3)
                .background(badgeColor.opacity(0.12), in: Capsule())
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 13)
    }

    // MARK: - 버튼

    var buttons: some View {
        VStack(spacing: 10) {
            Button(action: vm.confirmReroute) {
                HStack(spacing: 8) {
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .font(.system(size: 16, weight: .bold))
                    Text("지금 위치에서 다시 탐색")
                        .font(.system(size: 17, weight: .bold))
                }
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(Color.appBlue, in: RoundedRectangle(cornerRadius: 16))
            }
            .buttonStyle(.plain)

            Button(action: vm.cancelReroute) {
                Text("뒤로 가기")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.top, 14)
    }
}

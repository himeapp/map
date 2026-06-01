import SwiftUI

// MARK: - 인터시티 (시외/고속/열차) 시간표 화면
//
// 시내 대기 화면(WaitingView)과 다른 모델:
//  - 시내: "지금 탈 수 있는 것" (분 단위 카운트다운)
//  - 인터시티: "정해진 시간표" (출발 시각 기반)
//
// 흐름: 탭 선택 → 출발 도시 선택 → 도착 도시 선택 → 시간표 표시

struct IntercityView: View {
    @EnvironmentObject var vm: TransitViewModel

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().opacity(0.15)
            tabBar
            Divider().opacity(0.1)
            citySelectors
            Divider().opacity(0.1)
            if vm.isLoadingIntercity {
                loadingView
            } else if vm.intercityOptions.isEmpty {
                emptyView
            } else {
                scheduleList
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
            Text("도시 간 이동")
                .font(.system(size: 16, weight: .bold))
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }

    // MARK: - 탭

    var tabBar: some View {
        HStack(spacing: 0) {
            ForEach([IntercityVehicleType.expressBus, .suburbBus, .train], id: \.self) { type in
                TabButton(
                    label: type.label,
                    icon: type.icon,
                    isSelected: vm.intercityTab == type,
                    action: { vm.setIntercityTab(type) }
                )
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }

    // MARK: - 출/도착 도시 선택

    var citySelectors: some View {
        VStack(spacing: 8) {
            CityPickerRow(
                dotColor: .blue,
                placeholder: "출발 도시",
                selected: vm.intercityOrigin,
                options: vm.intercityOriginOptions,
                onSelect: vm.selectIntercityOrigin
            )
            CityPickerRow(
                dotColor: .purple,
                placeholder: "도착 도시",
                selected: vm.intercityDest,
                options: vm.intercityDestOptions,
                onSelect: vm.selectIntercityDest,
                disabled: vm.intercityOrigin == nil
            )
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    // MARK: - 결과

    var scheduleList: some View {
        ScrollView {
            LazyVStack(spacing: 8) {
                ForEach(vm.intercityOptions) { opt in
                    IntercityCard(option: opt)
                }
            }
            .padding(.horizontal, 14)
            .padding(.top, 8)
            .padding(.bottom, 20)
        }
    }

    var loadingView: some View {
        VStack(spacing: 12) {
            Spacer()
            ProgressView()
            Text("시간표 불러오는 중...")
                .font(.system(size: 13))
                .foregroundColor(.secondary)
            Spacer()
        }
    }

    var emptyView: some View {
        VStack(spacing: 8) {
            Spacer()
            Image(systemName: vm.intercityOrigin == nil ? "mappin.and.ellipse" : "magnifyingglass")
                .font(.system(size: 28))
                .foregroundColor(.secondary.opacity(0.6))
            Text(emptyMessage)
                .font(.system(size: 13))
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
            Spacer()
        }
        .padding(.horizontal, 30)
    }

    var emptyMessage: String {
        if vm.intercityOrigin == nil { return "출발 도시를 골라주세요" }
        if vm.intercityDest == nil { return "도착 도시를 골라주세요" }
        return "해당 노선의 시간표가 없습니다"
    }
}

// MARK: - 탭 버튼

private struct TabButton: View {
    let label: String
    let icon: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                HStack(spacing: 5) {
                    Image(systemName: icon)
                        .font(.system(size: 13, weight: .semibold))
                    Text(label)
                        .font(.system(size: 14, weight: .semibold))
                }
                .foregroundColor(isSelected ? .blue : .secondary)

                Rectangle()
                    .fill(isSelected ? Color.blue : Color.clear)
                    .frame(height: 2)
            }
        }
        .frame(maxWidth: .infinity)
        .buttonStyle(.plain)
    }
}

// MARK: - 도시 픽커 (Menu 베이스)

private struct CityPickerRow: View {
    let dotColor: Color
    let placeholder: String
    let selected: IntercityCity?
    let options: [IntercityCity]
    let onSelect: (IntercityCity) -> Void
    var disabled: Bool = false

    var body: some View {
        Menu {
            ForEach(options) { city in
                Button(city.name) { onSelect(city) }
            }
        } label: {
            HStack(spacing: 10) {
                Circle()
                    .fill(dotColor)
                    .frame(width: 9, height: 9)
                Text(selected?.name ?? placeholder)
                    .font(.system(size: 15, weight: selected != nil ? .semibold : .regular))
                    .foregroundColor(selected != nil ? .primary : .secondary)
                Spacer()
                Image(systemName: "chevron.down")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(Color(.secondarySystemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .disabled(disabled || options.isEmpty)
        .opacity(disabled ? 0.5 : 1.0)
    }
}

// MARK: - 시간표 카드

struct IntercityCard: View {
    let option: IntercityOption

    static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        f.locale = Locale(identifier: "ko_KR_POSIX")
        return f
    }()

    var depString: String { Self.timeFormatter.string(from: option.departureTime) }
    var arrString: String { Self.timeFormatter.string(from: option.arrivalTime) }

    var durationString: String {
        let h = option.durationMinutes / 60
        let m = option.durationMinutes % 60
        if h > 0 { return "\(h)시간 \(m)분" }
        return "\(m)분"
    }

    var fareString: String? {
        guard let f = option.fare, f > 0 else { return nil }
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        return (formatter.string(from: NSNumber(value: f)) ?? "\(f)") + "원"
    }

    var gradeColor: Color {
        if option.grade.contains("우등") || option.grade.contains("KTX") {
            return Color.purple
        }
        return Color.blue
    }

    var body: some View {
        VStack(spacing: 10) {
            // 등급 + 가격
            HStack {
                Text(option.grade)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(gradeColor)
                    .clipShape(Capsule())
                Spacer()
                if let fare = fareString {
                    Text(fare)
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundColor(.primary)
                }
            }

            // 시간
            HStack(alignment: .center, spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(depString)
                        .font(.system(size: 22, weight: .bold, design: .rounded))
                    Text(option.originTerminal)
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }

                VStack(spacing: 2) {
                    Text(durationString)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.secondary)
                    Rectangle()
                        .fill(Color.secondary.opacity(0.4))
                        .frame(height: 1)
                    Image(systemName: option.type.icon)
                        .font(.system(size: 9))
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity)

                VStack(alignment: .trailing, spacing: 2) {
                    Text(arrString)
                        .font(.system(size: 22, weight: .bold, design: .rounded))
                    Text(option.destTerminal)
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }
}

// MARK: - Hashable for IntercityVehicleType

extension IntercityVehicleType: Hashable {}

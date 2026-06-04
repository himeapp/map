import ActivityKit
import WidgetKit
import SwiftUI

// MARK: - 이동 중 Live Activity (다이내믹 아일랜드 + 잠금화면)
//
// TransitActivityAttributes.ContentState 를 받아 표시. 텍스트/색은 모두 앱(VM)에서
// 만들어 넘겨준 값을 그대로 그린다. 위젯은 판단하지 않고 표시만 한다.

struct TransitLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: TransitActivityAttributes.self) { context in
            // 잠금화면 / 배너
            LockScreenView(state: context.state, destination: context.attributes.destination)
                .padding(16)
                .activityBackgroundTint(Color.black.opacity(0.9))
                .activitySystemActionForegroundColor(.white)
        } dynamicIsland: { context in
            let s = context.state
            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Image(systemName: phaseIcon(s.phase))
                        .font(.title2)
                        .foregroundColor(hexColor(s.lineColorHex))
                }
                DynamicIslandExpandedRegion(.trailing) {
                    if let m = s.minutes {
                        VStack(alignment: .trailing, spacing: 0) {
                            Text("\(m)").font(.title).bold().monospacedDigit()
                            Text("분").font(.caption2).foregroundColor(.secondary)
                        }
                    } else {
                        Image(systemName: "figure.walk")
                            .font(.title3)
                            .foregroundColor(.secondary)
                    }
                }
                DynamicIslandExpandedRegion(.center) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(s.headline).font(.headline).lineLimit(1)
                        Text(s.detail).font(.caption).foregroundColor(.secondary).lineLimit(1)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    HStack(spacing: 4) {
                        Image(systemName: "mappin.and.ellipse").font(.caption2)
                        Text(context.attributes.destination).font(.caption)
                    }
                    .foregroundColor(.secondary)
                }
            } compactLeading: {
                Image(systemName: phaseIcon(s.phase))
                    .foregroundColor(hexColor(s.lineColorHex))
            } compactTrailing: {
                if let m = s.minutes {
                    Text("\(m)분").font(.caption).bold().monospacedDigit()
                } else {
                    Image(systemName: "figure.walk")
                }
            } minimal: {
                Image(systemName: phaseIcon(s.phase))
                    .foregroundColor(hexColor(s.lineColorHex))
            }
            .widgetURL(URL(string: "himemap://"))
        }
    }
}

// MARK: - 잠금화면 뷰

private struct LockScreenView: View {
    let state: TransitActivityAttributes.ContentState
    let destination: String

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle().fill(hexColor(state.lineColorHex).opacity(0.18))
                Image(systemName: phaseIcon(state.phase))
                    .font(.title2)
                    .foregroundColor(hexColor(state.lineColorHex))
            }
            .frame(width: 46, height: 46)

            VStack(alignment: .leading, spacing: 3) {
                Text(state.headline)
                    .font(.headline)
                    .foregroundColor(.white)
                    .lineLimit(1)
                HStack(spacing: 4) {
                    Text(state.detail)
                    Text("·")
                    Image(systemName: "mappin.and.ellipse")
                    Text(destination)
                }
                .font(.caption)
                .foregroundColor(.white.opacity(0.7))
                .lineLimit(1)
            }

            Spacer(minLength: 4)

            if let m = state.minutes {
                VStack(spacing: 0) {
                    Text("\(m)").font(.title).bold().monospacedDigit().foregroundColor(.white)
                    Text("분").font(.caption2).foregroundColor(.white.opacity(0.7))
                }
            }
        }
    }
}

// MARK: - 표시 헬퍼

private func phaseIcon(_ phase: TransitActivityAttributes.ContentState.Phase) -> String {
    switch phase {
    case .waiting:  return "clock.fill"
    case .onboard:  return "bus.fill"
    case .transfer: return "arrow.triangle.swap"
    }
}

// 위젯 타깃엔 Theme.swift가 없으므로 자체 hex 파서 사용.
private func hexColor(_ hex: String) -> Color {
    var s = hex.trimmingCharacters(in: .whitespacesAndNewlines)
    if s.hasPrefix("#") { s.removeFirst() }
    guard s.count == 6, let v = UInt64(s, radix: 16) else { return .gray }
    return Color(
        red:   Double((v >> 16) & 0xFF) / 255,
        green: Double((v >> 8) & 0xFF) / 255,
        blue:  Double(v & 0xFF) / 255
    )
}

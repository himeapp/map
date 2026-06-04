import SwiftUI

// MARK: - HTML 기획서 색상 토큰 (ux_*.html :root 변수와 동일)

extension Color {
    init(hex: String) {
        let h = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        var int: UInt64 = 0
        Scanner(string: h).scanHexInt64(&int)
        let r, g, b, a: UInt64
        switch h.count {
        case 8: (r, g, b, a) = (int >> 24 & 0xFF, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        case 6: (r, g, b, a) = (int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF, 255)
        default: (r, g, b, a) = (0, 0, 0, 255)
        }
        self.init(.sRGB,
                  red: Double(r) / 255, green: Double(g) / 255,
                  blue: Double(b) / 255, opacity: Double(a) / 255)
    }

    // 기획서 팔레트
    static let appBlue   = Color(hex: "#0a84ff")
    static let appGreen  = Color(hex: "#34c759")
    static let appOrange = Color(hex: "#ff9f0a")
    static let appPurple = Color(hex: "#bf5af2")
    static let appRed    = Color(hex: "#ff3b30")
    static let appLine   = Color(hex: "#e9e9ed")
    static let appSec    = Color(hex: "#8a8a8e")
    static let appBg     = Color(hex: "#f2f2f7")

    // 버스 번호 등급별 색 (간선=파랑 / 지선=초록 / 광역=빨강)
    static let busTrunk  = Color(hex: "#0a84ff")
    static let busBranch = Color(hex: "#00b14f")
    static let busWide   = Color(hex: "#ff3b30")
}

// MARK: - 실시간 도착 분 → 색 (곧=초록 / 중간=주황 / 늦음=기본)

enum ArrivalTier {
    case soon, mid, late, none

    init(minutes: Int?) {
        guard let m = minutes else { self = .none; return }
        if m <= 2 { self = .soon }
        else if m <= 5 { self = .mid }
        else { self = .late }
    }

    var color: Color {
        switch self {
        case .soon: return .appGreen
        case .mid:  return .appOrange
        case .late: return .primary
        case .none: return .secondary
        }
    }
}

// MARK: - 차량 번호 표시 색 (모델 lineColor 우선, 없으면 등급 추정)

extension Vehicle {
    var displayColor: Color {
        switch type {
        case .subway: return Color(hex: lineColor)
        case .walk:   return .appSec
        case .bus:
            if busType != nil { return Color(hex: lineColor) }
            // 자릿수 기반 보조 추정 (색약 보조 채널)
            switch number.count {
            case 0...3: return .busTrunk
            default:    return number.hasPrefix("9") ? .busWide : .busBranch
            }
        }
    }
}

// MARK: - 다이나믹 아일랜드 (상단 알약형 상태 표시)

struct DynamicIslandPill: View {
    var dotColor: Color
    var text: String

    var body: some View {
        HStack(spacing: 7) {
            Circle().fill(dotColor).frame(width: 7, height: 7)
            Text(text)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.white)
                .lineLimit(1)
        }
        .padding(.horizontal, 14)
        .frame(height: 36)
        .background(Color.black, in: Capsule())
        .shadow(color: .black.opacity(0.25), radius: 8, y: 2)
    }
}

// MARK: - 도착 ETA 배지

struct ETABadge: View {
    let minutes: Int?
    var nextMinutes: Int? = nil

    var body: some View {
        let tier = ArrivalTier(minutes: minutes)
        VStack(alignment: .trailing, spacing: 1) {
            if let m = minutes {
                Text(m <= 0 ? "곧 도착" : "\(m)분 후")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(tier.color)
            } else {
                Text("—분")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(.secondary)
            }
            if let n = nextMinutes {
                Text("다음 \(n)분")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }
        }
    }
}

// MARK: - 한글 텍스트 헬퍼 (조사·방면 라벨)

/// 받침에 맞는 '로/으로' 조사. 받침 없음 또는 ㄹ받침 → "로", 그 외 → "으로".
/// 한글이 아닌 끝글자는 "로"로 둔다.
func josaRo(_ word: String) -> String {
    guard let last = word.unicodeScalars.last else { return "로" }
    let v = last.value
    guard v >= 0xAC00 && v <= 0xD7A3 else { return "로" }
    let jong = (v - 0xAC00) % 28
    return (jong == 0 || jong == 8) ? "로" : "으로"
}

/// ODsay way(방면) 원문을 "○○행" 형태로 정규화. 빈 값이면 nil.
/// "성수", "성수방면", "성수방향", "성수행" 모두 "성수행"으로.
func directionLabel(_ raw: String?) -> String? {
    var s = (raw ?? "").trimmingCharacters(in: .whitespaces)
    for suffix in ["방면", "방향", "행"] where s.hasSuffix(suffix) {
        s = String(s.dropLast(suffix.count)).trimmingCharacters(in: .whitespaces)
    }
    guard !s.isEmpty else { return nil }
    return s + "행"
}

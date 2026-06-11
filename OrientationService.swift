import Foundation
import CoreLocation

// MARK: - 방향 잡기 (간판 → 좌표 → 방위각)
//
// 원리: GPS 는 "내 위치 P"를 알지만 나침반은 지하철 출구·빌딩 근처에서 매우 부정확하다.
// 사용자가 정면 간판을 읽으면, 그 간판의 정확한 좌표 S 를 카카오 로컬에서 찾는다.
//   - bearing(P → S) = 내가 바라보는 방향 (간판은 내 정면에 있으니까)
//   - bearing(P → 목적지 D) = 가야 할 방향
//   - 둘의 차이 = "왼쪽/오른쪽/직진/뒤로" 안내
// 추가로 이 순간의 나침반값을 함께 캡처하면 보정(calibration)이 가능해, 이후 몸을 돌릴 때
// 실시간 화살표가 정확히 따라온다 (OrientationView 참고).

struct SignCandidate: Identifiable {
    let id = UUID()
    let name: String
    let address: String
    let coordinate: Coordinate
    let distance: Double  // 사용자 위치로부터 거리(m)
}

struct OrientationResult {
    let sign: SignCandidate
    let userHeading: Double      // 내가 바라보는 방위각 (= 간판 방향, 0=북 90=동)
    let targetBearing: Double    // 목적지 방위각
    let relativeAngle: Double    // 정면 대비 목적지 상대각 (-180~180, +오른쪽)
    let instruction: String      // 큰 글씨 안내: "왼쪽으로 도세요"
    let detail: String           // 보조 설명
}

enum OrientationService {

    /// 두 좌표 사이 방위각 (0=북, 90=동, 180=남, 270=서).
    static func bearing(from a: Coordinate, to b: Coordinate) -> Double {
        let lat1 = a.lat * .pi / 180, lat2 = b.lat * .pi / 180
        let dLon = (b.lng - a.lng) * .pi / 180
        let y = sin(dLon) * cos(lat2)
        let x = cos(lat1) * sin(lat2) - sin(lat1) * cos(lat2) * cos(dLon)
        return (atan2(y, x) * 180 / .pi + 360).truncatingRemainder(dividingBy: 360)
    }

    /// 읽은 간판 텍스트로 근처 후보 장소를 검색해 거리순 정렬.
    static func candidates(for text: String, near user: Coordinate) async -> [SignCandidate] {
        let cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return [] }

        let places = (try? await KakaoTransitService.shared.searchPlacesNear(
            query: cleaned, lat: user.lat, lng: user.lng, radius: 1000)) ?? []

        let here = CLLocation(latitude: user.lat, longitude: user.lng)
        return places
            .map { p -> SignCandidate in
                let d = here.distance(from: CLLocation(latitude: p.coordinate.lat, longitude: p.coordinate.lng))
                return SignCandidate(name: p.name, address: p.address, coordinate: p.coordinate, distance: d)
            }
            // 같은 이름이 멀리 또 있어도(동명 매장) 눈앞 간판일 리 없으니 제외
            .filter { $0.distance < 600 }
            .sorted { $0.distance < $1.distance }
    }

    /// 사용자·간판·목적지로부터 방향 안내 계산.
    static func result(user: Coordinate, sign: SignCandidate, target: Coordinate) -> OrientationResult {
        let userHeading = bearing(from: user, to: sign.coordinate)
        let targetBearing = bearing(from: user, to: target)
        let rel = normalize(targetBearing - userHeading)
        let (instruction, detail) = phrase(for: rel)
        return OrientationResult(
            sign: sign, userHeading: userHeading, targetBearing: targetBearing,
            relativeAngle: rel, instruction: instruction, detail: detail
        )
    }

    /// 각도를 -180~180 범위로.
    static func normalize(_ deg: Double) -> Double {
        var a = deg.truncatingRemainder(dividingBy: 360)
        if a > 180 { a -= 360 }
        if a < -180 { a += 360 }
        return a
    }

    /// 상대각 → 길치도 바로 알아듣는 안내 문구.
    static func phrase(for rel: Double) -> (instruction: String, detail: String) {
        let a = abs(rel)
        let side = rel >= 0 ? "오른쪽" : "왼쪽"
        switch a {
        case ..<20:
            return ("앞으로 직진", "지금 보는 간판 쪽으로 그대로 걸어가세요")
        case ..<65:
            return ("\(side) 앞으로", "간판을 기준으로 \(side) 앞 비스듬한 방향이에요")
        case ..<115:
            return ("\(side)으로 도세요", "몸을 \(side)으로 90도 돌린 방향이에요")
        case ..<160:
            return ("\(side) 뒤로", "거의 뒤쪽이에요. \(side) 뒤로 돌아서 가세요")
        default:
            return ("뒤로 돌아서", "지금 보는 간판의 정반대 방향이에요")
        }
    }
}

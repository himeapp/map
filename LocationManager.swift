import Foundation
import CoreLocation
import Combine

// MARK: - 위치 관리자
//
// 기본 지도앱에서 "내 위치" 표시·재중앙(recenter)에 사용.
// 권한 요청 + 현재 좌표 publish. 경로 안내 중 자동 트리거(도착/이탈)는 추후 이 좌표를 활용.
// 핵심 UX: 탑승/하차 판단엔 절대 쓰지 않음(유저 선언 유지).

@MainActor
final class LocationManager: NSObject, ObservableObject {
    static let shared = LocationManager()

    private let manager = CLLocationManager()

    @Published var authorization: CLAuthorizationStatus
    @Published var current: CLLocationCoordinate2D?

    /// 권한이 막혀 설정에서 켜야 하는 상태인지
    var isDenied: Bool {
        authorization == .denied || authorization == .restricted
    }

    override init() {
        authorization = manager.authorizationStatus
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyNearestTenMeters
    }

    /// 현재 위치에서 주어진 좌표까지 거리(m). 위치를 모르면 nil.
    func distance(to coord: Coordinate) -> CLLocationDistance? {
        guard let cur = current else { return nil }
        let here = CLLocation(latitude: cur.latitude, longitude: cur.longitude)
        let there = CLLocation(latitude: coord.lat, longitude: coord.lng)
        return here.distance(from: there)
    }

    /// 권한 요청 + 위치 갱신 시작 (홈 진입 시 호출)
    func start() {
        switch authorization {
        case .notDetermined:
            manager.requestWhenInUseAuthorization()
        case .authorizedWhenInUse, .authorizedAlways:
            manager.startUpdatingLocation()
        default:
            break
        }
    }
}

extension LocationManager: CLLocationManagerDelegate {
    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        Task { @MainActor in
            self.authorization = status
            if status == .authorizedWhenInUse || status == .authorizedAlways {
                manager.startUpdatingLocation()
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let loc = locations.last else { return }
        let coord = loc.coordinate
        Task { @MainActor in
            self.current = coord
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        // 위치 실패는 조용히 무시 (지도는 기본 위치 유지)
    }
}

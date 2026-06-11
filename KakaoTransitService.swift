import Foundation

// MARK: - 카카오 로컬 API (장소 검색만 담당)
//
// 대중교통 경로는 ODsayService, 실시간 버스 도착은 RealtimeBusService 참고.
// 카카오 모빌리티는 공개 REST 대중교통 경로 API가 없어 자동차 길찾기 코드는 제거함.
//
// 카카오 API 키는 Info.plist에 KAKAO_API_KEY 로 넣으세요.

final class KakaoTransitService {
    static let shared = KakaoTransitService()
    private init() {}

    private var apiKey: String {
        Bundle.main.infoDictionary?["KAKAO_API_KEY"] as? String ?? ""
    }

    private let session = URLSession.shared

    // MARK: - 장소 검색

    func searchPlaces(query: String) async throws -> [Place] {
        var components = URLComponents(string: "https://dapi.kakao.com/v2/local/search/keyword.json")!
        components.queryItems = [
            URLQueryItem(name: "query", value: query),
            URLQueryItem(name: "size", value: "15")
        ]
        var request = URLRequest(url: components.url!)
        request.setValue("KakaoAK \(apiKey)", forHTTPHeaderField: "Authorization")

        let (data, _) = try await session.data(for: request)
        let response = try JSONDecoder().decode(KakaoPlaceResponse.self, from: data)

        return response.documents.map(Self.place(from:))
    }

    /// 현재 위치 중심 반경 검색 (간판 읽기 방향 잡기용). 가까운 순으로 정렬돼 옴.
    func searchPlacesNear(query: String, lat: Double, lng: Double, radius: Int = 1000) async throws -> [Place] {
        var components = URLComponents(string: "https://dapi.kakao.com/v2/local/search/keyword.json")!
        components.queryItems = [
            URLQueryItem(name: "query", value: query),
            URLQueryItem(name: "x", value: String(lng)),
            URLQueryItem(name: "y", value: String(lat)),
            URLQueryItem(name: "radius", value: String(min(max(radius, 1), 20000))),
            URLQueryItem(name: "sort", value: "distance"),
            URLQueryItem(name: "size", value: "15")
        ]
        var request = URLRequest(url: components.url!)
        request.setValue("KakaoAK \(apiKey)", forHTTPHeaderField: "Authorization")

        let (data, _) = try await session.data(for: request)
        let response = try JSONDecoder().decode(KakaoPlaceResponse.self, from: data)
        return response.documents.map(Self.place(from:))
    }

    private static func place(from doc: KakaoPlace) -> Place {
        Place(
            name: doc.place_name,
            address: doc.road_address_name.isEmpty ? doc.address_name : doc.road_address_name,
            coordinate: Coordinate(lat: Double(doc.y) ?? 0, lng: Double(doc.x) ?? 0)
        )
    }
}

// MARK: - Kakao Local Response

struct KakaoPlaceResponse: Codable {
    let documents: [KakaoPlace]
}

struct KakaoPlace: Codable {
    let place_name: String
    let address_name: String
    let road_address_name: String
    let x: String  // lng
    let y: String  // lat
}

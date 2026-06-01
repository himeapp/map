import Foundation

// MARK: - TAGO 지하철 정적정보 (역사/노선)
//
// API: SubwayInfoService
// 실시간 도착정보는 없음 (그건 SeoulSubwayRealtimeService 또는 지역별 별도 API).
// 여기는 "어느 역이 몇 호선이고 어디 있나" 정도의 정적 데이터.
//
// 사용처:
//  - 검색창에 "강남역" 치면 카카오 결과보다 정확한 역 정보 제공
//  - RouteStep 의 지하철 옵션에 정확한 노선 컬러/이름 보강
//  - 환승역 출구 정보 (향후)
//
// 키: Info.plist 의 DATA_GO_KR_KEY (TAGO 통합 키)

final class SubwayInfoService {
    static let shared = SubwayInfoService()
    private init() {}

    private var serviceKey: String {
        Bundle.main.infoDictionary?["DATA_GO_KR_KEY"] as? String ?? ""
    }

    private let session = URLSession.shared
    private let apiBase = "https://apis.data.go.kr/1613000/SubwayInfoService"

    // 노선 정보 캐시 — 한 번 받아서 메모리에 둠
    private var cachedLines: [SubwayLine]?

    // MARK: - 키워드로 역 검색

    func searchStations(keyword: String) async throws -> [SubwayStation] {
        var components = URLComponents(string: "\(apiBase)/getKwrdFndSubwaySttnList")!
        components.queryItems = [
            URLQueryItem(name: "serviceKey", value: serviceKey),
            URLQueryItem(name: "subwayStationName", value: keyword),
            URLQueryItem(name: "numOfRows", value: "30"),
            URLQueryItem(name: "pageNo", value: "1"),
            URLQueryItem(name: "_type", value: "json")
        ]
        let req = URLRequest(url: components.url!)
        let (data, _) = try await session.data(for: req)
        let response = try JSONDecoder().decode(TagoSubwayStationResponse.self, from: data)

        let items = response.response?.body?.items?.itemList ?? []
        return items.compactMap { item in
            guard let id = item.subwayStationId, let name = item.subwayStationName else { return nil }
            return SubwayStation(
                id: id,
                name: name,
                lineId: item.subwayRouteName.flatMap { _ in item.subwayStationId } ?? id,
                lineName: item.subwayRouteName ?? ""
            )
        }
    }

    // MARK: - 노선 목록 (캐시)

    func fetchAllLines() async throws -> [SubwayLine] {
        if let cached = cachedLines { return cached }

        var components = URLComponents(string: "\(apiBase)/getSubwayRouteInfoAll")!
        components.queryItems = [
            URLQueryItem(name: "serviceKey", value: serviceKey),
            URLQueryItem(name: "numOfRows", value: "200"),
            URLQueryItem(name: "pageNo", value: "1"),
            URLQueryItem(name: "_type", value: "json")
        ]
        let req = URLRequest(url: components.url!)
        let (data, _) = try await session.data(for: req)
        let response = try JSONDecoder().decode(TagoSubwayLineResponse.self, from: data)

        let items = response.response?.body?.items?.itemList ?? []
        let lines = items.compactMap { item -> SubwayLine? in
            guard let id = item.subwayRouteId, let name = item.subwayRouteName else { return nil }
            return SubwayLine(id: id, name: name)
        }
        cachedLines = lines
        return lines
    }
}

// MARK: - 도메인 모델

struct SubwayStation: Identifiable {
    let id: String          // 역 ID (subwayStationId)
    let name: String        // "강남"
    let lineId: String      // 노선 ID
    let lineName: String    // "수도권2호선"
}

struct SubwayLine: Identifiable {
    let id: String
    let name: String
}

// MARK: - TAGO 응답

struct TagoSubwayStationResponse: Decodable {
    let response: TagoResponse<TagoSubwayStationItem>?
}

struct TagoSubwayStationItem: Decodable {
    let subwayStationId: String?
    let subwayStationName: String?
    let subwayRouteName: String?
}

struct TagoSubwayLineResponse: Decodable {
    let response: TagoResponse<TagoSubwayLineItem>?
}

struct TagoSubwayLineItem: Decodable {
    let subwayRouteId: String?
    let subwayRouteName: String?
}

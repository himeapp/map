import Foundation

// MARK: - TAGO 버스위치정보 (실시간 차량 좌표)
//
// 노선의 모든 운행 중인 차량의 위치를 가져와서 지도에 핀으로 표시.
// OnboardView에서 "내가 탄 271번 지금 어디 있나" 같은 시각화에 사용.
//
// 키: Info.plist 의 DATA_GO_KR_KEY (TAGO 통합 키)
// API: BusLcInfoInqireService

final class BusPositionService {
    static let shared = BusPositionService()
    private init() {}

    private var serviceKey: String {
        Bundle.main.infoDictionary?["DATA_GO_KR_KEY"] as? String ?? ""
    }

    private let session = URLSession.shared

    // MARK: - 노선별 차량 위치 목록

    func fetchBusPositions(cityCode: Int, routeId: String) async throws -> [BusPosition] {
        var components = URLComponents(string: "https://apis.data.go.kr/1613000/BusLcInfoInqireService/getRouteAcctoBusLcList")!
        components.queryItems = [
            URLQueryItem(name: "serviceKey", value: serviceKey),
            URLQueryItem(name: "cityCode", value: String(cityCode)),
            URLQueryItem(name: "routeId", value: routeId),
            URLQueryItem(name: "numOfRows", value: "50"),
            URLQueryItem(name: "pageNo", value: "1"),
            URLQueryItem(name: "_type", value: "json")
        ]
        let request = URLRequest(url: components.url!)

        let (data, _) = try await session.data(for: request)
        let response = try JSONDecoder().decode(TagoBusPositionResponse.self, from: data)

        let items = response.response?.body?.items?.itemList ?? []
        let now = Date()
        return items.compactMap { item in
            guard let lat = item.gpslati, let lng = item.gpslong else { return nil }
            return BusPosition(
                id: item.vehicleno ?? "\(item.nodeid ?? "")-\(item.nodeord ?? 0)",
                routeNo: item.routenm ?? "",
                coordinate: Coordinate(lat: lat, lng: lng),
                lastStopName: item.nodenm,
                nextStopName: nil,
                updatedAt: now
            )
        }
    }
}

// MARK: - TAGO 응답

struct TagoBusPositionResponse: Decodable {
    let response: TagoResponse<TagoBusPositionItem>?
}

struct TagoBusPositionItem: Decodable {
    let gpslati: Double?           // 차량 위도
    let gpslong: Double?           // 차량 경도
    let nodeid: String?            // 직전 정류장 ID
    let nodenm: String?            // 직전 정류장명
    let nodeord: Int?              // 정류장 순번
    let routenm: String?           // 노선번호
    let routetp: String?           // 노선유형
    let vehicleno: String?         // 차량번호
}

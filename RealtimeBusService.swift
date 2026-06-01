import Foundation

// MARK: - 국토부 TAGO 실시간 버스 도착 정보
//
// 공공데이터포털 "국토교통부_(TAGO)_버스도착정보 / 버스정류소정보".
// 전국(서울+경기+광역시+...) 통합. 무료, 일 한도 있음.
// 키: Info.plist 의 DATA_GO_KR_KEY (인코딩되지 않은 일반 키).
//
// 흐름:
//   1) ODsay 경로의 출발 정류장 이름/좌표 확보
//   2) findStopsNear(coordinate:cityCode:) 로 좌표 기반 정류장 검색 → nodeId 매핑
//   3) fetchArrivals(cityCode:nodeId:) 로 그 정류장의 도착 정보 받기
//   4) 노선번호 매칭 → BoardableOption.arrivalMinutes 업데이트

final class RealtimeBusService {
    static let shared = RealtimeBusService()
    private init() {}

    private var serviceKey: String {
        Bundle.main.infoDictionary?["DATA_GO_KR_KEY"] as? String ?? ""
    }

    private let session = URLSession.shared

    // MARK: - 정류장 도착 정보 조회

    func fetchArrivals(cityCode: Int, nodeId: String) async throws -> [RealtimeArrival] {
        var components = URLComponents(string: "https://apis.data.go.kr/1613000/ArvlInfoInqireService/getSttnAcctoArvlPrearngeInfoList")!
        components.queryItems = [
            URLQueryItem(name: "serviceKey", value: serviceKey),
            URLQueryItem(name: "cityCode", value: String(cityCode)),
            URLQueryItem(name: "nodeId", value: nodeId),
            URLQueryItem(name: "numOfRows", value: "30"),
            URLQueryItem(name: "pageNo", value: "1"),
            URLQueryItem(name: "_type", value: "json")
        ]
        let request = URLRequest(url: components.url!)

        let (data, _) = try await session.data(for: request)
        let response = try JSONDecoder().decode(TagoArrivalResponse.self, from: data)

        let items = response.response?.body?.items?.itemList ?? []
        return items.map { item in
            RealtimeArrival(
                routeNo: item.routeno ?? "",
                routeId: item.routeid,            // 위치 추적용
                arrivalSeconds: item.arrtime ?? 0,
                remainingStops: item.arrprevstationcnt ?? 0,
                vehicleType: item.vehicletp
            )
        }
    }

    // MARK: - 좌표 기반 가까운 정류장 검색 (nodeId 알아내기)

    func findStopsNear(coordinate: Coordinate) async throws -> [TaggedStop] {
        var components = URLComponents(string: "https://apis.data.go.kr/1613000/BusSttnInfoInqireService/getCrdntPrxmtSttnList")!
        components.queryItems = [
            URLQueryItem(name: "serviceKey", value: serviceKey),
            URLQueryItem(name: "gpsLati", value: String(coordinate.lat)),
            URLQueryItem(name: "gpsLong", value: String(coordinate.lng)),
            URLQueryItem(name: "numOfRows", value: "20"),
            URLQueryItem(name: "pageNo", value: "1"),
            URLQueryItem(name: "_type", value: "json")
        ]
        let request = URLRequest(url: components.url!)

        let (data, _) = try await session.data(for: request)
        let response = try JSONDecoder().decode(TagoStopResponse.self, from: data)

        let items = response.response?.body?.items?.itemList ?? []
        return items.compactMap { item in
            guard let nodeId = item.nodeid, let cityCode = item.citycode else { return nil }
            return TaggedStop(
                name: item.nodenm ?? "",
                nodeId: nodeId,
                cityCode: cityCode
            )
        }
    }
}

// MARK: - 결과 모델

struct RealtimeArrival {
    let routeNo: String
    let routeId: String?           // TAGO routeId — 차량 위치 추적에 사용
    let arrivalSeconds: Int
    let remainingStops: Int
    let vehicleType: String?

    var arrivalMinutes: Int { max(0, arrivalSeconds / 60) }
}

struct TaggedStop {
    let name: String
    let nodeId: String
    let cityCode: Int
}

// MARK: - TAGO 응답

// items 가 빈 결과일 때 ""(빈 문자열)로 오는 케이스가 있어서 옵셔널 + 커스텀 디코딩.
// 응답은 디코딩만 하므로 Decodable 만 채택.
struct TagoArrivalResponse: Decodable {
    let response: TagoResponse<TagoArrivalItem>?
}

struct TagoStopResponse: Decodable {
    let response: TagoResponse<TagoStopItem>?
}

struct TagoResponse<T: Decodable>: Decodable {
    let header: TagoHeader?
    let body: TagoBody<T>?
}

struct TagoHeader: Decodable {
    let resultCode: String?
    let resultMsg: String?
}

struct TagoBody<T: Decodable>: Decodable {
    let items: TagoItems<T>?
    let numOfRows: Int?
    let pageNo: Int?
    let totalCount: Int?

    enum CodingKeys: String, CodingKey {
        case items, numOfRows, pageNo, totalCount
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.numOfRows = try? c.decodeIfPresent(Int.self, forKey: .numOfRows)
        self.pageNo = try? c.decodeIfPresent(Int.self, forKey: .pageNo)
        self.totalCount = try? c.decodeIfPresent(Int.self, forKey: .totalCount)
        // items 가 "" 일 수도, {item: [...]} 일 수도 있음
        if (try? c.decode(String.self, forKey: .items)) != nil {
            self.items = nil
        } else {
            self.items = try? c.decodeIfPresent(TagoItems<T>.self, forKey: .items)
        }
    }
}

// item 이 1개일 때 단일 객체로, 여러 개일 때 배열로 오는 변덕 흡수
struct TagoItems<T: Decodable>: Decodable {
    let itemList: [T]

    enum CodingKeys: String, CodingKey { case item }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        if let arr = try? c.decode([T].self, forKey: .item) {
            self.itemList = arr
        } else if let one = try? c.decode(T.self, forKey: .item) {
            self.itemList = [one]
        } else {
            self.itemList = []
        }
    }
}

struct TagoArrivalItem: Decodable {
    let routeno: String?       // 노선번호 (예: "271")
    let routeid: String?       // 노선 ID (위치 추적용)
    let routetp: String?       // 노선유형 (간선/지선/광역 등)
    let arrtime: Int?          // 도착예정 초
    let arrprevstationcnt: Int? // 남은 정거장 수
    let vehicletp: String?     // 차량유형 (저상/일반)
    let nodeid: String?
    let nodenm: String?
}

struct TagoStopItem: Decodable {
    let nodeid: String?        // 정류장 ID
    let nodenm: String?        // 정류장명
    let nodeno: Int?           // 정류장 번호
    let gpslati: Double?
    let gpslong: Double?
    let citycode: Int?
}

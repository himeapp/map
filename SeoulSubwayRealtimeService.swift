import Foundation

// MARK: - 서울 열린데이터광장 실시간 지하철 도착정보
//
// 수도권 지하철 1~9호선 + 분당/신분당/공항철도/경의중앙/경춘/수인 등 거의 다 커버.
// 키: Info.plist 의 SEOUL_OPEN_API_KEY
//
// ⚠️ 엔드포인트가 HTTP 만 지원 — Info.plist 에 NSAppTransportSecurity 예외 필요.
//
// 한도: 일 1,000회. 회당 최대 1,000건.

final class SeoulSubwayRealtimeService {
    static let shared = SeoulSubwayRealtimeService()
    private init() {}

    private var apiKey: String {
        Bundle.main.infoDictionary?["SEOUL_OPEN_API_KEY"] as? String ?? ""
    }

    private let session = URLSession.shared

    // MARK: - 역명으로 도착정보 조회

    /// stationName 은 한국어 역명 (예: "강남", "신도림"). "역" 접미사 없이.
    func fetchArrivals(stationName: String) async throws -> [SubwayArrival] {
        let cleanName = stationName.replacingOccurrences(of: "역", with: "")
        guard let encoded = cleanName.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) else {
            return []
        }
        let urlString = "http://swopenAPI.seoul.go.kr/api/subway/\(apiKey)/json/realtimeStationArrival/0/30/\(encoded)"
        guard let url = URL(string: urlString) else { return [] }

        let (data, _) = try await session.data(from: url)
        let response = try JSONDecoder().decode(SeoulSubwayResponse.self, from: data)

        let items = response.realtimeArrivalList ?? []
        return items.compactMap { item in
            SubwayArrival(
                subwayId: item.subwayId ?? "",
                lineName: SubwayLineMap.name(for: item.subwayId),
                stationName: item.statnNm ?? cleanName,
                trainDestination: item.bstatnNm ?? "",
                heading: item.updnLine ?? "",
                arrivalSeconds: Int(item.barvlDt ?? "0") ?? 0,
                statusMessage: item.arvlMsg2 ?? "",
                trainNo: item.btrainNo
            )
        }
    }
}

// MARK: - 도메인 모델

struct SubwayArrival {
    let subwayId: String        // "1001", "1002" 등 노선 ID
    let lineName: String        // "1호선", "2호선" 등 사람이 읽는 이름
    let stationName: String
    let trainDestination: String   // "신도림행" 등
    let heading: String         // "상행" / "하행"
    let arrivalSeconds: Int
    let statusMessage: String   // "5분 후 (신도림)" 같은 사람이 읽는 안내
    let trainNo: String?

    var arrivalMinutes: Int { max(0, arrivalSeconds / 60) }
}

// MARK: - 노선 ID → 노선명 매핑

enum SubwayLineMap {
    static func name(for subwayId: String?) -> String {
        guard let id = subwayId else { return "" }
        switch id {
        case "1001": return "1호선"
        case "1002": return "2호선"
        case "1003": return "3호선"
        case "1004": return "4호선"
        case "1005": return "5호선"
        case "1006": return "6호선"
        case "1007": return "7호선"
        case "1008": return "8호선"
        case "1009": return "9호선"
        case "1061": return "중앙선"
        case "1063": return "경의중앙선"
        case "1065": return "공항철도"
        case "1067": return "경춘선"
        case "1075": return "수인분당선"
        case "1077": return "신분당선"
        case "1081": return "경강선"
        case "1092": return "우이신설선"
        case "1093": return "서해선"
        case "1094": return "김포골드라인"
        case "1095": return "신림선"
        case "1032": return "GTX-A"
        default:    return id
        }
    }

    /// ODsay 가 주는 노선명("수도권2호선", "신분당선" 등) → 우리 정규화 이름
    static func normalize(_ odsayLineName: String) -> String {
        var s = odsayLineName
        s = s.replacingOccurrences(of: "수도권", with: "")
        s = s.trimmingCharacters(in: .whitespaces)
        return s
    }
}

// MARK: - 서울 API 응답

struct SeoulSubwayResponse: Decodable {
    let errorMessage: SeoulErrorMessage?
    let realtimeArrivalList: [SeoulSubwayArrivalItem]?
}

struct SeoulErrorMessage: Decodable {
    let code: String?
    let message: String?
    let total: Int?
}

struct SeoulSubwayArrivalItem: Decodable {
    let subwayId: String?          // "1001"~ 노선 ID
    let statnNm: String?           // 역명
    let trainLineNm: String?       // "강남행 - 신설동방면"
    let bstatnNm: String?          // 종점역명
    let btrainNo: String?          // 열차번호
    let updnLine: String?          // 상행/하행
    let barvlDt: String?           // 도착 예정 시간(초). 문자열로 옴
    let arvlMsg2: String?          // 도착 메시지 ("3분 후 (역삼)" 등)
    let arvlMsg3: String?          // 현재 역
}

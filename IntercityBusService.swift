import Foundation

// MARK: - TAGO 시외/고속버스 시간표
//
// 시외 (SuberbusInfoInqireService) + 고속 (ExpBusInfoInqireService) 통합.
// 같은 city→city 인터페이스로 노출. 둘 다 cityCode/terminalId 가 API에서 받은 그대로 통과.
//
// 키: Info.plist 의 DATA_GO_KR_KEY (TAGO 통합 키)

final class IntercityBusService {
    static let shared = IntercityBusService()
    private init() {}

    private var serviceKey: String {
        Bundle.main.infoDictionary?["DATA_GO_KR_KEY"] as? String ?? ""
    }

    private let session = URLSession.shared
    private let apiBase = "https://apis.data.go.kr/1613000"

    // MARK: - 도시/터미널 목록 (출발지 선택용)

    func fetchOriginCities(type: IntercityVehicleType) async throws -> [IntercityCity] {
        guard let service = serviceName(for: type) else { return [] }
        return try await fetchCityList(
            url: "\(apiBase)/\(service)/getStrtpntAlocFndCityCodeList"
        )
    }

    func fetchDestCities(type: IntercityVehicleType, originCode: String) async throws -> [IntercityCity] {
        guard let service = serviceName(for: type) else { return [] }
        return try await fetchCityList(
            url: "\(apiBase)/\(service)/getArrCityCodeList",
            extraParams: [URLQueryItem(name: "depTerminalId", value: originCode)]
        )
    }

    // MARK: - 시간표 조회

    func fetchSchedule(
        type: IntercityVehicleType,
        origin: IntercityCity,
        dest: IntercityCity,
        date: Date
    ) async throws -> [IntercityOption] {
        let opEndpoint: String
        switch type {
        case .expressBus:
            opEndpoint = "\(apiBase)/ExpBusInfoInqireService/getStrtpntAlocFndExpsBusInfo"
        case .suburbBus:
            opEndpoint = "\(apiBase)/SuberbusInfoInqireService/getStrtpntAlocFndSuberbusInfo"
        case .train:
            return []   // 열차는 TrainService 가 담당
        }

        var components = URLComponents(string: opEndpoint)!
        components.queryItems = baseParams() + [
            URLQueryItem(name: "depTerminalId", value: origin.code),
            URLQueryItem(name: "arrTerminalId", value: dest.code),
            URLQueryItem(name: "depPlandTime", value: dateString(date)),
            URLQueryItem(name: "numOfRows", value: "100"),
            URLQueryItem(name: "pageNo", value: "1")
        ]
        let req = URLRequest(url: components.url!)
        let (data, _) = try await session.data(for: req)
        let response = try JSONDecoder().decode(TagoIntercityScheduleResponse.self, from: data)

        let items = response.response?.body?.items?.itemList ?? []
        return items.compactMap { parseOption(item: $0, type: type) }
            .sorted { $0.departureTime < $1.departureTime }
    }

    // MARK: - 내부 헬퍼

    private func fetchCityList(url: String, extraParams: [URLQueryItem] = []) async throws -> [IntercityCity] {
        var components = URLComponents(string: url)!
        components.queryItems = baseParams() + extraParams + [
            URLQueryItem(name: "numOfRows", value: "300"),
            URLQueryItem(name: "pageNo", value: "1")
        ]
        let req = URLRequest(url: components.url!)
        let (data, _) = try await session.data(for: req)
        let response = try JSONDecoder().decode(TagoIntercityCityResponse.self, from: data)

        let items = response.response?.body?.items?.itemList ?? []
        return items.compactMap { item in
            guard let code = item.cityCode, let name = item.cityName else { return nil }
            return IntercityCity(code: code, name: name)
        }
    }

    private func baseParams() -> [URLQueryItem] {
        [URLQueryItem(name: "serviceKey", value: serviceKey),
         URLQueryItem(name: "_type", value: "json")]
    }

    private func serviceName(for type: IntercityVehicleType) -> String? {
        switch type {
        case .expressBus: return "ExpBusInfoInqireService"
        case .suburbBus:  return "SuberbusInfoInqireService"
        case .train:      return nil
        }
    }

    private func dateString(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyyMMdd"
        f.locale = Locale(identifier: "ko_KR_POSIX")
        f.timeZone = TimeZone(identifier: "Asia/Seoul")
        return f.string(from: date)
    }

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyyMMddHHmm"
        f.locale = Locale(identifier: "ko_KR_POSIX")
        f.timeZone = TimeZone(identifier: "Asia/Seoul")
        return f
    }()

    private func parseOption(item: TagoIntercityScheduleItem, type: IntercityVehicleType) -> IntercityOption? {
        guard let depRaw = item.depPlandTime, let arrRaw = item.arrPlandTime,
              let dep = Self.timeFormatter.date(from: String(depRaw)),
              let arr = Self.timeFormatter.date(from: String(arrRaw)) else {
            return nil
        }
        return IntercityOption(
            type: type,
            grade: item.gradeNm ?? "일반",
            departureTime: dep,
            arrivalTime: arr,
            originTerminal: item.depPlaceNm ?? "",
            destTerminal: item.arrPlaceNm ?? "",
            fare: item.charge,
            providerCode: item.routeId
        )
    }
}

// MARK: - TAGO 응답

struct TagoIntercityCityResponse: Decodable {
    let response: TagoResponse<TagoIntercityCityItem>?
}

struct TagoIntercityCityItem: Decodable {
    let cityCode: String?
    let cityName: String?
}

struct TagoIntercityScheduleResponse: Decodable {
    let response: TagoResponse<TagoIntercityScheduleItem>?
}

struct TagoIntercityScheduleItem: Decodable {
    let depPlaceNm: String?
    let arrPlaceNm: String?
    let depPlandTime: Int?       // yyyyMMddHHmm
    let arrPlandTime: Int?       // yyyyMMddHHmm
    let charge: Int?             // 요금 (원)
    let gradeNm: String?         // "우등", "심야우등", "일반" 등
    let routeId: String?
}

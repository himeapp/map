import Foundation

// MARK: - TAGO 열차 시간표 (KTX / 새마을 / 무궁화 등 일반열차)
//
// API: TrainInfoInqireService
// 운영: 한국철도공사 (코레일). SRT(수서)는 미포함 — 공공 API 없음.
//
// 키: Info.plist 의 DATA_GO_KR_KEY (TAGO 통합 키)

final class TrainService {
    static let shared = TrainService()
    private init() {}

    private var serviceKey: String {
        Bundle.main.infoDictionary?["DATA_GO_KR_KEY"] as? String ?? ""
    }

    private let session = URLSession.shared
    private let apiBase = "https://apis.data.go.kr/1613000/TrainInfoInqireService"

    // MARK: - 도시 목록

    func fetchCities() async throws -> [IntercityCity] {
        var components = URLComponents(string: "\(apiBase)/getCtyCodeList")!
        components.queryItems = baseParams() + [
            URLQueryItem(name: "numOfRows", value: "200"),
            URLQueryItem(name: "pageNo", value: "1")
        ]
        let req = URLRequest(url: components.url!)
        let (data, _) = try await session.data(for: req)
        let response = try JSONDecoder().decode(TagoTrainCityResponse.self, from: data)

        let items = response.response?.body?.items?.itemList ?? []
        return items.compactMap { item in
            guard let code = item.cityCode, let name = item.cityName else { return nil }
            return IntercityCity(code: String(code), name: name)
        }
    }

    // MARK: - 도시별 기차역

    func fetchStations(cityCode: String) async throws -> [IntercityCity] {
        var components = URLComponents(string: "\(apiBase)/getCtyAcctoTrainSttnList")!
        components.queryItems = baseParams() + [
            URLQueryItem(name: "cityCode", value: cityCode),
            URLQueryItem(name: "numOfRows", value: "200"),
            URLQueryItem(name: "pageNo", value: "1")
        ]
        let req = URLRequest(url: components.url!)
        let (data, _) = try await session.data(for: req)
        let response = try JSONDecoder().decode(TagoTrainStationResponse.self, from: data)

        let items = response.response?.body?.items?.itemList ?? []
        return items.compactMap { item in
            guard let id = item.nodeid, let name = item.nodename else { return nil }
            return IntercityCity(code: id, name: name)
        }
    }

    // MARK: - 도시 단위 시간표 (각 도시의 첫 번째 역으로 매핑)
    //
    // UX 단순화용. "서울 → 부산" 검색 시 서울의 첫 역(보통 서울역) → 부산의 첫 역.
    // 정확도 한계 있음 (서울역/용산역 등 구분 안 됨). 향후 역 단위 picker 도입 시 제거.

    func fetchScheduleByCity(
        originCity: IntercityCity,
        destCity: IntercityCity,
        date: Date
    ) async throws -> [IntercityOption] {
        async let originStations = fetchStations(cityCode: originCity.code)
        async let destStations = fetchStations(cityCode: destCity.code)
        let (origins, dests) = try await (originStations, destStations)
        guard let origin = origins.first, let dest = dests.first else { return [] }
        return try await fetchSchedule(origin: origin, dest: dest, date: date)
    }

    // MARK: - 시간표 조회 (역 → 역, 날짜)

    func fetchSchedule(
        origin: IntercityCity,        // .code 는 nodeid (역 ID)
        dest: IntercityCity,
        date: Date,
        gradeCode: String? = nil       // "00": 전체, "01": KTX, "02": 새마을, "03": 무궁화 등
    ) async throws -> [IntercityOption] {
        var components = URLComponents(string: "\(apiBase)/getStrtpntAlocFndTrainInfo")!
        var params = baseParams() + [
            URLQueryItem(name: "depPlaceId", value: origin.code),
            URLQueryItem(name: "arrPlaceId", value: dest.code),
            URLQueryItem(name: "depPlandTime", value: dateString(date)),
            URLQueryItem(name: "numOfRows", value: "100"),
            URLQueryItem(name: "pageNo", value: "1")
        ]
        if let g = gradeCode {
            params.append(URLQueryItem(name: "trainGradeCode", value: g))
        }
        components.queryItems = params

        let req = URLRequest(url: components.url!)
        let (data, _) = try await session.data(for: req)
        let response = try JSONDecoder().decode(TagoTrainScheduleResponse.self, from: data)

        let items = response.response?.body?.items?.itemList ?? []
        return items.compactMap { parseOption(item: $0) }
            .sorted { $0.departureTime < $1.departureTime }
    }

    // MARK: - 내부 헬퍼

    private func baseParams() -> [URLQueryItem] {
        [URLQueryItem(name: "serviceKey", value: serviceKey),
         URLQueryItem(name: "_type", value: "json")]
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

    private func parseOption(item: TagoTrainScheduleItem) -> IntercityOption? {
        guard let depRaw = item.depplandtime, let arrRaw = item.arrplandtime,
              let dep = Self.timeFormatter.date(from: String(depRaw)),
              let arr = Self.timeFormatter.date(from: String(arrRaw)) else {
            return nil
        }
        return IntercityOption(
            type: .train,
            grade: item.traingradename ?? "열차",
            departureTime: dep,
            arrivalTime: arr,
            originTerminal: item.depplacename ?? "",
            destTerminal: item.arrplacename ?? "",
            fare: item.adultcharge,
            providerCode: item.trainno.map(String.init)
        )
    }
}

// MARK: - TAGO 응답

struct TagoTrainCityResponse: Decodable {
    let response: TagoResponse<TagoTrainCityItem>?
}

struct TagoTrainCityItem: Decodable {
    let cityCode: Int?
    let cityName: String?
}

struct TagoTrainStationResponse: Decodable {
    let response: TagoResponse<TagoTrainStationItem>?
}

struct TagoTrainStationItem: Decodable {
    let nodeid: String?       // 역 ID
    let nodename: String?     // 역명
}

struct TagoTrainScheduleResponse: Decodable {
    let response: TagoResponse<TagoTrainScheduleItem>?
}

struct TagoTrainScheduleItem: Decodable {
    let depplandtime: Int?    // yyyyMMddHHmm
    let arrplandtime: Int?
    let depplacename: String?
    let arrplacename: String?
    let traingradename: String?
    let trainno: Int?
    let adultcharge: Int?
}

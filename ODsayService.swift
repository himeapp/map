import Foundation

// MARK: - ODsay 대중교통 경로 API
//
// 카카오는 공개 대중교통 경로 REST가 없어서 ODsay로 위임.
// 키: Info.plist 의 ODSAY_API_KEY.
// 무료 한도: 일 5,000건. https://lab.odsay.com
//
// 응답을 "지금 탈 수 있는 수단" flat 리스트로 변환하는 게 이 서비스의 핵심.
// path[].subPath[] 안에 도보/지하철/버스가 섞여 있는데, 첫 번째 탑승 수단을
// BoardableOption으로 뽑고 그 이후를 afterSteps 로 직렬화함.

final class ODsayService {
    static let shared = ODsayService()
    private init() {}

    private var apiKey: String {
        Bundle.main.infoDictionary?["ODSAY_API_KEY"] as? String ?? ""
    }

    private let session = URLSession.shared

    // MARK: - 경로 탐색

    func fetchBoardableOptions(from: Place, to: Place) async throws -> [BoardableOption] {
        var components = URLComponents(string: "https://api.odsay.com/v1/api/searchPubTransPathT")!
        components.queryItems = [
            URLQueryItem(name: "apiKey", value: apiKey),
            URLQueryItem(name: "SX", value: String(from.coordinate.lng)),
            URLQueryItem(name: "SY", value: String(from.coordinate.lat)),
            URLQueryItem(name: "EX", value: String(to.coordinate.lng)),
            URLQueryItem(name: "EY", value: String(to.coordinate.lat)),
            URLQueryItem(name: "OPT", value: "0"),          // 0: 추천, 1: 최소환승, 2: 최소시간
            URLQueryItem(name: "SearchPathType", value: "0") // 0: 지하철+버스
        ]
        let request = URLRequest(url: components.url!)

        let (data, _) = try await session.data(for: request)
        let response = try JSONDecoder().decode(ODsayPathResponse.self, from: data)

        if let err = response.error {
            throw ODsayError.api(code: err.code ?? "?", msg: err.msg ?? "unknown")
        }

        return flattenToBoardableOptions(response: response, to: to)
    }

    // MARK: - flatten

    private func flattenToBoardableOptions(response: ODsayPathResponse, to: Place) -> [BoardableOption] {
        guard let paths = response.result?.path else { return [] }

        // 같은 "첫 탑승 수단(번호 + 출발 정류장)" 이 여러 경로에서 반복되면 한 번만.
        var seen = Set<String>()
        var options: [BoardableOption] = []

        for path in paths {
            // 첫 번째 탑승(walk가 아닌 subPath)
            guard let firstTransitIdx = path.subPath.firstIndex(where: { $0.trafficType != ODsayTrafficType.walk.rawValue }) else {
                continue
            }
            let firstTransit = path.subPath[firstTransitIdx]
            guard let lane = firstTransit.lane?.first else { continue }

            let vehicleType: VehicleType = (firstTransit.trafficType == ODsayTrafficType.subway.rawValue) ? .subway : .bus
            let number: String = {
                if vehicleType == .subway {
                    return lane.name ?? "?"
                } else {
                    return lane.busNo ?? lane.name ?? "?"
                }
            }()

            let dedupeKey = "\(vehicleType)-\(number)-\(firstTransit.startName ?? "")"
            if seen.contains(dedupeKey) { continue }
            seen.insert(dedupeKey)

            let headsign: String = {
                if let way = firstTransit.way, !way.isEmpty { return way + " 방향" }
                if let end = firstTransit.endName { return end + " 방향" }
                return ""
            }()

            let vehicle = Vehicle(
                type: vehicleType,
                number: number,
                headsign: headsign,
                via: firstTransit.endName ?? "",
                busType: vehicleType == .bus ? lane.type : nil,
                subwayLineCode: vehicleType == .subway ? lane.subwayCode : nil
            )

            let originStop = TransitStop(
                name: firstTransit.startName ?? "",
                coordinate: firstTransit.startX.flatMap { sx in
                    firstTransit.startY.map { sy in Coordinate(lat: sy, lng: sx) }
                },
                odsayStationId: firstTransit.startID,
                cityCode: nil,
                nodeId: nil
            )

            // 첫 탑승 앞의 도보 구간 합 = "이 정류장까지 걸어가는 시간"
            let leadingWalk = path.subPath[0..<firstTransitIdx]
                .filter { $0.trafficType == ODsayTrafficType.walk.rawValue }
                .compactMap { $0.sectionTime }
                .reduce(0, +)

            let option = BoardableOption(
                vehicle: vehicle,
                arrivalMinutes: nil,        // 실시간 API로 채움
                nextArrivalMinutes: nil,
                totalMinutes: path.info.totalTime,
                originStop: originStop,
                walkToStopMinutes: leadingWalk > 0 ? leadingWalk : nil,
                afterSteps: buildAfterSteps(path: path, firstTransitIdx: firstTransitIdx, toPlace: to)
            )
            options.append(option)
        }

        return options
    }

    // 첫 탑승 이후의 subPath들을 RouteStep 시퀀스로 변환
    private func buildAfterSteps(path: ODsayPath, firstTransitIdx: Int, toPlace: Place) -> [RouteStep] {
        var steps: [RouteStep] = []
        let subPaths = path.subPath

        for i in firstTransitIdx..<subPaths.count {
            let sp = subPaths[i]

            if i == firstTransitIdx {
                // 첫 탑승 수단의 하차 정보
                steps.append(RouteStep(
                    type: .getOff,
                    title: "\(sp.endName ?? "") 하차",
                    description: sp.stationCount.map { "\($0)정거장 후" } ?? "",
                    detail: nil,
                    durationMinutes: sp.sectionTime,
                    stopsCount: sp.stationCount,
                    vehicle: nil
                ))
                continue
            }

            switch sp.trafficType {
            case ODsayTrafficType.walk.rawValue:
                let nextStart = (i + 1 < subPaths.count) ? subPaths[i + 1].startName : nil
                steps.append(RouteStep(
                    type: .walk,
                    title: "도보 \(sp.sectionTime ?? 0)분",
                    description: nextStart.map { "\($0)까지" } ?? "",
                    detail: nil,
                    durationMinutes: sp.sectionTime,
                    stopsCount: nil,
                    vehicle: nil
                ))
            case ODsayTrafficType.subway.rawValue, ODsayTrafficType.bus.rawValue:
                guard let lane = sp.lane?.first else { continue }
                let vt: VehicleType = (sp.trafficType == ODsayTrafficType.subway.rawValue) ? .subway : .bus
                let num = vt == .subway ? (lane.name ?? "?") : (lane.busNo ?? lane.name ?? "?")
                let v = Vehicle(
                    type: vt,
                    number: num,
                    headsign: sp.way ?? "",
                    via: sp.endName ?? "",
                    busType: vt == .bus ? lane.type : nil,
                    subwayLineCode: vt == .subway ? lane.subwayCode : nil
                )
                steps.append(RouteStep(
                    type: .transfer,
                    title: "\(sp.startName ?? "")에서 \(num) 환승",
                    description: sp.stationCount.map { "\($0)정거장 이동" } ?? "",
                    detail: nil,
                    durationMinutes: sp.sectionTime,
                    stopsCount: sp.stationCount,
                    vehicle: v
                ))
            default:
                break
            }
        }

        steps.append(RouteStep(
            type: .arrive,
            title: "\(toPlace.name) 도착",
            description: "목적지 도착",
            detail: nil,
            durationMinutes: nil,
            stopsCount: nil,
            vehicle: nil
        ))

        return steps
    }
}

// MARK: - ODsay 응답 모델

enum ODsayTrafficType: Int {
    case subway = 1
    case bus = 2
    case walk = 3
}

enum ODsayError: Error {
    case api(code: String, msg: String)
}

struct ODsayPathResponse: Codable {
    let result: ODsayResult?
    let error: ODsayApiErrorBody?
}

struct ODsayApiErrorBody: Codable {
    let code: String?
    let msg: String?
}

struct ODsayResult: Codable {
    let path: [ODsayPath]
}

struct ODsayPath: Codable {
    let pathType: Int
    let info: ODsayPathInfo
    let subPath: [ODsaySubPath]
}

struct ODsayPathInfo: Codable {
    let totalTime: Int
    let totalDistance: Int?
    let payment: Int?
    let busTransitCount: Int?
    let subwayTransitCount: Int?
    let firstStartStation: String?
    let lastEndStation: String?
}

struct ODsaySubPath: Codable {
    let trafficType: Int        // 1: subway, 2: bus, 3: walk
    let sectionTime: Int?
    let distance: Int?
    let stationCount: Int?
    let lane: [ODsayLane]?
    let startName: String?
    let endName: String?
    let startID: Int?
    let endID: Int?
    let way: String?
    let startX: Double?
    let startY: Double?
    let endX: Double?
    let endY: Double?
}

struct ODsayLane: Codable {
    let name: String?           // 지하철: "수도권1호선" 같은 노선명
    let busNo: String?          // 버스 번호
    let busID: Int?
    let subwayCode: Int?
    let type: Int?              // 버스 타입 코드(간선/지선/광역 등)
}

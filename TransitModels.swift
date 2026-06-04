import Foundation

// MARK: - 장소

struct Place: Identifiable, Codable, Equatable {
    let id: UUID
    var name: String
    var address: String
    var coordinate: Coordinate
    var category: PlaceCategory

    init(id: UUID = UUID(), name: String, address: String, coordinate: Coordinate, category: PlaceCategory = .general) {
        self.id = id
        self.name = name
        self.address = address
        self.coordinate = coordinate
        self.category = category
    }
}

struct Coordinate: Codable, Equatable {
    let lat: Double
    let lng: Double
}

enum PlaceCategory: String, Codable {
    case home, work, favorite, general
    var emoji: String {
        switch self {
        case .home: return "🏠"
        case .work: return "💼"
        case .favorite: return "⭐"
        case .general: return "📍"
        }
    }
}

// MARK: - 경로 탐색 결과

struct RouteResult {
    let from: Place
    let to: Place
    let fetchedAt: Date
    let boardableOptions: [BoardableOption] // 지금 탈 수 있는 것들 (flatten)
}

// 한 출발 지점(정류장/역)과 거기서 탈 수 있는 수단들.
// "어디로 가야 하나 → 거기서 뭘 타나" 흐름의 1차 단위.
struct DepartureGroup: Identifiable {
    let id: UUID = UUID()
    let stop: TransitStop          // 출발 정류장/역
    let walkMinutes: Int?          // 출발지에서 이 정류장까지 도보 분
    var options: [BoardableOption] // 그 정류장에서 탈 수 있는 수단들 (정렬됨)

    // 이 지점을 경유하는 경로 중 가장 빠른 총 소요시간 (그룹 정렬 기준)
    var bestTotalMinutes: Int { options.map(\.totalMinutes).min() ?? .max }
}

// 지금 탈 수 있는 수단 하나
struct BoardableOption: Identifiable {
    let id: UUID = UUID()
    let vehicle: Vehicle
    // 실시간 API 응답 전에는 nil. 받으면 채워짐.
    var arrivalMinutes: Int?
    var nextArrivalMinutes: Int?
    let totalMinutes: Int
    // ODsay path.info.mapObj — 지도 폴리라인(loadLane) 조회용 토큰. 없으면 nil.
    let mapObj: String?
    // 첫 탑승 정류장. 국토부 실시간 도착 조회용 식별자 매핑에 사용.
    let originStop: TransitStop?
    // 출발지에서 첫 탑승 정류장까지 도보 분 (ODsay 첫 도보 구간). 없으면 nil.
    let walkToStopMinutes: Int?
    // TAGO routeId — 실시간 차량 위치 추적용 (실시간 도착 응답에서 채움)
    var routeId: String?
    var cityCode: Int?
    let afterSteps: [RouteStep]

    // "뺄 것만 빼기"용 안정 키 — 새로고침해도 같은 경로면 유지됨
    var exclusionKey: String {
        "\(vehicle.type.color)|\(vehicle.number)|\(originStop?.name ?? "")"
    }
}

// 탑승 중 위치 기반 알림/넛지에서 쓰는 파생값들 (View·VM 공용)
extension BoardableOption {
    /// 이번 구간 하차 스텝
    var getOffStep: RouteStep? { afterSteps.first { $0.type == .getOff } }
    /// 다음 환승 스텝
    var transferStep: RouteStep? { afterSteps.first { $0.type == .transfer } }
    /// 환승 구간이 남아 있는지
    var hasTransferLeg: Bool { afterSteps.contains { $0.type == .transfer } }

    /// 이번 구간 하차 정류소 좌표 (경유역 좌표의 마지막 = 하차역). 없으면 nil.
    var getOffCoordinate: Coordinate? { getOffStep?.passStopCoords?.last }

    /// 이번 구간 하차 정류소 이름 ("○○ 하차" → "○○"). 없으면 nil.
    var getOffStopName: String? {
        guard let g = getOffStep else { return nil }
        var t = g.title.replacingOccurrences(of: "에서 하차", with: "")
        if t.hasSuffix("하차") { t = String(t.dropLast(2)) }
        t = t.trimmingCharacters(in: .whitespaces)
        return t.isEmpty ? nil : t
    }

    /// 환승해서 다음에 탈 수단 표시명 ("2호선"/"271번"). 환승 없으면 nil.
    var transferLineLabel: String? {
        guard let v = transferStep?.vehicle else { return nil }
        return v.type == .bus ? "\(v.number)번" : v.number
    }
}

// 정류장 / 역 식별자 묶음
struct TransitStop {
    let name: String
    let coordinate: Coordinate?
    // ODsay startID — 경로 응답에서 받음
    let odsayStationId: Int?
    // 국토부 TAGO nodeId — 좌표 기반 매핑으로 채워짐
    var cityCode: Int?
    var nodeId: String?
}

// 탈 수 있는 수단
struct Vehicle: Identifiable {
    let id: UUID = UUID()
    let type: VehicleType
    let number: String            // "271", "2호선" 등
    let headsign: String          // 방향 (예: "강남역 방향")
    let via: String               // 경유지 요약
    // ODsay lane.type — 버스 노선 종류 코드 (간선/지선/광역 등 색상 결정)
    let busType: Int?
    // ODsay lane.subwayCode — 지하철 호선 코드 (1~9, 100번대 등 색상 결정)
    let subwayLineCode: Int?
}

enum VehicleType {
    case bus, subway, walk
    /// exclusionKey용 레거시 식별자 (변경 금지)
    var color: String {
        switch self {
        case .bus: return "bus"
        case .subway: return "subway"
        case .walk: return "walk"
        }
    }
}

extension Vehicle {
    /// 다이내믹아일랜드 등 UI에서 쓸 hex 색상 문자열 (#rrggbb)
    var lineColor: String {
        switch type {
        case .walk:
            return "#8a8a8e"
        case .bus:
            switch busType {
            case 1:        return "#0068b7" // 간선 (파랑)
            case 2:        return "#53b332" // 지선 (초록)
            case 3:        return "#ffc600" // 순환 (노랑)
            case 4, 14:    return "#f72f08" // 광역·급행 (빨강)
            case 5:        return "#5bb025" // 마을 (연초록)
            case 6:        return "#007dc5" // 공항 (남색)
            default:       return "#3d6bb3" // 경기 일반 등 기타
            }
        case .subway:
            switch subwayLineCode {
            case 1:        return "#0052a4"
            case 2:        return "#009246"
            case 3:        return "#ef7c1c"
            case 4:        return "#00a5de"
            case 5:        return "#996cac"
            case 6:        return "#cd7c2f"
            case 7:        return "#747f00"
            case 8:        return "#e6186c"
            case 9:        return "#bfa100"
            case 100:      return "#f5a200" // 수인·분당
            case 101:      return "#0065b3" // 공항철도
            case 104:      return "#77c4a3" // 경의중앙
            case 108:      return "#178c72" // 경춘
            case 114:      return "#003da5" // 경강
            case 116:      return "#8aadcb" // 서해
            default:       return "#888888"
            }
        }
    }
}

// MARK: - 탑승 후 경로 스텝

struct RouteStep: Identifiable {
    let id: UUID = UUID()
    let type: StepType
    let title: String
    let description: String
    let detail: String?           // 출구번호, 방향 등
    let durationMinutes: Int?
    let stopsCount: Int?
    let vehicle: Vehicle?
    // 탑승~하차 사이 경유역 이름들(현재역 ~ 하차역 포함). ODsay passStopList에서 채움. 없으면 nil.
    var passStops: [String]? = nil
    // passStops와 같은 순서·길이의 정류장 좌표. GPS로 "지금 어디쯤" 계산용. 좌표가 다 없으면 nil.
    var passStopCoords: [Coordinate]? = nil
}

enum StepType {
    case getOff       // 하차
    case walk         // 도보
    case transfer     // 환승
    case board        // 탑승
    case arrive       // 도착
}

// MARK: - 인터시티 (도시 간) — 시외/고속버스 + 열차
//
// 시내 대중교통과는 모델이 다름:
//  - 시내: "지금 탈 수 있는 것" → arrivalMinutes (분 단위 카운트다운)
//  - 인터시티: "정해진 시간표" → departureTime (시각 기반)

struct IntercityOption: Identifiable {
    let id: UUID = UUID()
    let type: IntercityVehicleType
    let grade: String              // "우등", "심야우등", "일반", "KTX", "새마을", "무궁화" 등
    let departureTime: Date
    let arrivalTime: Date
    let originTerminal: String     // "서울고속버스터미널" / "서울역" 등
    let destTerminal: String
    let fare: Int?                 // 원 단위
    let providerCode: String?      // API의 routeId/trainNo (예매/디테일 조회용)

    var durationMinutes: Int {
        max(0, Int(arrivalTime.timeIntervalSince(departureTime) / 60))
    }

    var minutesUntilDeparture: Int {
        Int(departureTime.timeIntervalSinceNow / 60)
    }
}

enum IntercityVehicleType {
    case suburbBus    // 시외버스
    case expressBus   // 고속버스
    case train        // 열차 (KTX/새마을/무궁화 등)

    var label: String {
        switch self {
        case .suburbBus: return "시외"
        case .expressBus: return "고속"
        case .train: return "열차"
        }
    }

    var icon: String {
        switch self {
        case .suburbBus, .expressBus: return "bus.fill"
        case .train: return "tram.fill"
        }
    }
}

// 출발/도착 도시. TAGO 시외/고속은 cityCode 기반.
struct IntercityCity: Identifiable, Hashable {
    var id: String { code }
    let code: String     // TAGO cityCode (예: "NAEK010" — 서울)
    let name: String     // "서울"
}

// MARK: - 지도용 경로 지오메트리
//
// ODsay loadLane(mapObj) 응답을 지도 폴리라인으로 변환한 것.
// 한 RouteLine = 한 구간(lane.section)의 좌표열.

struct RouteLine: Identifiable {
    let id = UUID()
    let coordinates: [Coordinate]
    let colorHex: String
    var dashed: Bool = false   // 도보 구간 등 점선 표현용
}

// 지도 위 경로 지점 핀 (출발/도착/탑승 정류장)
struct RoutePoint: Identifiable {
    enum Kind { case origin, destination, stop }
    let id = UUID()
    let coordinate: Coordinate
    let kind: Kind
    let title: String
}

// MARK: - 실시간 버스 위치 (지도 위 핀)

struct BusPosition: Identifiable {
    let id: String              // 차량 고유 ID (vehicleNo)
    let routeNo: String         // "271"
    let coordinate: Coordinate
    let lastStopName: String?   // 직전 정류장
    let nextStopName: String?   // 다음 정류장
    let updatedAt: Date
}

// MARK: - 저장된 경로 (앱 껐다 켜도 유지)

struct SavedRoute: Codable, Identifiable {
    let id: UUID
    let from: Place
    let to: Place
    let savedAt: Date

    init(id: UUID = UUID(), from: Place, to: Place, savedAt: Date = Date()) {
        self.id = id
        self.from = from
        self.to = to
        self.savedAt = savedAt
    }
}

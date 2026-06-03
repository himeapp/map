import Foundation
import Combine

@MainActor
final class TransitViewModel: ObservableObject {

    // MARK: - State

    @Published var fromPlace: Place?
    @Published var toPlace: Place?

    @Published var searchQuery: String = ""
    @Published var searchResults: [Place] = []
    @Published var isSearching: Bool = false
    @Published var searchTarget: SearchTarget = .to  // 출발지/도착지 중 어느 쪽 입력 중

    @Published var boardableOptions: [BoardableOption] = []
    @Published var isLoadingRoutes: Bool = false
    @Published var isRefreshingRealtime: Bool = false

    @Published var selectedOption: BoardableOption?  // 탭한 버스/지하철

    // "뺄 것만 빼기" — 사용자가 숨긴 경로의 exclusionKey 모음
    @Published var excludedKeys: Set<String> = []

    // 인터시티 (시외/고속/열차)
    @Published var intercityOptions: [IntercityOption] = []
    @Published var intercityTab: IntercityVehicleType = .expressBus
    @Published var intercityOrigin: IntercityCity?
    @Published var intercityDest: IntercityCity?
    @Published var intercityOriginOptions: [IntercityCity] = []
    @Published var intercityDestOptions: [IntercityCity] = []
    @Published var intercityDate: Date = Date()
    @Published var isLoadingIntercity: Bool = false

    // 탑승 중인 버스 실시간 위치 (지도 위 핀)
    @Published var livePositions: [BusPosition] = []

    @Published var savedPlaces: [Place] = []
    @Published var recentSearches: [Place] = []

    // 검색 결과 선택 시 이 카테고리로 저장됨. 빈 "집/회사/즐겨찾기 추가" 칩 탭 시 세팅.
    @Published var pendingSaveCategory: PlaceCategory?

    var homePlace: Place? { savedPlaces.first { $0.category == .home } }
    var workPlace: Place? { savedPlaces.first { $0.category == .work } }
    var favoritePlaces: [Place] { savedPlaces.filter { $0.category == .favorite } }

    // MARK: - 출발 지점 그룹 (어디로 가야 하나 → 거기서 뭘 타나)
    //
    // boardableOptions 를 "출발 정류장" 단위로 묶는다. 숨긴 경로는 제외.
    // 그룹은 총 소요시간 짧은 순, 그룹 안은 도착 임박 → 총 소요 순.
    var departureGroups: [DepartureGroup] {
        let visible = boardableOptions.filter { !excludedKeys.contains($0.exclusionKey) }

        var order: [String] = []
        var buckets: [String: [BoardableOption]] = [:]
        for opt in visible {
            let name = opt.originStop?.name ?? ""
            let key = name.isEmpty ? "veh:\(opt.vehicle.number)" : name
            if buckets[key] == nil { order.append(key) }
            buckets[key, default: []].append(opt)
        }

        var groups: [DepartureGroup] = order.map { key in
            let opts = buckets[key]!.sorted {
                let la = $0.arrivalMinutes ?? Int.max
                let ra = $1.arrivalMinutes ?? Int.max
                if la != ra { return la < ra }
                return $0.totalMinutes < $1.totalMinutes
            }
            let stop = opts.first?.originStop
                ?? TransitStop(name: key, coordinate: nil, odsayStationId: nil, cityCode: nil, nodeId: nil)
            let walk = opts.compactMap { $0.walkToStopMinutes }.min()
            return DepartureGroup(stop: stop, walkMinutes: walk, options: opts)
        }

        // 총 소요시간 짧은 순
        groups.sort { $0.bestTotalMinutes < $1.bestTotalMinutes }
        return groups
    }

    @Published var appState: AppState = .home

    enum SearchTarget { case from, to }
    enum AppState {
        case home
        case searching
        case walkingToStop // 정류소까지 도보 안내 (① → ② 사이)
        case waiting      // 버스 대기 화면 (시내)
        case onboard      // 탑승 후 이후 경로
        case transferWalking // 하차 후 다음 정류소까지 환승 도보
        case rerouting    // 경로 이탈 → 현위치 기준 재탐색
        case arrived      // 목적지 도착 완료 (여정 요약)
        case intercity    // 도시 간 (시외/고속/열차 시간표)
    }

    // 여정 시각 기록 (도착 요약용)
    @Published var boardedAt: Date?   // 탑승 시각
    @Published var arrivedAt: Date?   // 도착 시각

    // 도보 안내 중인 목표 출발 정류장 그룹
    @Published var walkingGroup: DepartureGroup?

    private let kakao = KakaoTransitService.shared
    private let odsay = ODsayService.shared
    private let realtime = RealtimeBusService.shared
    private let position = BusPositionService.shared
    private let intercityBus = IntercityBusService.shared
    private let train = TrainService.shared
    private let seoulSubway = SeoulSubwayRealtimeService.shared
    private let persistence = PersistenceService.shared
    private var searchTask: Task<Void, Never>?
    private var positionPollingTask: Task<Void, Never>?

    // MARK: - Init

    init() {
        loadSavedData()
    }

    // MARK: - 저장 데이터 로드

    func loadSavedData() {
        savedPlaces = persistence.loadPlaces()
        recentSearches = persistence.loadRecentSearches()

        // 앱 껐다 켜도 마지막 경로 복원
        if let last = persistence.loadLastRoute() {
            fromPlace = last.from
            toPlace = last.to
            // 바로 경로 다시 불러오기
            Task { await fetchRoutes() }
        }
    }

    // MARK: - 검색

    func startSearch(target: SearchTarget) {
        searchTarget = target
        searchQuery = ""
        searchResults = []
        pendingSaveCategory = nil
        appState = .searching
    }

    /// 빈 "집/회사/즐겨찾기 추가" 칩을 탭하면 호출. 선택된 장소가 자동으로 해당 카테고리로 저장된다.
    func startAddingPlace(category: PlaceCategory) {
        pendingSaveCategory = category
        searchTarget = .to
        searchQuery = ""
        searchResults = []
        appState = .searching
    }

    /// 저장된 장소 칩을 탭하면 호출. 목적지로 설정하고, 출발지가 있으면 즉시 경로 탐색.
    func useAsDestination(_ place: Place) {
        toPlace = place
        if fromPlace != nil {
            Task { await fetchRoutes() }
        } else {
            // 출발지가 비어 있으면 출발지 입력으로
            startSearch(target: .from)
        }
    }

    /// 즐겨찾기 칩(집/회사/저장장소) 탭. 현재 활성 입력 필드(searchTarget)에 채운다.
    /// - 출발 필드가 활성: 출발지로 들어감
    /// - 도착 필드가 활성(기본): 도착지로 들어감
    func useSavedPlace(_ place: Place) {
        switch searchTarget {
        case .from:
            fromPlace = place
            if toPlace != nil {
                appState = .home
                Task { await fetchRoutes() }
            } else {
                // 출발만 정해짐 → 도착 입력으로
                startSearch(target: .to)
            }
        case .to:
            useAsDestination(place)
        }
    }

    /// 홈에서 입력 필드(출발/도착)를 선택만 한다(검색 시트는 열지 않음).
    /// 이후 칩을 누르면 이 필드에 채워진다.
    func focusField(_ target: SearchTarget) {
        searchTarget = target
    }

    func onSearchQueryChanged(_ query: String) {
        searchTask?.cancel()
        guard !query.isEmpty else {
            searchResults = []
            return
        }
        searchTask = Task {
            try? await Task.sleep(nanoseconds: 300_000_000) // 300ms debounce
            guard !Task.isCancelled else { return }
            isSearching = true
            do {
                let results = try await kakao.searchPlaces(query: query)
                searchResults = results
            } catch {
                searchResults = []
            }
            isSearching = false
        }
    }

    func selectPlace(_ place: Place) {
        persistence.addRecentSearch(place)
        recentSearches = persistence.loadRecentSearches()

        // 빠른접근 칩에서 들어온 흐름이면 카테고리 부여해서 저장
        if let category = pendingSaveCategory {
            let categorized = Place(
                id: place.id, name: place.name, address: place.address,
                coordinate: place.coordinate, category: category
            )
            savePlace(categorized)
            pendingSaveCategory = nil
            useAsDestination(categorized)
            return
        }

        switch searchTarget {
        case .from: fromPlace = place
        case .to:   toPlace = place
        }

        if fromPlace != nil && toPlace != nil {
            // 출발/도착 다 있으면 바로 경로 탐색
            appState = .home
            Task { await fetchRoutes() }
        } else if toPlace != nil {
            // 목적지만 정해짐 → 출발지 입력으로 (기본 지도앱 길찾기 흐름)
            startSearch(target: .from)
        } else {
            appState = .home
        }
    }

    func swapPlaces() {
        let tmp = fromPlace
        fromPlace = toPlace
        toPlace = tmp
        if fromPlace != nil && toPlace != nil {
            Task { await fetchRoutes() }
        }
    }

    // MARK: - 경로 탐색

    func fetchRoutes() async {
        guard let from = fromPlace, let to = toPlace else { return }
        isLoadingRoutes = true
        defer { isLoadingRoutes = false }

        // 경로 저장 → 앱 껐다 켜도 유지
        let savedRoute = SavedRoute(from: from, to: to)
        persistence.saveLastRoute(savedRoute)

        // 거리 기반 모드 자동 판정: 80km 이상이면 인터시티(시외/고속/열차)로 진입
        let distanceMeters = haversineDistance(from: from.coordinate, to: to.coordinate)
        if distanceMeters > 80_000 {
            enterIntercity()
            return
        }

        do {
            let options = try await odsay.fetchBoardableOptions(from: from, to: to)
            if options.isEmpty {
                // ODsay 가 결과 없으면 인터시티로 fallback
                enterIntercity()
                return
            }
            boardableOptions = options
            appState = .waiting

            // 실시간 도착정보를 비동기로 채워넣기 (지하철은 스킵)
            Task { await refreshRealtimeArrivals() }
        } catch {
            // ODsay 실패 시도 인터시티 fallback
            enterIntercity()
        }
    }

    // MARK: - 좌표 거리 (Haversine, m)

    private func haversineDistance(from a: Coordinate, to b: Coordinate) -> Double {
        let R = 6_371_000.0
        let lat1 = a.lat * .pi / 180
        let lat2 = b.lat * .pi / 180
        let dLat = (b.lat - a.lat) * .pi / 180
        let dLng = (b.lng - a.lng) * .pi / 180
        let h = sin(dLat/2) * sin(dLat/2) +
                cos(lat1) * cos(lat2) * sin(dLng/2) * sin(dLng/2)
        return 2 * R * asin(min(1, sqrt(h)))
    }

    // MARK: - 실시간 도착 갱신
    //
    // ODsay 의 정류장 ID 와 국토부 TAGO 의 nodeId 는 다른 체계라서
    // 좌표 + 정류장명으로 매핑한 다음 도착정보를 받아온다.

    func refreshRealtimeArrivals() async {
        let busOptions = boardableOptions.enumerated().filter { $0.element.vehicle.type == .bus }
        guard !busOptions.isEmpty else { return }

        isRefreshingRealtime = true
        defer { isRefreshingRealtime = false }

        // 출발 정류장(이름)별로 그룹화 → 같은 정류장이면 한 번만 호출
        var byStop: [String: [Int]] = [:]   // 정류장명 → boardableOptions 인덱스들
        for (idx, opt) in busOptions {
            guard let name = opt.originStop?.name, !name.isEmpty else { continue }
            byStop[name, default: []].append(idx)
        }

        for (stopName, indices) in byStop {
            // 매핑 기준 좌표: 첫 옵션의 originStop 좌표 → 없으면 fromPlace
            let firstIdx = indices.first!
            let probeCoord: Coordinate? = boardableOptions[firstIdx].originStop?.coordinate ?? fromPlace?.coordinate
            guard let coord = probeCoord else { continue }

            do {
                let nearby = try await realtime.findStopsNear(coordinate: coord)
                // 이름 정확히 일치 우선, 없으면 첫 결과
                let matched = nearby.first(where: { $0.name == stopName }) ?? nearby.first
                guard let stop = matched else { continue }

                let arrivals = try await realtime.fetchArrivals(cityCode: stop.cityCode, nodeId: stop.nodeId)

                for idx in indices {
                    let routeNo = boardableOptions[idx].vehicle.number
                    let matching = arrivals
                        .filter { $0.routeNo == routeNo }
                        .sorted { $0.arrivalSeconds < $1.arrivalSeconds }
                    guard let first = matching.first else { continue }

                    boardableOptions[idx].arrivalMinutes = first.arrivalMinutes
                    if matching.count > 1 {
                        boardableOptions[idx].nextArrivalMinutes = matching[1].arrivalMinutes
                    }
                    // 실시간 위치 추적 위한 식별자 저장
                    boardableOptions[idx].routeId = first.routeId
                    boardableOptions[idx].cityCode = stop.cityCode
                }
            } catch {
                // 이 정류장은 스킵 (다른 정류장은 계속 시도)
                continue
            }
        }

        // 지하철도 같은 방식으로 갱신 (서울권)
        await refreshSubwayArrivals()

        // 도착 임박 순 재정렬 — 실시간 없는 건 뒤로
        boardableOptions.sort { ($0.arrivalMinutes ?? Int.max) < ($1.arrivalMinutes ?? Int.max) }
    }

    // MARK: - 지하철 실시간 갱신 (수도권 한정)

    private func refreshSubwayArrivals() async {
        let subwayOptions = boardableOptions.enumerated().filter { $0.element.vehicle.type == .subway }
        guard !subwayOptions.isEmpty else { return }

        // 출발역명별로 그룹화 → 같은 역이면 한 번만 호출
        var byStation: [String: [Int]] = [:]
        for (idx, opt) in subwayOptions {
            guard let name = opt.originStop?.name, !name.isEmpty else { continue }
            byStation[name, default: []].append(idx)
        }

        for (stationName, indices) in byStation {
            do {
                let arrivals = try await seoulSubway.fetchArrivals(stationName: stationName)
                guard !arrivals.isEmpty else { continue }

                for idx in indices {
                    // ODsay 가 준 노선명(예: "수도권2호선") 을 정규화해서 매칭
                    let odsayLine = SubwayLineMap.normalize(boardableOptions[idx].vehicle.number)
                    let matching = arrivals
                        .filter { $0.lineName == odsayLine }
                        .sorted { $0.arrivalSeconds < $1.arrivalSeconds }
                    guard let first = matching.first else { continue }

                    boardableOptions[idx].arrivalMinutes = first.arrivalMinutes
                    if matching.count > 1 {
                        boardableOptions[idx].nextArrivalMinutes = matching[1].arrivalMinutes
                    }
                }
            } catch {
                continue  // 다른 역은 계속 시도
            }
        }
    }

    // MARK: - 경로 빼기 / 되돌리기

    func excludeOption(_ option: BoardableOption) {
        excludedKeys.insert(option.exclusionKey)
    }

    func clearExclusions() {
        excludedKeys.removeAll()
    }

    // MARK: - 탑승

    func boardVehicle(_ option: BoardableOption) {
        selectedOption = option
        boardedAt = Date()
        arrivedAt = nil
        appState = .onboard
        // 버스면 실시간 위치 추적 자동 시작
        if option.vehicle.type == .bus,
           let routeId = option.routeId,
           let cityCode = option.cityCode {
            startBusTracking(cityCode: cityCode, routeId: routeId)
        }
    }

    func exitOnboard() {
        stopBusTracking()
        selectedOption = nil
        appState = .waiting
    }

    // MARK: - 도착 완료
    //
    // 트리거: 사용자가 "내렸어요/도착" 탭 (또는 목적지 근접 감지). 차량 추적은 멈추되
    // selectedOption / fromPlace / toPlace 는 여정 요약을 위해 유지한다. goHome 에서 초기화.

    func arrive() {
        stopBusTracking()
        arrivedAt = Date()
        appState = .arrived
    }

    // MARK: - 정류소까지 도보 안내 (① → ②)
    //
    // 출발 정류장 그룹을 고른 뒤 그 정류장까지 걷는 구간. "정류소 도착" 선언 시 ② 대기 화면으로.

    func walkToStop(_ group: DepartureGroup) {
        walkingGroup = group
        appState = .walkingToStop
    }

    func arriveAtStop() {
        walkingGroup = nil
        appState = .waiting
    }

    // MARK: - 경로 이탈 → 재탐색
    //
    // 트리거: 위치 추적 경로 이탈 감지(현재는 OnboardView 긴급카드에서 수동 진입).
    // 출발=현위치(원래 fromPlace 유지), 도착=그대로. "다시 탐색"이면 현 시점 경로 재조회.

    func startReroute() {
        appState = .rerouting
    }

    func confirmReroute() {
        stopBusTracking()
        selectedOption = nil
        Task { await fetchRoutes() }   // 성공 시 .waiting 으로 전환됨
    }

    func cancelReroute() {
        // 탑승 중이었으면 다시 탑승 화면으로, 아니면 대기 화면으로
        appState = selectedOption != nil ? .onboard : .waiting
    }

    // MARK: - 환승 도보 (멀티 leg)
    //
    // 트리거: 탑승 후 경로(afterSteps)에 환승(transfer) 구간이 있을 때 하차 → 다음 정류소까지 도보.

    func startTransfer() {
        stopBusTracking()
        appState = .transferWalking
    }

    func arriveAtTransferStop() {
        // 다음 정류소 도착 → 다시 대기 화면에서 다음 수단 탑승
        selectedOption = nil
        appState = .waiting
    }

    // MARK: - 실시간 차량 위치 폴링

    func startBusTracking(cityCode: Int, routeId: String, intervalSeconds: TimeInterval = 15) {
        positionPollingTask?.cancel()
        livePositions = []
        positionPollingTask = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                do {
                    let positions = try await self.position.fetchBusPositions(
                        cityCode: cityCode,
                        routeId: routeId
                    )
                    self.livePositions = positions
                } catch {
                    // 무시. 다음 폴링 시도.
                }
                try? await Task.sleep(nanoseconds: UInt64(intervalSeconds * 1_000_000_000))
            }
        }
    }

    func stopBusTracking() {
        positionPollingTask?.cancel()
        positionPollingTask = nil
        livePositions = []
    }

    // MARK: - 저장 장소

    func savePlace(_ place: Place) {
        persistence.addPlace(place)
        savedPlaces = persistence.loadPlaces()
    }

    func removePlace(id: UUID) {
        persistence.removePlace(id: id)
        savedPlaces = persistence.loadPlaces()
    }

    // MARK: - 인터시티 (시외/고속/열차)

    /// 인터시티 모드 진입 — 도시 픽커 초기화 + 첫 탭의 도시 목록 로드
    func enterIntercity() {
        appState = .intercity
        intercityOrigin = nil
        intercityDest = nil
        intercityOptions = []
        intercityDestOptions = []
        Task { await loadIntercityOriginCities() }
    }

    /// 탭 변경 — origin/dest 초기화 후 도시 목록 재로드
    func setIntercityTab(_ tab: IntercityVehicleType) {
        guard tab != intercityTab else { return }
        intercityTab = tab
        intercityOrigin = nil
        intercityDest = nil
        intercityDestOptions = []
        intercityOptions = []
        Task { await loadIntercityOriginCities() }
    }

    func loadIntercityOriginCities() async {
        do {
            switch intercityTab {
            case .train:
                intercityOriginOptions = try await train.fetchCities()
            case .suburbBus, .expressBus:
                intercityOriginOptions = try await intercityBus.fetchOriginCities(type: intercityTab)
            }
        } catch {
            intercityOriginOptions = []
        }
    }

    func selectIntercityOrigin(_ city: IntercityCity) {
        intercityOrigin = city
        intercityDest = nil
        intercityOptions = []
        Task { await loadIntercityDestCities() }
    }

    func loadIntercityDestCities() async {
        guard let origin = intercityOrigin else { return }
        do {
            switch intercityTab {
            case .train:
                // 열차는 도착도시도 전체 도시 목록에서 선택
                intercityDestOptions = try await train.fetchCities().filter { $0.code != origin.code }
            case .suburbBus, .expressBus:
                intercityDestOptions = try await intercityBus.fetchDestCities(type: intercityTab, originCode: origin.code)
            }
        } catch {
            intercityDestOptions = []
        }
    }

    func selectIntercityDest(_ city: IntercityCity) {
        intercityDest = city
        Task { await loadIntercitySchedule() }
    }

    func loadIntercitySchedule() async {
        guard let origin = intercityOrigin, let dest = intercityDest else { return }
        isLoadingIntercity = true
        defer { isLoadingIntercity = false }

        do {
            switch intercityTab {
            case .train:
                intercityOptions = try await train.fetchScheduleByCity(
                    originCity: origin, destCity: dest, date: intercityDate
                )
            case .suburbBus, .expressBus:
                intercityOptions = try await intercityBus.fetchSchedule(
                    type: intercityTab, origin: origin, dest: dest, date: intercityDate
                )
            }
        } catch {
            intercityOptions = []
        }
    }

    // MARK: - 홈으로

    func goHome() {
        appState = .home
        boardableOptions = []
        selectedOption = nil
        excludedKeys = []
        boardedAt = nil
        arrivedAt = nil
        walkingGroup = nil
        intercityOptions = []
        intercityOrigin = nil
        intercityDest = nil
    }
}

import SwiftUI
import MapKit

struct HomeView: View {
    @EnvironmentObject var vm: TransitViewModel
    @StateObject private var location = LocationManager.shared
    @StateObject private var mapController = MapController.shared

    var body: some View {
        ZStack(alignment: .bottom) {
            // MARK: - 지도 (항상 배경)
            MapView(positions: vm.livePositions,
                    routeLines: vm.routeLines,
                    routePoints: vm.mapRoutePoints,
                    routeVersion: vm.routeVersion,
                    controller: mapController)
                .ignoresSafeArea()

            // MARK: - 우측 지도 컨트롤 (내 위치) — 홈에서만
            if vm.appState == .home {
                VStack {
                    Spacer()
                    HStack {
                        Spacer()
                        LocateButton(denied: location.isDenied) {
                            if location.isDenied {
                                openSettings()
                            } else {
                                location.start()
                                mapController.recenter()
                            }
                        }
                    }
                    .padding(.trailing, 16)
                    .padding(.bottom, 12)
                }
                .transition(.opacity)
            }

            // MARK: - 홈: 하단 출발/도착 카드 (기본 지도앱 스타일)
            if vm.appState == .home {
                HomeSearchBar()
                    .transition(.move(edge: .bottom))
            }
        }
        .onAppear { location.start() }
        // 여정 상태/고른 경로가 바뀔 때마다 추천 경로 폴리라인을 다시 그림
        .task(id: geometryKey) { await loadRouteGeometry() }
        // MARK: - 검색은 네이티브 모달 시트로
        .sheet(isPresented: Binding(
            get: { vm.appState == .searching },
            set: { presented in
                // 사용자가 시트를 직접 내렸을 때만 홈으로. 장소 선택 후
                // fetchRoutes 가 이미 .routes/.intercity 로 넘어간 경우엔
                // 늦게 도착한 dismiss 콜백이 그 상태를 .home 으로 덮어쓰지 않게 한다.
                if !presented && vm.appState == .searching {
                    vm.appState = .home
                    vm.pendingSaveCategory = nil
                }
            }
        )) {
            SearchSheet()
                .environmentObject(vm)
        }
    }

    private func openSettings() {
        if let url = URL(string: UIApplication.openSettingsURLString) {
            UIApplication.shared.open(url)
        }
    }

    // MARK: - 추천 경로 폴리라인 로딩

    /// 여정 상태 + 그릴 경로가 바뀔 때마다 변하는 키. .task(id:) 트리거용.
    private var geometryKey: String {
        "\(vm.appState)|\(currentRouteOption()?.id.uuidString ?? "none")"
    }

    /// 지도에 그릴 경로 1개: 고른 경로(chosenOptionID) 우선, 없으면 가장 빠른(총소요 최소) 경로.
    private func currentRouteOption() -> BoardableOption? {
        if let id = vm.chosenOptionID,
           let chosen = vm.boardableOptions.first(where: { $0.id == id }) {
            return chosen
        }
        return vm.boardableOptions
            .filter { !vm.excludedKeys.contains($0.exclusionKey) }
            .min(by: { $0.totalMinutes < $1.totalMinutes })
    }

    /// 여정 중이면 추천 경로 폴리라인을 받아와 지도에 그리고, 아니면 지움.
    @MainActor
    private func loadRouteGeometry() async {
        let isJourney: Bool
        switch vm.appState {
        case .routes, .waiting, .walkingToStop, .onboard, .transferWalking, .rerouting:
            isJourney = true
        default:
            isJourney = false
        }
        guard isJourney else {
            vm.routeLines = []
            return
        }

        // 마커(출발·도착·정류장)만으로도 먼저 지도 영역을 맞추도록 트리거
        vm.routeVersion &+= 1

        guard let option = currentRouteOption(), let mapObj = option.mapObj else {
            vm.routeLines = []
            return
        }

        do {
            let lines = try await ODsayService.shared.fetchRouteGraphic(
                mapObj: mapObj, colorHex: option.vehicle.lineColor
            )
            vm.routeLines = lines
            vm.routeVersion &+= 1   // 선까지 포함해 영역 재맞춤
        } catch {
            vm.routeLines = []      // 실패해도 마커 영역 맞춤은 유지
        }
    }
}

// MARK: - 내 위치 버튼 (Apple Maps 스타일)

struct LocateButton: View {
    let denied: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: denied ? "location.slash.fill" : "location.fill")
                .font(.system(size: 17, weight: .semibold))
                .foregroundColor(denied ? .secondary : .appBlue)
                .frame(width: 44, height: 44)
                .background(
                    Circle()
                        .fill(Color(.systemBackground))
                        .shadow(color: .black.opacity(0.15), radius: 8, y: 2)
                )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - 지도 명령 컨트롤러 (recenter)

final class MapController: ObservableObject {
    static let shared = MapController()

    weak var mapView: MKMapView?

    /// 간판으로 구한 방위각이 화면 위쪽이 되도록 지도를 한 번 회전 (정면 = 위).
    /// 내 위치를 중심에 두고 걷기 좋은 줌으로 맞춘다.
    func orient(toHeading heading: Double, center: Coordinate?) {
        guard let map = mapView else { return }
        let target: CLLocationCoordinate2D
        if let c = center {
            target = CLLocationCoordinate2D(latitude: c.lat, longitude: c.lng)
        } else if let loc = map.userLocation.location {
            target = loc.coordinate
        } else {
            target = map.centerCoordinate
        }
        let cam = MKMapCamera(lookingAtCenter: target, fromDistance: 500, pitch: 0, heading: heading)
        map.setCamera(cam, animated: true)
    }

    /// 내 위치로 재중앙. 위치를 모르면 추적 모드(follow)로 전환.
    func recenter() {
        guard let map = mapView else { return }
        if let loc = map.userLocation.location {
            let region = MKCoordinateRegion(
                center: loc.coordinate,
                latitudinalMeters: 800,
                longitudinalMeters: 800
            )
            map.setRegion(region, animated: true)
        } else {
            map.setUserTrackingMode(.follow, animated: true)
        }
    }
}

// MARK: - 지도

struct MapView: UIViewRepresentable {
    var positions: [BusPosition] = []
    var routeLines: [RouteLine] = []
    var routePoints: [RoutePoint] = []
    var routeVersion: Int = 0
    var controller: MapController? = nil

    func makeUIView(context: Context) -> MKMapView {
        let map = MKMapView()
        map.showsUserLocation = true
        map.mapType = .standard
        map.delegate = context.coordinator
        map.showsCompass = true
        // 서울 기본 위치
        let region = MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 37.5511, longitude: 126.9258),
            span: MKCoordinateSpan(latitudeDelta: 0.02, longitudeDelta: 0.02)
        )
        map.setRegion(region, animated: false)
        controller?.mapView = map
        return map
    }

    func updateUIView(_ uiView: MKMapView, context: Context) {
        let coord = context.coordinator

        // 1) 실시간 버스 핀
        let oldBus = uiView.annotations.compactMap { $0 as? BusAnnotation }
        uiView.removeAnnotations(oldBus)
        uiView.addAnnotations(positions.map { BusAnnotation(position: $0) })

        // 2) 경로 지점 핀 (출발 / 도착 / 탑승 정류장)
        let oldPts = uiView.annotations.compactMap { $0 as? RoutePointAnnotation }
        uiView.removeAnnotations(oldPts)
        uiView.addAnnotations(routePoints.map { RoutePointAnnotation($0) })

        // 3) 경로 선
        let oldLines = uiView.overlays.compactMap { $0 as? MKPolyline }
        uiView.removeOverlays(oldLines)
        coord.lineStyles.removeAll()
        for line in routeLines {
            let cs = line.coordinates.map {
                CLLocationCoordinate2D(latitude: $0.lat, longitude: $0.lng)
            }
            guard cs.count >= 2 else { continue }
            let poly = MKPolyline(coordinates: cs, count: cs.count)
            coord.lineStyles[ObjectIdentifier(poly)] = (UIColor(hex: line.colorHex), line.dashed)
            uiView.addOverlay(poly)
        }

        // 4) routeVersion 이 바뀌면 경로(선+지점)가 다 보이게 영역 맞춤
        if routeVersion != coord.lastFittedVersion {
            coord.lastFittedVersion = routeVersion
            fitRoute(in: uiView)
        }
    }

    /// 경로 선과 지점을 모두 포함하도록 지도 영역을 맞춘다. 하단은 바텀시트가 가리므로 여백을 크게.
    private func fitRoute(in map: MKMapView) {
        let coords = routeLines.flatMap { $0.coordinates } + routePoints.map { $0.coordinate }
        guard !coords.isEmpty else { return }

        var rect = MKMapRect.null
        for c in coords {
            let p = MKMapPoint(CLLocationCoordinate2D(latitude: c.lat, longitude: c.lng))
            rect = rect.union(MKMapRect(origin: p, size: MKMapSize(width: 1, height: 1)))
        }
        guard !rect.isNull else { return }

        let bottomInset = max(140, map.bounds.height * 0.5)   // 바텀시트 가림 보정
        let insets = UIEdgeInsets(top: 90, left: 50, bottom: bottomInset, right: 50)
        map.setVisibleMapRect(rect, edgePadding: insets, animated: true)
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator: NSObject, MKMapViewDelegate {
        // 폴리라인별 (색, 점선여부). ObjectIdentifier 로 매핑.
        var lineStyles: [ObjectIdentifier: (UIColor, Bool)] = [:]
        var lastFittedVersion: Int = -1

        func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
            if let bus = annotation as? BusAnnotation {
                let id = "bus"
                let view = mapView.dequeueReusableAnnotationView(withIdentifier: id) as? MKMarkerAnnotationView
                    ?? MKMarkerAnnotationView(annotation: bus, reuseIdentifier: id)
                view.annotation = bus
                view.markerTintColor = .systemBlue
                view.glyphImage = UIImage(systemName: "bus.fill")
                view.canShowCallout = true
                return view
            }

            if let pt = annotation as? RoutePointAnnotation {
                let id = "routePoint"
                let view = mapView.dequeueReusableAnnotationView(withIdentifier: id) as? MKMarkerAnnotationView
                    ?? MKMarkerAnnotationView(annotation: pt, reuseIdentifier: id)
                view.annotation = pt
                view.canShowCallout = true
                switch pt.point.kind {
                case .origin:
                    view.markerTintColor = UIColor(hex: "#8a8a8e")
                    view.glyphImage = UIImage(systemName: "circle.circle.fill")
                    view.displayPriority = .defaultHigh
                case .destination:
                    view.markerTintColor = UIColor(hex: "#bf5af2")
                    view.glyphImage = UIImage(systemName: "mappin")
                    view.displayPriority = .required
                case .stop:
                    view.markerTintColor = UIColor(hex: "#0a84ff")
                    view.glyphImage = UIImage(systemName: "figure.walk")
                    view.displayPriority = .required
                }
                return view
            }

            return nil   // MKUserLocation 등은 기본 표시(파란 점)
        }

        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            guard let poly = overlay as? MKPolyline else {
                return MKOverlayRenderer(overlay: overlay)
            }
            let r = MKPolylineRenderer(polyline: poly)
            let style = lineStyles[ObjectIdentifier(poly)]
            r.strokeColor = (style?.0 ?? .systemBlue).withAlphaComponent(0.9)
            r.lineWidth = 5
            r.lineCap = .round
            r.lineJoin = .round
            if style?.1 == true { r.lineDashPattern = [2, 8] }
            return r
        }
    }
}

// MARK: - 경로 지점 어노테이션 (출발/도착/정류장)

final class RoutePointAnnotation: NSObject, MKAnnotation {
    let point: RoutePoint
    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: point.coordinate.lat, longitude: point.coordinate.lng)
    }
    var title: String? { point.title }
    init(_ point: RoutePoint) { self.point = point }
}

// MARK: - UIColor hex (지도 오버레이용 — Color(hex:) 의 UIKit 짝)

extension UIColor {
    convenience init(hex: String) {
        let h = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        var int: UInt64 = 0
        Scanner(string: h).scanHexInt64(&int)
        let r, g, b: UInt64
        switch h.count {
        case 6: (r, g, b) = (int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default: (r, g, b) = (10, 132, 255)   // 폴백: appBlue
        }
        self.init(red: CGFloat(r) / 255, green: CGFloat(g) / 255, blue: CGFloat(b) / 255, alpha: 1)
    }
}

// MARK: - 버스 위치 어노테이션

final class BusAnnotation: NSObject, MKAnnotation {
    let position: BusPosition
    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: position.coordinate.lat, longitude: position.coordinate.lng)
    }
    var title: String? { "\(position.routeNo)번" }
    var subtitle: String? { position.lastStopName.map { "직전: \($0)" } }

    init(position: BusPosition) {
        self.position = position
    }
}

// MARK: - 홈 하단 출발/도착 카드 (기본 지도앱 스타일, 항상 떠 있음)

struct HomeSearchBar: View {
    @EnvironmentObject var vm: TransitViewModel

    private let rowHeight: CGFloat = 56
    private let iconWidth: CGFloat = 24
    private let cardHPadding: CGFloat = 18

    var body: some View {
        VStack(spacing: 10) {
            RouteInputCard
            QuickPlacesBar()
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 6)
    }

    private var RouteInputCard: some View {
        VStack(spacing: 0) {
            // 출발지
            Button(action: { vm.startSearch(target: .from) }) {
                HStack(spacing: 12) {
                    Image(systemName: "circle")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(Color(.systemGray2))
                        .frame(width: iconWidth)
                    Text(vm.fromPlace?.name ?? "출발지")
                        .font(.system(size: 17, weight: .medium))
                        .foregroundColor(vm.fromPlace == nil ? Color(.placeholderText) : .primary)
                        .lineLimit(1)
                    Spacer(minLength: 8)
                }
            }
            .buttonStyle(.plain)
            .frame(height: rowHeight)
            .overlay(alignment: .trailing) {
                if vm.fromPlace != nil {
                    Button {
                        vm.fromPlace = nil
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 18))
                            .foregroundColor(.secondary)
                            .frame(width: 32, height: 32)
                    }
                    .buttonStyle(.plain)
                }
            }

            Divider().padding(.leading, iconWidth + 12)

            // 도착지
            Button(action: { vm.startSearch(target: .to) }) {
                HStack(spacing: 12) {
                    Image(systemName: "mappin.circle.fill")
                        .font(.system(size: 18))
                        .foregroundColor(.red)
                        .frame(width: iconWidth)
                    Text(vm.toPlace?.name ?? "도착지")
                        .font(.system(size: 17, weight: .medium))
                        .foregroundColor(vm.toPlace == nil ? Color(.placeholderText) : .primary)
                        .lineLimit(1)
                    Spacer(minLength: 8)
                }
            }
            .buttonStyle(.plain)
            .frame(height: rowHeight)
            .overlay(alignment: .trailing) {
                HStack(spacing: 2) {
                    if vm.toPlace != nil {
                        Button {
                            vm.toPlace = nil
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 18))
                                .foregroundColor(.secondary)
                                .frame(width: 32, height: 32)
                        }
                        .buttonStyle(.plain)
                    }
                    Button(action: vm.swapPlaces) {
                        Image(systemName: "arrow.up.arrow.down")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(.secondary)
                            .frame(width: 32, height: 32)
                    }
                }
            }
        }
        .padding(.horizontal, cardHPadding)
        .background(
            RoundedRectangle(cornerRadius: 26)
                .fill(Color(.systemBackground))
                .shadow(color: .black.opacity(0.15), radius: 14, y: 4)
        )
        // 출발·도착 잇는 점선 커넥터
        .overlay(alignment: .topLeading) {
            VStack(spacing: 3) {
                ForEach(0..<3, id: \.self) { _ in
                    Circle()
                        .fill(Color(.systemGray3))
                        .frame(width: 3, height: 3)
                }
            }
            .frame(width: iconWidth)
            .padding(.leading, cardHPadding)
            .offset(y: rowHeight - 7.5)
        }
    }
}

// MARK: - 빠른 접근 칩 바 (집/회사/즐겨찾기)

struct QuickPlacesBar: View {
    @EnvironmentObject var vm: TransitViewModel

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                // 집
                QuickChip(
                    emoji: "🏠",
                    label: vm.homePlace?.name ?? "집",
                    isPlaceholder: vm.homePlace == nil,
                    onTap: {
                        if let home = vm.homePlace {
                            vm.useSavedPlace(home)
                        } else {
                            vm.startAddingPlace(category: .home)
                        }
                    },
                    onDelete: vm.homePlace.map { p in { vm.removePlace(id: p.id) } }
                )

                // 회사
                QuickChip(
                    emoji: "💼",
                    label: vm.workPlace?.name ?? "회사",
                    isPlaceholder: vm.workPlace == nil,
                    onTap: {
                        if let work = vm.workPlace {
                            vm.useSavedPlace(work)
                        } else {
                            vm.startAddingPlace(category: .work)
                        }
                    },
                    onDelete: vm.workPlace.map { p in { vm.removePlace(id: p.id) } }
                )

                // 즐겨찾기
                ForEach(vm.favoritePlaces) { place in
                    QuickChip(
                        emoji: "⭐",
                        label: place.name,
                        isPlaceholder: false,
                        onTap: { vm.useSavedPlace(place) },
                        onDelete: { vm.removePlace(id: place.id) }
                    )
                }

                // 추가
                Button(action: { vm.startAddingPlace(category: .favorite) }) {
                    Image(systemName: "plus")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(.ultraThinMaterial, in: Capsule())
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 12)
        }
    }
}

struct QuickChip: View {
    let emoji: String
    let label: String
    let isPlaceholder: Bool
    let onTap: () -> Void
    let onDelete: (() -> Void)?

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 6) {
                Text(emoji)
                    .font(.system(size: 13))
                Text(label)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(isPlaceholder ? .secondary : .primary)
                    .lineLimit(1)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(.ultraThinMaterial, in: Capsule())
        }
        .buttonStyle(.plain)
        .contextMenu {
            if let onDelete {
                Button(role: .destructive, action: onDelete) {
                    Label("삭제", systemImage: "trash")
                }
            }
        }
    }
}

// MARK: - 검색 모달 시트 (네이티브 .sheet 로 표시)

struct SearchSheet: View {
    @EnvironmentObject var vm: TransitViewModel
    @State private var query: String = ""
    @FocusState private var focused: Bool

    private var searchPlaceholder: String {
        switch vm.pendingSaveCategory {
        case .home: return "집으로 등록할 장소 검색"
        case .work: return "회사로 등록할 장소 검색"
        case .favorite: return "즐겨찾기에 추가할 장소 검색"
        case .general, .none:
            return vm.searchTarget == .from ? "출발지 검색" : "도착지 검색"
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // 결과 목록 — 키보드/입력창 위에 뜸
            ScrollView {
                LazyVStack(spacing: 0) {
                    if query.isEmpty {
                        if vm.pendingSaveCategory == nil {
                            quickChipsSection
                        }
                        savedPlacesSection
                        recentSection
                    } else {
                        searchResultsSection
                    }
                }
            }

            Divider()

            // 입력창 + 취소 — 화면 아래(키보드 바로 위)
            HStack(spacing: 12) {
                HStack(spacing: 8) {
                    Circle()
                        .fill(vm.searchTarget == .from ? Color.blue : Color.purple)
                        .frame(width: 9, height: 9)
                    TextField(searchPlaceholder, text: $query)
                        .focused($focused)
                        .font(.system(size: 16))
                        .autocorrectionDisabled()
                        .submitLabel(.search)
                        .onChange(of: query) { vm.onSearchQueryChanged($0) }
                    if !query.isEmpty {
                        Button(action: { query = "" }) {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(.secondary)
                        }
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 11)
                .background(Color(.secondarySystemBackground), in: Capsule())

                Button("취소") {
                    vm.appState = .home
                    vm.pendingSaveCategory = nil
                }
                .font(.system(size: 16))
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 18)
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        // 목적지 선택 후 출발지 입력으로 넘어갈 때 입력 초기화
        .onChange(of: vm.searchTarget) { _ in query = "" }
        .task {
            // 시트가 다 뜬 뒤 포커스 → 키보드가 매끄럽게 올라옴
            try? await Task.sleep(nanoseconds: 250_000_000)
            focused = true
        }
    }

    // MARK: - 빠른 장소 칩 (시트 안) — 활성 필드(출발/도착)에 채움

    var quickChipsSection: some View {
        Group {
            if vm.homePlace != nil || vm.workPlace != nil || !vm.favoritePlaces.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        if let home = vm.homePlace {
                            sheetChip(emoji: "🏠", label: home.name) { vm.useSavedPlace(home) }
                        }
                        if let work = vm.workPlace {
                            sheetChip(emoji: "💼", label: work.name) { vm.useSavedPlace(work) }
                        }
                        ForEach(vm.favoritePlaces) { place in
                            sheetChip(emoji: "⭐", label: place.name) { vm.useSavedPlace(place) }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                }
            }
        }
    }

    private func sheetChip(emoji: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Text(emoji).font(.system(size: 13))
                Text(label).font(.system(size: 13, weight: .medium)).foregroundColor(.primary).lineLimit(1)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color(.secondarySystemBackground), in: Capsule())
        }
        .buttonStyle(.plain)
    }

    // MARK: - 저장 장소

    var savedPlacesSection: some View {
        Group {
            if !vm.savedPlaces.isEmpty {
                SectionHeader(title: "저장한 장소")
                ForEach(vm.savedPlaces) { place in
                    ResultRow(
                        icon: place.category.emoji,
                        name: place.name,
                        address: place.address
                    ) {
                        vm.selectPlace(place)
                    }
                }
                Divider().padding(.vertical, 4)
            }
        }
    }

    // MARK: - 최근 검색

    var recentSection: some View {
        Group {
            if !vm.recentSearches.isEmpty {
                SectionHeader(title: "최근 검색")
                ForEach(vm.recentSearches) { place in
                    ResultRow(
                        icon: "🕐",
                        name: place.name,
                        address: place.address
                    ) {
                        vm.selectPlace(place)
                    }
                }
            }
        }
    }

    // MARK: - 검색 결과

    var searchResultsSection: some View {
        Group {
            if vm.isSearching {
                HStack {
                    ProgressView()
                    Text("검색 중...")
                        .font(.system(size: 14))
                        .foregroundColor(.secondary)
                }
                .padding()
            } else {
                ForEach(vm.searchResults) { place in
                    ResultRow(
                        icon: "📍",
                        name: place.name,
                        address: place.address
                    ) {
                        vm.selectPlace(place)
                    }
                }
            }
        }
    }
}

// MARK: - 공통 컴포넌트

struct SectionHeader: View {
    let title: String
    var body: some View {
        HStack {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(.secondary)
                .textCase(.uppercase)
                .tracking(0.6)
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Color(.systemGroupedBackground))
    }
}

struct ResultRow: View {
    let icon: String
    let name: String
    let address: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Text(icon)
                    .font(.system(size: 16))
                    .frame(width: 36, height: 36)
                    .background(Color(.secondarySystemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 10))

                VStack(alignment: .leading, spacing: 2) {
                    Text(name)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundColor(.primary)
                    Text(address)
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 11)
        }
        .buttonStyle(.plain)

        Divider()
            .padding(.leading, 64)
    }
}

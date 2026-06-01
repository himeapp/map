import SwiftUI
import MapKit

struct HomeView: View {
    @EnvironmentObject var vm: TransitViewModel

    var body: some View {
        ZStack(alignment: .bottom) {
            // MARK: - 지도 (항상 배경)
            MapView(positions: vm.livePositions)
                .ignoresSafeArea()

            // MARK: - 홈: 하단 출발/도착 카드 (기본 지도앱 스타일)
            if vm.appState == .home {
                HomeSearchBar()
                    .transition(.move(edge: .bottom))
            }
        }
        // MARK: - 검색은 네이티브 모달 시트로
        .sheet(isPresented: Binding(
            get: { vm.appState == .searching },
            set: { presented in
                if !presented {
                    vm.appState = .home
                    vm.pendingSaveCategory = nil
                }
            }
        )) {
            SearchSheet()
                .environmentObject(vm)
        }
    }
}

// MARK: - 지도

struct MapView: UIViewRepresentable {
    var positions: [BusPosition] = []

    func makeUIView(context: Context) -> MKMapView {
        let map = MKMapView()
        map.showsUserLocation = true
        map.mapType = .standard
        map.delegate = context.coordinator
        // 서울 기본 위치
        let region = MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 37.5511, longitude: 126.9258),
            span: MKCoordinateSpan(latitudeDelta: 0.02, longitudeDelta: 0.02)
        )
        map.setRegion(region, animated: false)
        return map
    }

    func updateUIView(_ uiView: MKMapView, context: Context) {
        // 기존 버스 핀 정리하고 새로 그리기
        let oldBus = uiView.annotations.compactMap { $0 as? BusAnnotation }
        uiView.removeAnnotations(oldBus)

        let newBus = positions.map { BusAnnotation(position: $0) }
        uiView.addAnnotations(newBus)
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator: NSObject, MKMapViewDelegate {
        func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
            guard let bus = annotation as? BusAnnotation else { return nil }
            let id = "bus"
            let view = mapView.dequeueReusableAnnotationView(withIdentifier: id) as? MKMarkerAnnotationView
                ?? MKMarkerAnnotationView(annotation: bus, reuseIdentifier: id)
            view.annotation = bus
            view.markerTintColor = .systemBlue
            view.glyphImage = UIImage(systemName: "bus.fill")
            view.canShowCallout = true
            return view
        }
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
                Menu {
                    Button(role: .destructive) {
                        vm.fromPlace = nil
                        vm.toPlace = nil
                    } label: {
                        Label("출발·도착 지우기", systemImage: "xmark")
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.secondary)
                        .frame(width: 32, height: 32)
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
                Button(action: vm.swapPlaces) {
                    Image(systemName: "arrow.up.arrow.down")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.secondary)
                        .frame(width: 32, height: 32)
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
                            vm.useAsDestination(home)
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
                            vm.useAsDestination(work)
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
                        onTap: { vm.useAsDestination(place) },
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

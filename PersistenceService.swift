import Foundation

final class PersistenceService {
    static let shared = PersistenceService()
    private init() {}

    private let defaults = UserDefaults.standard
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    // MARK: - Keys
    private enum Key {
        static let lastRoute = "gaja_last_route"
        static let savedPlaces = "gaja_saved_places"
        static let recentSearches = "gaja_recent_searches"
    }

    // MARK: - 마지막 경로 (앱 껐다 켜도 유지되는 핵심 기능)

    func saveLastRoute(_ route: SavedRoute) {
        guard let data = try? encoder.encode(route) else { return }
        defaults.set(data, forKey: Key.lastRoute)
    }

    func loadLastRoute() -> SavedRoute? {
        guard let data = defaults.data(forKey: Key.lastRoute),
              let route = try? decoder.decode(SavedRoute.self, from: data) else { return nil }
        return route
    }

    func clearLastRoute() {
        defaults.removeObject(forKey: Key.lastRoute)
    }

    // MARK: - 저장된 장소 (집, 회사 등)

    func savePlaces(_ places: [Place]) {
        guard let data = try? encoder.encode(places) else { return }
        defaults.set(data, forKey: Key.savedPlaces)
    }

    func loadPlaces() -> [Place] {
        guard let data = defaults.data(forKey: Key.savedPlaces),
              let places = try? decoder.decode([Place].self, from: data) else { return [] }
        return places
    }

    func addPlace(_ place: Place) {
        var places = loadPlaces()
        places.removeAll { $0.id == place.id }
        // 집/회사는 하나만 — 같은 카테고리가 이미 있으면 교체
        if place.category == .home || place.category == .work {
            places.removeAll { $0.category == place.category }
        }
        places.append(place)
        savePlaces(places)
    }

    func removePlace(id: UUID) {
        var places = loadPlaces()
        places.removeAll { $0.id == id }
        savePlaces(places)
    }

    func removePlace(category: PlaceCategory) {
        var places = loadPlaces()
        places.removeAll { $0.category == category }
        savePlaces(places)
    }

    // MARK: - 최근 검색

    func saveRecentSearches(_ searches: [Place]) {
        let trimmed = Array(searches.prefix(10))
        guard let data = try? encoder.encode(trimmed) else { return }
        defaults.set(data, forKey: Key.recentSearches)
    }

    func loadRecentSearches() -> [Place] {
        guard let data = defaults.data(forKey: Key.recentSearches),
              let searches = try? decoder.decode([Place].self, from: data) else { return [] }
        return searches
    }

    func addRecentSearch(_ place: Place) {
        var searches = loadRecentSearches()
        searches.removeAll { $0.name == place.name }
        searches.insert(place, at: 0)
        saveRecentSearches(searches)
    }
}

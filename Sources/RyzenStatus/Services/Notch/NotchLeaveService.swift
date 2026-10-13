// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 RyzenStatus

import AppKit
import Combine
import CoreLocation
import MapKit

enum NotchLeaveTransport: String, CaseIterable, Identifiable {
    case automobile, walking, transit
    var id: String { rawValue }

    var directions: MKDirectionsTransportType {
        switch self {
        case .automobile: return .automobile
        case .walking: return .walking
        case .transit: return .transit
        }
    }

    var symbol: String {
        switch self {
        case .automobile: return "car.fill"
        case .walking: return "figure.walk"
        case .transit: return "tram.fill"
        }
    }
}

enum NotchLeaveSupport {
    /// Room kept for getting out of the door.
    static let buffer: TimeInterval = 5 * 60
    /// Only an event this close is worth asking the way to.
    static let lookahead: TimeInterval = 3 * 3600

    static func isEnabled(in defaults: UserDefaults = .standard) -> Bool {
        NotchSupport.routes(.leave, in: defaults)
    }

    static func transport(in defaults: UserDefaults = .standard) -> NotchLeaveTransport {
        NotchLeaveTransport(rawValue: defaults.string(forKey: DefaultsKey.notchLeaveTransport) ?? "") ?? .automobile
    }

    /// An online meeting has nowhere to travel to.
    static func isPlace(_ location: String) -> Bool {
        let text = location.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !text.isEmpty else { return false }
        let online = ["http://", "https://", "zoom.us", "meet.google", "teams.microsoft", "teams.live",
                      "webex", "facetime", "whereby.com", "discord.gg"]
        return !online.contains { text.contains($0) }
    }

    /// The next timed event somewhere else, starting within the lookahead.
    static func candidate(_ events: [NotchCalendarEvent], now: Date) -> NotchCalendarEvent? {
        events.filter { !$0.allDay && $0.start > now && $0.start.timeIntervalSince(now) <= lookahead
            && isPlace($0.location) }
            .min { $0.start < $1.start }
    }

    static func leaveAt(start: Date, travel: TimeInterval) -> Date {
        start.addingTimeInterval(-(travel + buffer))
    }
}

/// Before an event somewhere else, the island says when to set off, from the
/// travel time between here and there. The location is asked for only while
/// this is on, read once per plan, and never stored or sent anywhere but to
/// Apple Maps for the route.
final class NotchLeaveService: NSObject, CLLocationManagerDelegate {
    static let shared = NotchLeaveService()

    private var subscription: AnyCancellable?
    private var manager: CLLocationManager?
    private var timer: Timer?
    /// The event and transport the current plan was made for.
    private var planned: String?
    /// Plans already announced, so a refresh never repeats one.
    private var announced = Set<String>()
    private var waitingForLocation: [(CLLocation?) -> Void] = []
    private var search: MKLocalSearch?
    private var directions: MKDirections?

    func syncWithPreferences() {
        guard NotchLeaveSupport.isEnabled() else { stop(); return }
        if subscription == nil {
            subscription = NotchCalendarService.shared.$events.receive(on: DispatchQueue.main)
                .sink { [weak self] _ in self?.plan() }
        }
        plan()
    }

    func stop() {
        subscription = nil
        cancelPlan()
        planned = nil
        manager?.delegate = nil
        manager = nil
        flushLocation(nil)
    }

    private func cancelPlan() {
        timer?.invalidate(); timer = nil
        search?.cancel(); search = nil
        directions?.cancel(); directions = nil
    }

    private func plan() {
        let now = Date()
        let transport = NotchLeaveSupport.transport()
        guard let event = NotchLeaveSupport.candidate(NotchCalendarService.shared.events, now: now) else {
            cancelPlan(); planned = nil
            return
        }
        let key = event.id + "|" + event.location + "|" + transport.rawValue
        guard planned != key, !announced.contains(key) else { return }
        cancelPlan()
        planned = key
        locate { [weak self] here in
            guard let self, self.planned == key, let here else { return }
            self.destination(for: event, near: here) { [weak self] place in
                guard let self, self.planned == key, let place else { return }
                self.travelTime(from: here, to: place, by: transport) { [weak self] travel in
                    guard let self, self.planned == key, let travel else { return }
                    self.schedule(event: event, travel: travel, transport: transport, key: key)
                }
            }
        }
    }

    private func schedule(event: NotchCalendarEvent, travel: TimeInterval, transport: NotchLeaveTransport, key: String) {
        let leave = NotchLeaveSupport.leaveAt(start: event.start, travel: travel)
        let fire = { [weak self] in
            guard let self, self.planned == key, Date() < event.start else { return }
            self.announced.insert(key)
            self.announce(event: event, travel: travel, transport: transport)
        }
        guard leave > Date() else { fire(); return }
        let timer = Timer(fire: leave, interval: 0, repeats: false) { _ in fire() }
        timer.tolerance = 10
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func announce(event: NotchCalendarEvent, travel: TimeInterval, transport: NotchLeaveTransport) {
        let text = FeatureStrings.notchIslandExtras(L10n.shared.language)
        let minutes = max(1, Int((travel / 60).rounded()))
        let detail = String(format: text.travelMinutes, minutes) + " · " + event.title
        NotchService.shared.show(NotchNotice(event: .leave, title: text.timeToLeave, detail: detail,
                                             symbol: transport.symbol))
    }

    // MARK: Location

    private func locate(_ completion: @escaping (CLLocation?) -> Void) {
        let manager = self.manager ?? {
            let manager = CLLocationManager()
            manager.delegate = self
            manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
            self.manager = manager
            return manager
        }()
        waitingForLocation.append(completion)
        guard waitingForLocation.count == 1 else { return }
        switch manager.authorizationStatus {
        case .notDetermined: manager.requestWhenInUseAuthorization()
        case .denied, .restricted: flushLocation(nil)
        default: manager.requestLocation()
        }
    }

    private func flushLocation(_ location: CLLocation?) {
        let waiting = waitingForLocation
        waitingForLocation.removeAll()
        waiting.forEach { $0(location) }
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        guard !waitingForLocation.isEmpty else { return }
        switch manager.authorizationStatus {
        case .notDetermined: return
        case .denied, .restricted: flushLocation(nil)
        default: manager.requestLocation()
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        flushLocation(locations.last)
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        flushLocation(nil)
    }

    // MARK: Maps

    private func destination(for event: NotchCalendarEvent, near here: CLLocation,
                             completion: @escaping (MKMapItem?) -> Void) {
        if let latitude = event.latitude, let longitude = event.longitude {
            completion(Self.mapItem(at: CLLocation(latitude: latitude, longitude: longitude)))
            return
        }
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = event.location
        request.region = MKCoordinateRegion(center: here.coordinate, latitudinalMeters: 100_000,
                                            longitudinalMeters: 100_000)
        let search = MKLocalSearch(request: request)
        self.search = search
        search.start { response, _ in completion(response?.mapItems.first) }
    }

    private func travelTime(from here: CLLocation, to place: MKMapItem, by transport: NotchLeaveTransport,
                            completion: @escaping (TimeInterval?) -> Void) {
        let request = MKDirections.Request()
        request.source = Self.mapItem(at: here)
        request.destination = place
        request.transportType = transport.directions
        let directions = MKDirections(request: request)
        self.directions = directions
        directions.calculateETA { response, _ in
            completion(response.map(\.expectedTravelTime).flatMap { $0.isFinite && $0 > 0 ? $0 : nil })
        }
    }

    private static func mapItem(at location: CLLocation) -> MKMapItem {
        if #available(macOS 26, *) { return MKMapItem(location: location, address: nil) }
        return MKMapItem(placemark: MKPlacemark(coordinate: location.coordinate))
    }
}

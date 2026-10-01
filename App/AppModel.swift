import CoreLocation
import CoreMotion
import Observation
import SwiftUI
import UserNotifications

/// 화면이 바라보는 상태. 저장소와 세션 관리자의 변경 알림을 받아 다시 읽기만 한다.
@Observable
final class AppModel {
    private(set) var current: ParkingRecord?
    private(set) var history: [ParkingRecord] = []
    private(set) var settings = AppSettings()
    private(set) var calibration = Calibration()
    private(set) var isTracking = false
    private(set) var locationStatus: CLAuthorizationStatus = .notDetermined
    private(set) var motionStatus: CMAuthorizationStatus = .notDetermined
    private(set) var notificationsAllowed = false

    @ObservationIgnored private let store = ParkingStore.shared
    @ObservationIgnored private let session = ParkingSessionManager.shared
    @ObservationIgnored private var observers: [NSObjectProtocol] = []

    init() {
        let center = NotificationCenter.default
        for name in [Notification.Name.parkingStoreDidChange, .parkingSessionDidChange] {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                self?.reload()
            })
        }
        reload()
    }

    deinit {
        observers.forEach { NotificationCenter.default.removeObserver($0) }
    }

    func reload() {
        current = store.current
        history = store.history
        settings = store.settings
        calibration = store.calibration
        isTracking = session.isTracking
        locationStatus = session.locationStatus
        motionStatus = session.motionStatus
        UNUserNotificationCenter.current().getNotificationSettings { [weak self] result in
            let allowed = result.authorizationStatus == .authorized || result.authorizationStatus == .provisional
            DispatchQueue.main.async { self?.notificationsAllowed = allowed }
        }
    }

    // MARK: 준비 상태

    var isBarometerAvailable: Bool { session.isBarometerAvailable }
    var hasAlwaysLocation: Bool { locationStatus == .authorizedAlways }
    var hasMotion: Bool { motionStatus == .authorized }
    var isReady: Bool { settings.hasHome && hasAlwaysLocation && hasMotion }

    // MARK: 기록

    /// 층 선택 시트에서 고른 층을 반영한다. 기록이 있으면 수정(+학습), 없으면 수동 기록.
    func chooseFloor(_ level: Int) {
        if current != nil {
            store.correctCurrent(to: level)
        } else {
            store.recordManually(level: level)
        }
    }

    func recordManually(level: Int) { store.recordManually(level: level) }
    func confirmCurrent() { if let current { store.correctCurrent(to: current.level) } }
    func setMemo(_ memo: String) { store.setMemo(memo) }
    func clearCurrent() { store.clearCurrent() }
    func resetCalibration() { store.resetCalibration() }

    // MARK: 측정

    func startManualSession() { session.beginSession(manual: true) }
    func finishSession() { session.finishNow(reason: "직접 확정") }
    func cancelSession() { session.cancelSession() }
    var liveDepth: Double? { session.liveDepth }
    var log: [String] { store.log }

    // MARK: 설정

    func updateSettings(_ change: (inout AppSettings) -> Void) {
        var updated = store.settings
        change(&updated)
        guard updated != store.settings else { return }
        store.settings = updated
        session.syncMonitoring()
        store.notifyChanged()
    }

    func setHome(_ coordinate: CLLocationCoordinate2D) {
        updateSettings {
            $0.homeLatitude = coordinate.latitude
            $0.homeLongitude = coordinate.longitude
        }
    }

    func setHomeToCurrentLocation(completion: @escaping (Bool) -> Void) {
        session.requestCurrentLocation { [weak self] location in
            guard let location else { return completion(false) }
            self?.setHome(location.coordinate)
            completion(true)
        }
    }

    // MARK: 권한

    func requestLocationPermission() { session.requestLocationPermission() }
    func requestMotionPermission() { session.requestMotionPermission() }
    func requestNotificationPermission() { session.requestNotificationPermission() }
}

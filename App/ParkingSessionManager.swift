import AVFAudio
import CoreLocation
import CoreMotion
import UIKit
import UserNotifications

extension Notification.Name {
    /// 측정 상태·권한 상태가 바뀌었을 때
    static let parkingSessionDidChange = Notification.Name("parkingSessionDidChange")
}

enum CarPlayMonitor {
    /// 오디오 세션을 활성화하지 않고 현재 출력 경로만 읽는다 → 재생 중인 음악에 영향이 없다.
    /// 유선·무선 CarPlay 모두 `.carAudio` 로 잡힌다.
    static var isConnected: Bool {
        AVAudioSession.sharedInstance().currentRoute.outputs.contains { $0.portType == .carAudio }
    }
}

/// 자동 감지의 전부를 담당한다.
///
/// 평소에는 아무것도 실행하지 않는다. iOS의 지오펜스(셀/Wi-Fi 기반, 전력 소모 거의 없음)가
/// 집 근처 진입을 알려주면 그때만 깨어나서 주차할 때까지 몇 분 동안 기압계를 기록하고,
/// CarPlay 연결이 끊기는 순간 층을 계산해 저장한 뒤 다시 완전히 멈춘다.
///
/// 모든 콜백은 메인 스레드에서 처리한다.
final class ParkingSessionManager: NSObject, CLLocationManagerDelegate {
    static let shared = ParkingSessionManager()

    static let homeRegionID = "home"
    /// 주차를 못 찾고 헤매는 경우까지 감안한 최대 측정 시간
    static let maxSessionDuration: TimeInterval = 20 * 60
    /// 무선 CarPlay의 순간 끊김을 주차로 오인하지 않기 위한 대기 시간
    static let disconnectDebounce: TimeInterval = 3
    static let maxSamples = 1500

    private(set) var isTracking = false {
        didSet {
            if oldValue != isTracking {
                NotificationCenter.default.post(name: .parkingSessionDidChange, object: self)
            }
        }
    }

    private let location = CLLocationManager()
    private let altimeter = CMAltimeter()
    private let store = ParkingStore.shared

    private var samples: [AltitudeSample] = []
    private var sessionStart: Date?
    private var sawCarPlay = false
    private var disconnectedAt: TimeInterval?
    private var samplesAtDisconnect = 0
    private var escalateToAlways = false
    private var oneShot: ((CLLocation?) -> Void)?

    // MARK: 시작

    /// 앱이 (백그라운드 실행 포함) 시작될 때 한 번 호출한다.
    func activate() {
        location.delegate = self
        NotificationCenter.default.addObserver(self, selector: #selector(audioRouteChanged),
                                               name: AVAudioSession.routeChangeNotification, object: nil)
        syncMonitoring()
    }

    /// 설정에 맞춰 집 지오펜스를 등록/해제한다. 이미 같은 조건으로 등록돼 있으면 건드리지 않는다
    /// (지오펜스 이벤트로 깨어난 직후 다시 등록하면 대기 중인 이벤트를 잃을 수 있다).
    func syncMonitoring() {
        let settings = store.settings
        let existing = location.monitoredRegions
            .compactMap { $0 as? CLCircularRegion }
            .first { $0.identifier == Self.homeRegionID }

        guard settings.autoDetect,
              let latitude = settings.homeLatitude,
              let longitude = settings.homeLongitude,
              CLLocationManager.isMonitoringAvailable(for: CLCircularRegion.self) else {
            if let existing {
                location.stopMonitoring(for: existing)
                store.appendLog("집 주변 감지 해제")
            }
            return
        }

        let radius = min(settings.regionRadius, location.maximumRegionMonitoringDistance)
        if let existing,
           abs(existing.center.latitude - latitude) < 1e-6,
           abs(existing.center.longitude - longitude) < 1e-6,
           abs(existing.radius - radius) < 1 {
            return
        }

        let region = CLCircularRegion(center: CLLocationCoordinate2D(latitude: latitude, longitude: longitude),
                                      radius: radius, identifier: Self.homeRegionID)
        region.notifyOnEntry = true
        region.notifyOnExit = true
        location.startMonitoring(for: region)
        store.appendLog("집 주변 감지 등록 (반경 \(Int(radius))m)")
    }

    // MARK: 권한

    var locationStatus: CLAuthorizationStatus { location.authorizationStatus }
    var motionStatus: CMAuthorizationStatus { CMAltimeter.authorizationStatus() }
    var isBarometerAvailable: Bool { CMAltimeter.isRelativeAltitudeAvailable() }

    /// "앱 사용 중" → "항상" 순서로 요청한다. 백그라운드에서 깨어나려면 "항상"이 필요하다.
    func requestLocationPermission() {
        switch location.authorizationStatus {
        case .notDetermined:
            escalateToAlways = true
            location.requestWhenInUseAuthorization()
        case .authorizedWhenInUse:
            location.requestAlwaysAuthorization()
        default:
            break
        }
    }

    /// 기압계를 잠깐 켰다 꺼서 "동작 및 피트니스" 권한 창을 띄운다.
    func requestMotionPermission() {
        guard isBarometerAvailable, !isTracking else { return }
        altimeter.startRelativeAltitudeUpdates(to: .main) { [weak self] _, _ in
            guard let self, !self.isTracking else { return }
            self.altimeter.stopRelativeAltitudeUpdates()
            NotificationCenter.default.post(name: .parkingSessionDidChange, object: self)
        }
    }

    func requestNotificationPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in
            DispatchQueue.main.async {
                NotificationCenter.default.post(name: .parkingSessionDidChange, object: self)
            }
        }
    }

    // MARK: 현재 위치 (집 위치 설정용)

    func requestCurrentLocation(_ completion: @escaping (CLLocation?) -> Void) {
        if let last = location.location, last.horizontalAccuracy >= 0, last.horizontalAccuracy <= 50,
           abs(last.timestamp.timeIntervalSinceNow) < 60 {
            completion(last)
            return
        }
        oneShot = completion
        if !isTracking { location.desiredAccuracy = kCLLocationAccuracyNearestTenMeters }
        location.requestLocation()
    }

    // MARK: 측정 세션

    /// - Parameter manual: 앱 화면에서 직접 시작한 경우. CarPlay 연결 여부를 따지지 않는다.
    @discardableResult
    func beginSession(manual: Bool) -> Bool {
        guard !isTracking else { return true }
        guard isBarometerAvailable else {
            store.appendLog("기압계를 쓸 수 없는 기기")
            return false
        }
        let connected = CarPlayMonitor.isConnected
        guard manual || connected else {
            store.appendLog("집 근처 진입 — CarPlay 미연결이라 건너뜀")
            return false
        }

        samples.removeAll(keepingCapacity: true)
        sessionStart = Date()
        sawCarPlay = connected
        disconnectedAt = nil
        samplesAtDisconnect = 0
        isTracking = true

        // 위치 업데이트는 백그라운드 실행을 유지하는 용도일 뿐이다.
        // 정확도를 최저로 둬서 GPS 칩을 켜지 않는다 (지하에서는 어차피 GPS가 안 잡힌다).
        location.desiredAccuracy = kCLLocationAccuracyThreeKilometers
        location.distanceFilter = kCLDistanceFilterNone
        location.pausesLocationUpdatesAutomatically = false
        location.allowsBackgroundLocationUpdates = true
        location.startUpdatingLocation()

        altimeter.startRelativeAltitudeUpdates(to: .main) { [weak self] data, _ in
            guard let self, self.isTracking, let data else { return }
            self.samples.append(AltitudeSample(t: data.timestamp, altitude: data.relativeAltitude.doubleValue))
            if self.samples.count > Self.maxSamples {
                self.samples.removeFirst(self.samples.count - Self.maxSamples)
            }
            self.tick()
        }

        store.appendLog(manual ? "수동 측정 시작" : "집 근처 진입 — 측정 시작")
        return true
    }

    /// 지금 위치를 주차 위치로 확정한다 (앱의 "여기 주차했어요" 버튼, 단축어 자동화).
    @discardableResult
    func finishNow(reason: String) -> ParkingRecord? {
        if isTracking { return finish(reason: reason, sampleCount: nil) }
        // 자동 감지와 단축어가 거의 동시에 동작한 경우: 방금 저장된 기록을 그대로 돌려준다.
        if let current = store.current, Date().timeIntervalSince(current.date) < 180 { return current }
        return nil
    }

    func cancelSession() {
        if isTracking { endSession(log: "측정 취소") }
    }

    /// 측정 중일 때 현재까지 내려온 깊이(m) — 화면 표시용
    var liveDepth: Double? {
        isTracking ? FloorEstimator.depth(from: samples) : nil
    }

    /// 기압계 표본이 들어올 때마다(약 1초 간격) 호출된다. 별도 타이머를 두지 않는다.
    private func tick() {
        guard isTracking else { return }
        let now = ProcessInfo.processInfo.systemUptime

        if CarPlayMonitor.isConnected {
            sawCarPlay = true
            disconnectedAt = nil
        } else if sawCarPlay {
            if disconnectedAt == nil {
                disconnectedAt = now
                samplesAtDisconnect = samples.count
            }
            if let since = disconnectedAt, now - since >= Self.disconnectDebounce {
                finish(reason: "CarPlay 해제", sampleCount: samplesAtDisconnect)
                return
            }
        }

        if let start = sessionStart, Date().timeIntervalSince(start) > Self.maxSessionDuration {
            endSession(log: "시간 초과로 측정 종료")
        }
    }

    @discardableResult
    private func finish(reason: String, sampleCount: Int?) -> ParkingRecord? {
        // 저장과 알림이 끝나기 전에 앱이 중단되지 않도록 잠깐 시간을 확보한다.
        let task = UIApplication.shared.beginBackgroundTask(withName: "finish-parking")
        defer {
            if task != .invalid {
                DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                    UIApplication.shared.endBackgroundTask(task)
                }
            }
        }

        let all = samples
        let untilDisconnect = sampleCount.map { Array(all.prefix($0)) } ?? all
        let duration = sessionStart.map { Date().timeIntervalSince($0) } ?? 0
        endSession(log: nil)

        guard let depth = FloorEstimator.depth(from: untilDisconnect) ?? FloorEstimator.depth(from: all) else {
            store.appendLog("\(reason) — 표본 부족으로 층 계산 실패 (\(all.count)개)")
            return nil
        }

        var result = FloorEstimator.classify(depth: depth, settings: store.settings, calibration: store.calibration)
        // 측정이 너무 짧으면 이미 지하에 들어온 뒤에 시작됐을 수 있다.
        if duration < 30 { result.confidence = .low }

        let record = ParkingRecord(date: Date(), level: result.level, depth: depth,
                                   confidence: result.confidence, source: .auto)
        store.save(record)
        store.appendLog("\(reason) — 깊이 \(String(format: "%.1f", depth))m → \(FloorStyle.short(record.level)) "
                        + "(신뢰도 \(record.confidence.rawValue), 표본 \(all.count)개, \(Int(duration))초)")
        notify(record)
        return record
    }

    private func endSession(log message: String?) {
        altimeter.stopRelativeAltitudeUpdates()
        location.stopUpdatingLocation()
        location.allowsBackgroundLocationUpdates = false
        samples.removeAll(keepingCapacity: false)
        sessionStart = nil
        sawCarPlay = false
        disconnectedAt = nil
        samplesAtDisconnect = 0
        isTracking = false
        if let message { store.appendLog(message) }
    }

    private func notify(_ record: ParkingRecord) {
        guard store.settings.notifyOnPark else { return }
        let content = UNMutableNotificationContent()
        content.title = FloorStyle.parkedSentence(record.level)
        content.body = record.confidence == .low
            ? "정확하지 않을 수 있어요. 층이 다르면 눌러서 고쳐 주세요."
            : "층이 다르면 눌러서 고쳐 주세요. 고칠수록 정확해져요."
        content.sound = .default
        let request = UNNotificationRequest(identifier: "parked", content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }

    @objc private func audioRouteChanged() {
        DispatchQueue.main.async { [weak self] in self?.tick() }
    }

    // MARK: CLLocationManagerDelegate

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        if escalateToAlways, manager.authorizationStatus == .authorizedWhenInUse {
            escalateToAlways = false
            manager.requestAlwaysAuthorization()
        }
        syncMonitoring()
        NotificationCenter.default.post(name: .parkingSessionDidChange, object: self)
    }

    func locationManager(_ manager: CLLocationManager, didEnterRegion region: CLRegion) {
        guard region.identifier == Self.homeRegionID else { return }
        beginSession(manual: false)
    }

    func locationManager(_ manager: CLLocationManager, didExitRegion region: CLRegion) {
        guard region.identifier == Self.homeRegionID, isTracking else { return }
        endSession(log: "집 주변을 벗어나 측정 종료")
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        if let handler = oneShot {
            oneShot = nil
            handler(locations.last)
        }
        tick()
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        if let handler = oneShot {
            oneShot = nil
            handler(nil)
        }
    }

    func locationManager(_ manager: CLLocationManager, monitoringDidFailFor region: CLRegion?, withError error: Error) {
        store.appendLog("집 주변 감지 실패: \(error.localizedDescription)")
    }
}

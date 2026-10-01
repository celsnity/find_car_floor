import Foundation
import WidgetKit

extension Notification.Name {
    /// 주차 기록·설정이 바뀌었을 때 (같은 프로세스 안에서만 전달)
    static let parkingStoreDidChange = Notification.Name("parkingStoreDidChange")
}

/// 앱과 위젯이 함께 쓰는 저장소 (App Group UserDefaults).
/// 데이터가 몇 KB 수준이라 DB 없이 JSON으로 충분하다.
final class ParkingStore {
    static let shared = ParkingStore()
    static let appGroup = "group.com.celsnity.parkfloor"
    static let widgetKind = "ParkFloorWidget"
    static let historyLimit = 30
    static let logLimit = 80

    private enum Key {
        static let current = "current"
        static let history = "history"
        static let settings = "settings"
        static let calibration = "calibration"
        static let log = "log"
    }

    private let defaults: UserDefaults
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(defaults: UserDefaults? = nil) {
        self.defaults = defaults ?? UserDefaults(suiteName: Self.appGroup) ?? .standard
    }

    // MARK: 읽기/쓰기

    var current: ParkingRecord? {
        get { load(ParkingRecord.self, Key.current) }
        set { store(newValue, Key.current) }
    }

    var history: [ParkingRecord] {
        get { load([ParkingRecord].self, Key.history) ?? [] }
        set { store(Array(newValue.prefix(Self.historyLimit)), Key.history) }
    }

    var settings: AppSettings {
        get { load(AppSettings.self, Key.settings) ?? AppSettings() }
        set { store(newValue, Key.settings) }
    }

    var calibration: Calibration {
        get { load(Calibration.self, Key.calibration) ?? Calibration() }
        set { store(newValue, Key.calibration) }
    }

    var log: [String] {
        get { defaults.stringArray(forKey: Key.log) ?? [] }
        set { defaults.set(Array(newValue.suffix(Self.logLimit)), forKey: Key.log) }
    }

    // MARK: 동작

    /// 새 주차 기록 저장
    func save(_ record: ParkingRecord) {
        current = record
        history = [record] + history.filter { $0.id != record.id }
        notifyChanged()
    }

    /// 현재 기록의 층을 바꾼다. 자동 측정 기록이면 그 깊이를 해당 층의 보정값으로 학습한다.
    func correctCurrent(to level: Int) {
        guard var record = current else { return }
        let clamped = clamp(level)
        if let depth = record.depth {
            var calibration = self.calibration
            calibration.add(depth: depth, for: clamped)
            self.calibration = calibration
        }
        record.corrected = record.corrected || record.level != clamped
        record.level = clamped
        record.confidence = .high
        replaceCurrent(with: record)
    }

    /// 위젯의 ▲▼ 버튼용
    func adjustCurrent(by delta: Int) {
        guard let record = current else { return }
        let target = clamp(record.level + delta)
        guard target != record.level else { return }
        correctCurrent(to: target)
    }

    func setMemo(_ memo: String) {
        guard var record = current else { return }
        record.memo = memo.trimmingCharacters(in: .whitespacesAndNewlines)
        replaceCurrent(with: record)
    }

    /// 수동 기록 ("지금 여기 주차")
    func recordManually(level: Int) {
        save(ParkingRecord(date: Date(), level: clamp(level), depth: nil, confidence: .high, source: .manual))
    }

    func clearCurrent() {
        current = nil
        notifyChanged()
    }

    func resetCalibration() {
        calibration = Calibration()
        notifyChanged()
    }

    func appendLog(_ message: String) {
        let stamp = Date().formatted(.dateTime.month(.twoDigits).day(.twoDigits).hour().minute().second())
        log = log + ["\(stamp)  \(message)"]
    }

    // MARK: 내부

    private func clamp(_ level: Int) -> Int {
        min(0, max(-settings.basementCount, level))
    }

    private func replaceCurrent(with record: ParkingRecord) {
        current = record
        var list = history
        if let index = list.firstIndex(where: { $0.id == record.id }) {
            list[index] = record
        } else {
            list.insert(record, at: 0)
        }
        history = list
        notifyChanged()
    }

    func notifyChanged() {
        WidgetCenter.shared.reloadTimelines(ofKind: Self.widgetKind)
        NotificationCenter.default.post(name: .parkingStoreDidChange, object: self)
    }

    private func load<T: Decodable>(_ type: T.Type, _ key: String) -> T? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? decoder.decode(type, from: data)
    }

    private func store<T: Encodable>(_ value: T?, _ key: String) {
        guard let value, let data = try? encoder.encode(value) else {
            defaults.removeObject(forKey: key)
            return
        }
        defaults.set(data, forKey: key)
    }
}

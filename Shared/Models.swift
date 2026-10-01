import Foundation

/// 층 표기 규칙: 0 = 지상, -1 = B1, -2 = B2 …
struct ParkingRecord: Codable, Equatable, Identifiable {
    enum Source: String, Codable { case auto, manual }
    enum Confidence: String, Codable { case high, medium, low }

    var id = UUID()
    var date: Date
    var level: Int
    /// 지면 대비 내려간 깊이(m). 자동 측정일 때만 존재.
    var depth: Double?
    var confidence: Confidence
    var source: Source
    var corrected = false
    var memo = ""
}

struct AppSettings: Codable, Equatable {
    var homeLatitude: Double?
    var homeLongitude: Double?
    /// 집 주변 감지 반경(m). 지하로 들어가기 전에 측정이 시작되도록 넉넉하게 잡는다.
    var regionRadius: Double = 400
    var basementCount: Int = 3
    /// 지면 → B1 깊이(m)
    var firstBasementDepth: Double = 4.5
    /// B1 이후 층간 높이(m)
    var floorHeight: Double = 3.3
    var autoDetect = true
    var notifyOnPark = true

    var hasHome: Bool { homeLatitude != nil && homeLongitude != nil }
}

/// 사용자가 확인/수정해 준 층별 실측 깊이. 층마다 최근 값 몇 개만 보관한다.
struct Calibration: Codable, Equatable {
    static let maxSamplesPerLevel = 6
    var samples: [Int: [Double]] = [:]

    var isEmpty: Bool { samples.values.allSatisfy(\.isEmpty) }

    mutating func add(depth: Double, for level: Int) {
        var list = samples[level, default: []]
        list.append(depth)
        if list.count > Self.maxSamplesPerLevel { list.removeFirst(list.count - Self.maxSamplesPerLevel) }
        samples[level] = list
    }

    /// 해당 층의 대표 깊이(중앙값)
    func centroid(for level: Int) -> Double? {
        guard let list = samples[level], !list.isEmpty else { return nil }
        return FloorEstimator.median(list)
    }
}

struct AltitudeSample: Equatable {
    /// 부팅 후 경과 시간(초) — CMAltitudeData.timestamp
    var t: TimeInterval
    /// 측정 시작점 대비 상대 고도(m)
    var altitude: Double
}

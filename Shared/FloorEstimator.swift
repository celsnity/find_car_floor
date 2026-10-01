import Foundation

/// 기압계 상대 고도 기록으로 주차 층을 추정한다. (Foundation 전용 — 순수 로직)
///
/// 원리: 집 근처에 들어온 뒤부터 주차할 때까지의 고도 기록에서
///   깊이 = (최근 구간에서 가장 높았던 지점 ≈ 지면) − (주차 직전 고도)
/// 를 구하고, 층별 예상 깊이와 가장 가까운 층을 고른다.
/// 몇 분 사이의 "변화량"만 쓰기 때문에 날씨에 따른 기압 변동의 영향을 받지 않는다.
enum FloorEstimator {
    struct Result: Equatable {
        var level: Int
        var depth: Double
        var confidence: ParkingRecord.Confidence
    }

    // MARK: 깊이 계산

    /// - Parameters:
    ///   - lookback: 지면 기준점을 찾을 구간(초). 주차 시점에서 이만큼만 거슬러 올라간다.
    ///   - settle: 주차 고도를 구할 마지막 구간(초).
    /// - Returns: 지면 대비 내려간 깊이(m, 0 이상). 표본이 부족하면 nil.
    static func depth(from samples: [AltitudeSample],
                      lookback: TimeInterval = 300,
                      settle: TimeInterval = 4) -> Double? {
        guard samples.count >= 5, let end = samples.last?.t else { return nil }
        let window = samples.filter { $0.t >= end - lookback }
        guard window.count >= 5 else { return nil }

        let smoothed = movingMedian(window.map(\.altitude), radius: 2)
        guard let reference = smoothed.max() else { return nil }

        let tail = window.filter { $0.t >= end - settle }.map(\.altitude)
        let parked = median(tail.isEmpty ? [window[window.count - 1].altitude] : tail)
        return max(0, reference - parked)
    }

    // MARK: 층 분류

    /// 설정값만으로 계산한 층별 기본 깊이
    static func modelDepth(for level: Int, settings: AppSettings) -> Double {
        guard level < 0 else { return 0 }
        return settings.firstBasementDepth + Double(-level - 1) * settings.floorHeight
    }

    /// 층별 예상 깊이. 보정값이 있는 층은 실측 중앙값을,
    /// 없는 층은 가장 가까운 보정 층의 오차만큼 기본 모델을 평행 이동해서 쓴다.
    static func expectedDepths(settings: AppSettings, calibration: Calibration) -> [(level: Int, depth: Double, calibrated: Bool)] {
        let levels = Array(stride(from: 0, through: -max(1, settings.basementCount), by: -1))
        let calibratedBasements = levels.filter { $0 < 0 && calibration.centroid(for: $0) != nil }

        return levels.map { level in
            if let own = calibration.centroid(for: level) {
                return (level, own, true)
            }
            let model = modelDepth(for: level, settings: settings)
            guard level < 0,
                  let nearest = calibratedBasements.min(by: { abs($0 - level) < abs($1 - level) }),
                  let centroid = calibration.centroid(for: nearest) else {
                return (level, model, false)
            }
            let residual = centroid - modelDepth(for: nearest, settings: settings)
            return (level, model + residual, false)
        }
    }

    static func classify(depth: Double, settings: AppSettings, calibration: Calibration) -> Result {
        let ranked = expectedDepths(settings: settings, calibration: calibration)
            .map { (level: $0.level, distance: abs($0.depth - depth), calibrated: $0.calibrated) }
            .sorted { $0.distance < $1.distance }

        let best = ranked[0]
        let margin = ranked.count > 1 ? ranked[1].distance - best.distance : .infinity

        let confidence: ParkingRecord.Confidence
        if best.distance <= 0.8, margin >= 1.0, best.calibrated {
            confidence = .high
        } else if best.distance <= 1.3, margin >= 0.6 {
            confidence = .medium
        } else {
            confidence = .low
        }
        return Result(level: best.level, depth: depth, confidence: confidence)
    }

    // MARK: 통계 유틸

    static func median(_ values: [Double]) -> Double {
        guard !values.isEmpty else { return 0 }
        let sorted = values.sorted()
        let mid = sorted.count / 2
        return sorted.count % 2 == 0 ? (sorted[mid - 1] + sorted[mid]) / 2 : sorted[mid]
    }

    /// 차량 공조·창문 개폐로 생기는 순간적인 기압 튐을 걸러내기 위한 이동 중앙값
    static func movingMedian(_ values: [Double], radius: Int) -> [Double] {
        guard values.count > 1, radius > 0 else { return values }
        return values.indices.map { i in
            let lo = max(0, i - radius)
            let hi = min(values.count - 1, i + radius)
            return median(Array(values[lo...hi]))
        }
    }
}

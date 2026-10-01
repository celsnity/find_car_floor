import XCTest

/// 층 추정 로직 테스트. Models.swift / FloorEstimator.swift 를 테스트 번들에 직접 컴파일하므로
/// 앱을 띄우지 않고 시뮬레이터에서 바로 돈다 (⌘U).
final class FloorEstimatorTests: XCTestCase {
    private let settings = AppSettings()   // B1 4.5m, 층간 3.3m, 지하 3층

    /// 지면을 달리다가 `depth` 만큼 내려가서 주차하는 고도 기록을 만든다 (1Hz).
    private func trace(depth: Double, flat: Int = 40, descent: Int = 30, parked: Int = 20,
                       noise: Double = 0.15, spikeAt: Int? = nil) -> [AltitudeSample] {
        var generator = SystemRandomNumberGenerator()
        var samples: [AltitudeSample] = []
        let total = flat + descent + parked
        for i in 0..<total {
            let ideal: Double
            if i < flat {
                ideal = 0
            } else if i < flat + descent {
                ideal = -depth * Double(i - flat + 1) / Double(descent)
            } else {
                ideal = -depth
            }
            var value = ideal + Double.random(in: -noise...noise, using: &generator)
            if i == spikeAt { value += 3 }   // 창문 개폐 같은 순간 기압 튐
            samples.append(AltitudeSample(t: Double(i), altitude: value))
        }
        return samples
    }

    func testDepthIsMeasuredFromGroundPlateau() throws {
        let depth = try XCTUnwrap(FloorEstimator.depth(from: trace(depth: 7.8)))
        XCTAssertEqual(depth, 7.8, accuracy: 0.5)
    }

    func testSingleSpikeIsIgnored() throws {
        let depth = try XCTUnwrap(FloorEstimator.depth(from: trace(depth: 4.5, spikeAt: 10)))
        XCTAssertEqual(depth, 4.5, accuracy: 0.5)
    }

    func testTooFewSamplesReturnsNil() {
        XCTAssertNil(FloorEstimator.depth(from: [AltitudeSample(t: 0, altitude: 0)]))
    }

    func testDefaultModelClassifiesEachFloor() {
        let calibration = Calibration()
        XCTAssertEqual(FloorEstimator.classify(depth: 0.3, settings: settings, calibration: calibration).level, 0)
        XCTAssertEqual(FloorEstimator.classify(depth: 4.4, settings: settings, calibration: calibration).level, -1)
        XCTAssertEqual(FloorEstimator.classify(depth: 7.9, settings: settings, calibration: calibration).level, -2)
        XCTAssertEqual(FloorEstimator.classify(depth: 11.0, settings: settings, calibration: calibration).level, -3)
    }

    func testDepthBeyondDeepestFloorIsLowConfidence() {
        let result = FloorEstimator.classify(depth: 20, settings: settings, calibration: Calibration())
        XCTAssertEqual(result.level, -3)
        XCTAssertEqual(result.confidence, .low)
    }

    func testCalibrationOverridesModel() {
        // 실제 주차장이 기본값보다 깊은 경우: B1 = 6.0m 로 학습
        var calibration = Calibration()
        calibration.add(depth: 6.1, for: -1)
        calibration.add(depth: 5.9, for: -1)

        // 6.0m 는 기본 모델이면 B1(4.5)과 B2(7.8) 사이에서 애매하지만, 학습 후에는 확실히 B1
        let b1 = FloorEstimator.classify(depth: 6.0, settings: settings, calibration: calibration)
        XCTAssertEqual(b1.level, -1)
        XCTAssertEqual(b1.confidence, .high)

        // 학습하지 않은 B2 도 같은 오차(+1.5m)만큼 이동: 7.8 → 9.3
        let expected = FloorEstimator.expectedDepths(settings: settings, calibration: calibration)
        let b2 = expected.first { $0.level == -2 }
        XCTAssertEqual(b2?.depth ?? 0, 9.3, accuracy: 0.01)
        XCTAssertEqual(FloorEstimator.classify(depth: 9.2, settings: settings, calibration: calibration).level, -2)
    }

    func testCalibrationKeepsOnlyRecentSamples() {
        var calibration = Calibration()
        for i in 0..<20 { calibration.add(depth: Double(i), for: -1) }
        XCTAssertEqual(calibration.samples[-1]?.count, Calibration.maxSamplesPerLevel)
        XCTAssertEqual(calibration.samples[-1]?.last, 19)
    }

    func testCalibrationSurvivesJSONRoundTrip() throws {
        var calibration = Calibration()
        calibration.add(depth: 7.7, for: -2)
        let data = try JSONEncoder().encode(calibration)
        XCTAssertEqual(try JSONDecoder().decode(Calibration.self, from: data), calibration)
    }

    func testEndToEndWithNoise() throws {
        for (depth, level) in [(0.0, 0), (4.5, -1), (7.8, -2), (11.1, -3)] {
            let measured = try XCTUnwrap(FloorEstimator.depth(from: trace(depth: depth)))
            XCTAssertEqual(FloorEstimator.classify(depth: measured, settings: settings, calibration: Calibration()).level, level)
        }
    }
}

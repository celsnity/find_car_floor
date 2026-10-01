import AppIntents

/// 위젯의 ▲▼ 버튼이 실행하는 인텐트. 층이 한 칸 틀렸을 때 앱을 열지 않고 바로 고친다.
struct AdjustFloorIntent: AppIntent {
    static let title: LocalizedStringResource = "주차 층 조정"
    static let isDiscoverable = false

    /// +1 = 한 층 위로, -1 = 한 층 아래로
    @Parameter(title: "변화량")
    var delta: Int

    init() {}

    init(delta: Int) {
        self.delta = delta
    }

    func perform() async throws -> some IntentResult {
        ParkingStore.shared.adjustCurrent(by: delta)
        return .result()
    }
}

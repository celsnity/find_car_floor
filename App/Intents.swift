import AppIntents

/// 단축어 자동화("CarPlay 연결 해제될 때")에 걸어 두는 인텐트.
/// 측정 중이면 그 자리에서 층을 확정하고, 이미 자동으로 기록됐으면 그 결과를 그대로 알려준다.
struct RecordParkingIntent: AppIntent {
    static let title: LocalizedStringResource = "주차 층 기록"
    static let description: IntentDescription? = IntentDescription("지금 주차한 층을 기록해요. 단축어 자동화의 ‘CarPlay 연결 해제될 때’에 연결해 두면 좋아요.")
    static let openAppWhenRun = false

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        if let record = ParkingSessionManager.shared.finishNow(reason: "단축어") {
            return .result(dialog: "\(FloorStyle.parkedSentence(record.level))")
        }
        return .result(dialog: "측정 중이 아니어서 층을 알 수 없었어요. 앱에서 직접 기록해 주세요.")
    }
}

/// "시리야, 주차층에서 내 차 어디 있어"
struct WhereIsMyCarIntent: AppIntent {
    static let title: LocalizedStringResource = "내 차 위치 확인"
    static let description: IntentDescription? = IntentDescription("마지막으로 주차한 층을 알려줘요.")
    static let openAppWhenRun = false

    func perform() async throws -> some IntentResult & ReturnsValue<String> & ProvidesDialog {
        guard let record = ParkingStore.shared.current else {
            return .result(value: "", dialog: "아직 주차 기록이 없어요.")
        }
        var sentence = "내 차는 \(FloorStyle.long(record.level))에 있어요. \(ParkedTime.label(record.date))에 주차했어요."
        if !record.memo.isEmpty {
            sentence += " 메모: \(record.memo)"
        }
        return .result(value: FloorStyle.short(record.level), dialog: "\(sentence)")
    }
}

struct ParkFloorShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: WhereIsMyCarIntent(),
                    phrases: [
                        "\(.applicationName)에서 내 차 어디 있어",
                        "\(.applicationName) 내 차 위치"
                    ],
                    shortTitle: "내 차 위치",
                    systemImageName: "car.fill")
        AppShortcut(intent: RecordParkingIntent(),
                    phrases: [
                        "\(.applicationName)에 주차 기록"
                    ],
                    shortTitle: "주차 층 기록",
                    systemImageName: "parkingsign.circle.fill")
    }
}

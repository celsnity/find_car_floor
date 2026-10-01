import SwiftUI

/// 층 표기와 색. 실제 주차장처럼 층마다 고유색을 줘서 숫자를 읽기 전에 색으로 먼저 알아볼 수 있게 한다.
enum FloorStyle {
    static func short(_ level: Int) -> String {
        level < 0 ? "B\(-level)" : "지상"
    }

    static func long(_ level: Int) -> String {
        level < 0 ? "지하 \(-level)층" : "지상 주차"
    }

    /// 알림·Siri 응답용 문장
    static func parkedSentence(_ level: Int) -> String {
        level < 0 ? "지하 \(-level)층(B\(-level))에 주차했어요" : "지상에 주차했어요"
    }

    private static let ground = 0x5B6B82
    private static let basements = [0x0FA573, 0x2F7BF0, 0xEA6A0C, 0x7C5CF0, 0xE23D5B, 0x0E9AA8, 0xB98207]

    static func color(_ level: Int) -> Color {
        Color(hex: hex(level))
    }

    static func gradient(_ level: Int) -> LinearGradient {
        let base = hex(level)
        return LinearGradient(colors: [Color(hex: base, brightness: 1.08), Color(hex: base, brightness: 0.72)],
                              startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    /// 기록이 없을 때의 중립 배경
    static let emptyGradient = LinearGradient(colors: [Color(hex: 0x3A4658), Color(hex: 0x232B38)],
                                              startPoint: .topLeading, endPoint: .bottomTrailing)

    private static func hex(_ level: Int) -> Int {
        level < 0 ? basements[(-level - 1) % basements.count] : ground
    }
}

extension Color {
    init(hex: Int, brightness: Double = 1) {
        let r = Double((hex >> 16) & 0xFF) / 255 * brightness
        let g = Double((hex >> 8) & 0xFF) / 255 * brightness
        let b = Double(hex & 0xFF) / 255 * brightness
        self.init(.sRGB, red: min(r, 1), green: min(g, 1), blue: min(b, 1), opacity: 1)
    }
}

enum ParkedTime {
    /// "오늘 오후 6:42" / "어제 오후 6:42" / "9월 29일 오후 6:42"
    static func label(_ date: Date, now: Date = Date(), calendar: Calendar = .current) -> String {
        let time = date.formatted(date: .omitted, time: .shortened)
        if calendar.isDate(date, inSameDayAs: now) { return "오늘 \(time)" }
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: now),
           calendar.isDate(date, inSameDayAs: yesterday) { return "어제 \(time)" }
        return "\(date.formatted(.dateTime.month().day())) \(time)"
    }
}

/// 건물 단면처럼 층을 쌓아 보여주는 인디케이터. 앱과 위젯이 함께 쓴다.
struct FloorStackView: View {
    let basementCount: Int
    let current: Int?
    var showLabels = true

    private var levels: [Int] {
        let deepest = max(max(1, basementCount), -(current ?? 0))
        return Array(stride(from: 0, through: -deepest, by: -1))
    }

    var body: some View {
        VStack(spacing: 4) {
            ForEach(levels, id: \.self) { level in
                let isCurrent = level == current
                HStack(spacing: 6) {
                    if showLabels {
                        Text(FloorStyle.short(level))
                            .font(.system(size: 10, weight: isCurrent ? .heavy : .semibold, design: .rounded))
                            .opacity(isCurrent ? 1 : 0.6)
                            .frame(width: 24, alignment: .trailing)
                    }
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .fill(.white.opacity(isCurrent ? 1 : 0.2))
                        .overlay {
                            if isCurrent {
                                Image(systemName: "car.side.fill")
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundStyle(FloorStyle.color(level))
                            }
                        }
                }
                .frame(maxHeight: 20)
            }
        }
        .foregroundStyle(.white)
        .accessibilityHidden(true)
    }
}

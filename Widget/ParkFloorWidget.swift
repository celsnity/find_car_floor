import AppIntents
import SwiftUI
import WidgetKit

// MARK: - 타임라인

struct ParkingEntry: TimelineEntry {
    let date: Date
    let record: ParkingRecord?
    let basementCount: Int

    static var sample: ParkingEntry {
        ParkingEntry(date: Date(),
                     record: ParkingRecord(date: Date().addingTimeInterval(-12 * 60), level: -2, depth: 7.8,
                                           confidence: .high, source: .auto),
                     basementCount: 3)
    }

    static var current: ParkingEntry {
        let store = ParkingStore.shared
        return ParkingEntry(date: Date(), record: store.current, basementCount: store.settings.basementCount)
    }
}

struct ParkingProvider: TimelineProvider {
    func placeholder(in context: Context) -> ParkingEntry {
        .sample
    }

    func getSnapshot(in context: Context, completion: @escaping (ParkingEntry) -> Void) {
        completion(context.isPreview ? .sample : .current)
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<ParkingEntry>) -> Void) {
        // 내용은 앱이 기록을 바꿀 때만 달라진다(그때 앱이 직접 갱신을 요청한다).
        // "오늘/어제" 표기를 맞추려고 자정에 한 번만 스스로 갱신한다.
        let calendar = Calendar.current
        let startOfToday = calendar.startOfDay(for: Date())
        let nextMidnight = calendar.date(byAdding: .day, value: 1, to: startOfToday) ?? Date().addingTimeInterval(86_400)
        completion(Timeline(entries: [.current], policy: .after(nextMidnight)))
    }
}

// MARK: - 위젯

@main
struct ParkFloorWidgetBundle: WidgetBundle {
    var body: some Widget {
        ParkFloorWidget()
    }
}

struct ParkFloorWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: ParkingStore.widgetKind, provider: ParkingProvider()) { entry in
            ParkFloorWidgetView(entry: entry)
        }
        .configurationDisplayName("주차 층")
        .description("내 차가 몇 층에 있는지 바로 확인해요.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryCircular, .accessoryRectangular, .accessoryInline])
    }
}

struct ParkFloorWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: ParkingEntry

    var body: some View {
        content
            .containerBackground(for: .widget) {
                switch family {
                case .systemSmall, .systemMedium:
                    entry.record.map { FloorStyle.gradient($0.level) } ?? FloorStyle.emptyGradient
                default:
                    Color.clear
                }
            }
    }

    @ViewBuilder
    private var content: some View {
        switch family {
        case .systemMedium:
            MediumWidgetView(entry: entry)
        case .accessoryCircular:
            CircularWidgetView(entry: entry)
        case .accessoryRectangular:
            RectangularWidgetView(entry: entry)
        case .accessoryInline:
            InlineWidgetView(entry: entry)
        default:
            SmallWidgetView(entry: entry)
        }
    }
}

// MARK: - 홈 화면

private struct SmallWidgetView: View {
    let entry: ParkingEntry

    var body: some View {
        if let record = entry.record {
            VStack(alignment: .leading, spacing: 0) {
                WidgetHeader(record: record)
                Spacer(minLength: 0)
                Text(FloorStyle.short(record.level))
                    .font(.system(size: 62, weight: .heavy, design: .rounded))
                    .minimumScaleFactor(0.5)
                    .lineLimit(1)
                    .widgetAccentable()
                Spacer(minLength: 0)
                Text(ParkedTime.label(record.date, now: entry.date))
                    .font(.caption.weight(.medium))
                    .opacity(0.85)
                    .lineLimit(1)
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        } else {
            EmptyWidgetView()
        }
    }
}

private struct MediumWidgetView: View {
    let entry: ParkingEntry

    var body: some View {
        if let record = entry.record {
            HStack(spacing: 14) {
                VStack(alignment: .leading, spacing: 0) {
                    WidgetHeader(record: record)
                    Spacer(minLength: 0)
                    Text(FloorStyle.short(record.level))
                        .font(.system(size: 62, weight: .heavy, design: .rounded))
                        .minimumScaleFactor(0.5)
                        .lineLimit(1)
                        .widgetAccentable()
                    Spacer(minLength: 0)
                    Text("\(FloorStyle.long(record.level)) · \(ParkedTime.label(record.date, now: entry.date))")
                        .font(.caption.weight(.medium))
                        .opacity(0.85)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                FloorStackView(basementCount: entry.basementCount, current: record.level)
                    .frame(width: 92)

                VStack(spacing: 10) {
                    AdjustButton(systemImage: "chevron.up", delta: 1, enabled: record.level < 0)
                    AdjustButton(systemImage: "chevron.down", delta: -1, enabled: record.level > -entry.basementCount)
                }
            }
            .foregroundStyle(.white)
        } else {
            EmptyWidgetView()
        }
    }
}

private struct WidgetHeader: View {
    let record: ParkingRecord

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: "car.fill")
            Text(record.memo.isEmpty ? "내 차" : record.memo)
                .lineLimit(1)
        }
        .font(.caption.weight(.semibold))
        .opacity(0.92)
    }
}

/// 층이 한 칸 틀렸을 때 위젯에서 바로 고치는 버튼 (앱을 열지 않는다)
private struct AdjustButton: View {
    let systemImage: String
    let delta: Int
    let enabled: Bool

    var body: some View {
        Button(intent: AdjustFloorIntent(delta: delta)) {
            Image(systemName: systemImage)
                .font(.system(size: 13, weight: .bold))
                .frame(width: 34, height: 34)
                .background(.white.opacity(0.2), in: Circle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.35)
        .accessibilityLabel(delta > 0 ? "한 층 위로" : "한 층 아래로")
    }
}

private struct EmptyWidgetView: View {
    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: "parkingsign.circle.fill")
                .font(.system(size: 30))
                .symbolRenderingMode(.hierarchical)
            Text("주차 기록 없음")
                .font(.caption.weight(.semibold))
        }
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - 잠금 화면

private struct CircularWidgetView: View {
    let entry: ParkingEntry

    var body: some View {
        ZStack {
            AccessoryWidgetBackground()
            VStack(spacing: -1) {
                Image(systemName: "car.fill")
                    .font(.system(size: 10, weight: .semibold))
                Text(entry.record.map { FloorStyle.short($0.level) } ?? "–")
                    .font(.system(size: 20, weight: .heavy, design: .rounded))
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)
                    .widgetAccentable()
            }
            .padding(6)
        }
    }
}

private struct RectangularWidgetView: View {
    let entry: ParkingEntry

    var body: some View {
        HStack(spacing: 8) {
            if let record = entry.record {
                Text(FloorStyle.short(record.level))
                    .font(.system(size: 30, weight: .heavy, design: .rounded))
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)
                    .widgetAccentable()
                VStack(alignment: .leading, spacing: 1) {
                    Label(record.memo.isEmpty ? "내 차" : record.memo, systemImage: "car.fill")
                        .font(.caption.weight(.semibold))
                    Text(ParkedTime.label(record.date, now: entry.date))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .lineLimit(1)
            } else {
                Label("주차 기록 없음", systemImage: "car.fill")
                    .font(.caption.weight(.semibold))
            }
            Spacer(minLength: 0)
        }
    }
}

private struct InlineWidgetView: View {
    let entry: ParkingEntry

    var body: some View {
        if let record = entry.record {
            Label("내 차 \(FloorStyle.short(record.level)) · \(ParkedTime.label(record.date, now: entry.date))",
                  systemImage: "car.fill")
        } else {
            Label("주차 기록 없음", systemImage: "car.fill")
        }
    }
}

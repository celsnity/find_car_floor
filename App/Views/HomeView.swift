import SwiftUI

struct HomeView: View {
    @Environment(AppModel.self) private var model
    @State private var showFloorPicker = false
    @State private var showSettings = false
    @State private var showMemoEditor = false
    @State private var memoDraft = ""

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    if model.isTracking {
                        TrackingBanner()
                    }

                    if let record = model.current {
                        HeroCard(record: record, basementCount: model.settings.basementCount)
                            .contextMenu {
                                Button(role: .destructive) {
                                    model.clearCurrent()
                                } label: {
                                    Label("이 기록 지우기", systemImage: "trash")
                                }
                            }

                        if record.source == .auto, !record.corrected, record.confidence != .high {
                            ConfirmCard(record: record) {
                                model.confirmCurrent()
                            } onChange: {
                                showFloorPicker = true
                            }
                        }

                        actionRow(for: record)
                    } else {
                        EmptyHero {
                            showFloorPicker = true
                        }
                    }

                    if !model.isReady {
                        SetupCard {
                            showSettings = true
                        }
                    }

                    if model.history.count > 1 {
                        historySection
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 28)
                .animation(.snappy, value: model.current)
                .animation(.snappy, value: model.isTracking)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("주차층")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showSettings = true
                    } label: {
                        Image(systemName: "gearshape")
                    }
                    .accessibilityLabel("설정")
                }
            }
            .sheet(isPresented: $showFloorPicker) {
                FloorPickerSheet(basementCount: model.settings.basementCount,
                                 selected: model.current?.level) { level in
                    model.chooseFloor(level)
                }
                .presentationDetents([.medium, .large])
            }
            .sheet(isPresented: $showSettings) {
                SettingsView()
            }
            .alert("메모", isPresented: $showMemoEditor) {
                TextField("예: A구역 23번 기둥", text: $memoDraft)
                Button("저장") { model.setMemo(memoDraft) }
                Button("취소", role: .cancel) {}
            } message: {
                Text("구역이나 기둥 번호를 적어 두면 위젯에도 함께 보여요.")
            }
            .sensoryFeedback(.success, trigger: model.current?.level)
        }
    }

    private func actionRow(for record: ParkingRecord) -> some View {
        HStack(spacing: 12) {
            ActionButton(title: "층 수정", systemImage: "arrow.up.arrow.down") {
                showFloorPicker = true
            }
            ActionButton(title: record.memo.isEmpty ? "메모 추가" : "메모 수정", systemImage: "square.and.pencil") {
                memoDraft = record.memo
                showMemoEditor = true
            }
        }
    }

    private var historySection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("최근 기록")
                .font(.headline)
                .padding(.horizontal, 4)
                .padding(.top, 8)

            VStack(spacing: 0) {
                let items = Array(model.history.dropFirst().prefix(10))
                ForEach(items) { record in
                    HistoryRow(record: record)
                    if record.id != items.last?.id {
                        Divider().padding(.leading, 64)
                    }
                }
            }
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        }
    }
}

// MARK: - 히어로 카드

private struct HeroCard: View {
    let record: ParkingRecord
    let basementCount: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label("내 차 위치", systemImage: "car.fill")
                    .font(.subheadline.weight(.semibold))
                    .opacity(0.92)
                Spacer()
                Text(chipText)
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(.white.opacity(0.2), in: Capsule())
            }

            HStack(alignment: .bottom, spacing: 16) {
                VStack(alignment: .leading, spacing: 0) {
                    Text(FloorStyle.short(record.level))
                        .font(.system(size: 104, weight: .heavy, design: .rounded))
                        .minimumScaleFactor(0.5)
                        .lineLimit(1)
                        .contentTransition(.numericText())
                    Text(FloorStyle.long(record.level))
                        .font(.title3.weight(.semibold))
                        .opacity(0.92)
                }
                Spacer(minLength: 0)
                FloorStackView(basementCount: basementCount, current: record.level)
                    .frame(width: 112, height: CGFloat(max(basementCount, -record.level) + 1) * 24)
                    .padding(.bottom, 6)
            }

            Rectangle()
                .fill(.white.opacity(0.22))
                .frame(height: 1)

            HStack(spacing: 6) {
                Image(systemName: "clock")
                Text(ParkedTime.label(record.date))
                TimelineView(.everyMinute) { context in
                    Text("· \(record.date.formatted(.relative(presentation: .named)))")
                        .opacity(0.8)
                        .id(context.date)
                }
                Spacer(minLength: 0)
                if let depth = record.depth {
                    Text("지면 −\(depth, specifier: "%.1f")m")
                        .opacity(0.8)
                }
            }
            .font(.footnote.weight(.medium))
            .lineLimit(1)

            if !record.memo.isEmpty {
                Label(record.memo, systemImage: "mappin.and.ellipse")
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(2)
            }
        }
        .foregroundStyle(.white)
        .padding(22)
        .background(FloorStyle.gradient(record.level), in: RoundedRectangle(cornerRadius: 30, style: .continuous))
        .shadow(color: FloorStyle.color(record.level).opacity(0.35), radius: 18, y: 10)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("내 차는 \(FloorStyle.long(record.level)), \(ParkedTime.label(record.date)) 주차")
    }

    private var chipText: String {
        if record.source == .manual { return "직접 기록" }
        if record.corrected { return "수정됨" }
        switch record.confidence {
        case .high: return "자동 · 정확도 높음"
        case .medium: return "자동 · 정확도 보통"
        case .low: return "자동 · 확인 필요"
        }
    }
}

private struct EmptyHero: View {
    let onRecord: () -> Void

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "parkingsign.circle.fill")
                .font(.system(size: 56))
                .symbolRenderingMode(.hierarchical)
            Text("아직 주차 기록이 없어요")
                .font(.title3.weight(.bold))
            Text("집 주차장에 주차하고 CarPlay 연결이 끊기면\n몇 층인지 자동으로 기록돼요.")
                .font(.subheadline)
                .multilineTextAlignment(.center)
                .opacity(0.8)
            Button("직접 기록하기", action: onRecord)
                .font(.subheadline.weight(.semibold))
                .padding(.horizontal, 18)
                .padding(.vertical, 10)
                .background(.white.opacity(0.18), in: Capsule())
                .padding(.top, 4)
        }
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 36)
        .padding(.horizontal, 20)
        .background(FloorStyle.emptyGradient, in: RoundedRectangle(cornerRadius: 30, style: .continuous))
    }
}

// MARK: - 보조 카드

/// 자동 추정이 확실하지 않을 때 한 번 탭으로 확인받는다. 확인·수정 모두 다음 추정의 보정값이 된다.
private struct ConfirmCard: View {
    let record: ParkingRecord
    let onConfirm: () -> Void
    let onChange: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("주차한 층이 \(FloorStyle.short(record.level)) 맞나요?")
                    .font(.subheadline.weight(.semibold))
                Text("알려 주시면 다음부터 더 정확해져요.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            Button("다른 층", action: onChange)
                .buttonStyle(.bordered)
            Button("맞아요", action: onConfirm)
                .buttonStyle(.borderedProminent)
                .tint(FloorStyle.color(record.level))
        }
        .font(.subheadline.weight(.semibold))
        .padding(16)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }
}

private struct TrackingBanner: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                ProgressView()
                VStack(alignment: .leading, spacing: 2) {
                    Text("층 측정 중")
                        .font(.subheadline.weight(.semibold))
                    TimelineView(.periodic(from: .now, by: 1)) { _ in
                        Text(depthText)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                }
                Spacer(minLength: 0)
            }
            HStack(spacing: 10) {
                Button("여기 주차했어요") { model.finishSession() }
                    .buttonStyle(.borderedProminent)
                Button("취소", role: .cancel) { model.cancelSession() }
                    .buttonStyle(.bordered)
            }
            .font(.subheadline.weight(.semibold))
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private var depthText: String {
        if let depth = model.liveDepth {
            return "지면에서 \(String(format: "%.1f", depth))m 내려왔어요 · CarPlay가 끊기면 자동 기록"
        }
        return "CarPlay 연결이 끊기면 자동으로 기록돼요"
    }
}

private struct ActionButton: View {
    let title: String
    let systemImage: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.subheadline.weight(.semibold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

private struct HistoryRow: View {
    let record: ParkingRecord

    var body: some View {
        HStack(spacing: 12) {
            Text(FloorStyle.short(record.level))
                .font(.system(size: 15, weight: .heavy, design: .rounded))
                .foregroundStyle(.white)
                .frame(width: 40, height: 40)
                .background(FloorStyle.gradient(record.level), in: RoundedRectangle(cornerRadius: 12, style: .continuous))

            VStack(alignment: .leading, spacing: 2) {
                Text(FloorStyle.long(record.level))
                    .font(.subheadline.weight(.semibold))
                Text(record.memo.isEmpty ? ParkedTime.label(record.date) : "\(ParkedTime.label(record.date)) · \(record.memo)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            if record.source == .manual || record.corrected {
                Image(systemName: record.source == .manual ? "hand.tap" : "pencil")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }
}

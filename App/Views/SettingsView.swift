import CoreLocation
import MapKit
import SwiftUI

struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    @State private var camera: MapCameraPosition = .automatic
    @State private var isLocating = false
    @State private var locateFailed = false
    @State private var confirmReset = false

    private var home: CLLocationCoordinate2D? {
        guard let latitude = model.settings.homeLatitude, let longitude = model.settings.homeLongitude else { return nil }
        return CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    var body: some View {
        NavigationStack {
            Form {
                homeSection
                detectionSection
                structureSection
                shortcutSection
                diagnosticsSection
            }
            .navigationTitle("설정")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("완료") { dismiss() }
                }
            }
            .onAppear {
                camera = home == nil ? .userLocation(fallback: .automatic) : .automatic
            }
            .alert("현재 위치를 가져오지 못했어요", isPresented: $locateFailed) {
                Button("확인", role: .cancel) {}
            } message: {
                Text("위치 권한을 확인하거나, 지도에서 집 주차장 위치를 직접 탭해 주세요.")
            }
        }
    }

    // MARK: 집 위치

    private var homeSection: some View {
        Section {
            MapReader { proxy in
                Map(position: $camera) {
                    if let home {
                        Marker("우리 집", systemImage: "house.fill", coordinate: home)
                        MapCircle(center: home, radius: model.settings.regionRadius)
                            .foregroundStyle(Color.blue.opacity(0.12))
                            .stroke(Color.blue.opacity(0.5), lineWidth: 1)
                    }
                    UserAnnotation()
                }
                .onTapGesture { point in
                    if let coordinate = proxy.convert(point, from: .local) {
                        model.setHome(coordinate)
                    }
                }
            }
            .frame(height: 220)
            .listRowInsets(EdgeInsets())

            Button {
                isLocating = true
                model.setHomeToCurrentLocation { success in
                    isLocating = false
                    locateFailed = !success
                    if success { camera = .automatic }
                }
            } label: {
                HStack {
                    Label("현재 위치를 집으로 설정", systemImage: "location.fill")
                    Spacer()
                    if isLocating { ProgressView() }
                }
            }
            .disabled(isLocating)

            Picker("감지 반경", selection: binding(\.regionRadius)) {
                ForEach([300.0, 400.0, 600.0, 800.0], id: \.self) { radius in
                    Text("\(Int(radius))m").tag(radius)
                }
            }
        } header: {
            Text("집 주차장 위치")
        } footer: {
            Text("지도를 탭하면 위치를 옮길 수 있어요. 원 안으로 들어오면 측정을 시작하니, 지하로 내려가기 전에 시작되도록 반경을 넉넉하게 두세요.")
        }
    }

    // MARK: 자동 감지

    private var detectionSection: some View {
        Section {
            Toggle("CarPlay 해제 시 자동 기록", isOn: binding(\.autoDetect))
            Toggle("주차 알림", isOn: binding(\.notifyOnPark))
        } footer: {
            Text("평소에는 아무것도 실행하지 않아요. 집 근처에 CarPlay가 연결된 채로 들어왔을 때만 주차할 때까지 몇 분간 기압계를 기록합니다.")
        }
    }

    // MARK: 주차장 구조

    private var structureSection: some View {
        Section {
            Stepper(value: binding(\.basementCount), in: 1...7) {
                LabeledContent("지하 층수", value: "B\(model.settings.basementCount)까지")
            }
            Stepper(value: binding(\.firstBasementDepth), in: 2.5...9, step: 0.1) {
                LabeledContent("지면 → B1 깊이", value: String(format: "%.1fm", model.settings.firstBasementDepth))
            }
            Stepper(value: binding(\.floorHeight), in: 2.2...6, step: 0.1) {
                LabeledContent("층간 높이", value: String(format: "%.1fm", model.settings.floorHeight))
            }

            ForEach(learnedLevels, id: \.level) { item in
                LabeledContent("\(FloorStyle.short(item.level)) 학습값",
                               value: String(format: "%.1fm · %ld회", item.depth, item.count))
                    .foregroundStyle(.secondary)
            }

            if !model.calibration.isEmpty {
                Button("학습값 초기화", role: .destructive) { confirmReset = true }
                    .confirmationDialog("층별 학습값을 모두 지울까요?", isPresented: $confirmReset, titleVisibility: .visible) {
                        Button("초기화", role: .destructive) { model.resetCalibration() }
                    }
            }
        } header: {
            Text("주차장 구조")
        } footer: {
            Text("깊이 값은 대략이면 충분해요. 층을 확인하거나 고쳐 줄 때마다 그 층의 실제 깊이를 학습해서 이 값보다 우선 적용합니다.")
        }
    }

    private var learnedLevels: [(level: Int, depth: Double, count: Int)] {
        model.calibration.samples.keys.sorted(by: >).compactMap { level in
            guard let depth = model.calibration.centroid(for: level),
                  let count = model.calibration.samples[level]?.count else { return nil }
            return (level: level, depth: depth, count: count)
        }
    }

    // MARK: 단축어

    private var shortcutSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 6) {
                Text("단축어 앱 → 자동화 → ‘CarPlay’ → ‘연결 해제될 때’ → ‘즉시 실행’")
                Text("동작으로 ‘주차 층 기록’을 추가하세요.")
            }
            .font(.footnote)
        } header: {
            Text("더 확실하게 (선택)")
        } footer: {
            Text("앱이 스스로 CarPlay 해제를 놓쳤을 때를 대비한 이중 안전장치예요. 둘 다 동작해도 기록은 한 번만 남습니다.")
        }
    }

    // MARK: 진단

    private var diagnosticsSection: some View {
        Section {
            TimelineView(.periodic(from: .now, by: 2)) { _ in
                LabeledContent("CarPlay", value: CarPlayMonitor.isConnected ? "연결됨" : "연결 안 됨")
            }
            LabeledContent("기압계", value: model.isBarometerAvailable ? "사용 가능" : "없음")
            LabeledContent("위치 권한", value: locationStatusText)

            if model.isTracking {
                Button("측정 끝내고 여기로 기록") { model.finishSession() }
                Button("측정 취소", role: .destructive) { model.cancelSession() }
            } else {
                Button("지금부터 측정 시작 (테스트)") { model.startManualSession() }
            }

            NavigationLink("동작 기록") {
                LogView(lines: model.log)
            }
        } header: {
            Text("진단")
        } footer: {
            Text("테스트: 지상에서 측정을 시작한 뒤 주차하고 ‘여기로 기록’을 누르면 자동 감지와 같은 방식으로 층을 계산해요.")
        }
    }

    private var locationStatusText: String {
        switch model.locationStatus {
        case .authorizedAlways: return "항상 허용"
        case .authorizedWhenInUse: return "앱 사용 중에만"
        case .denied, .restricted: return "거부됨"
        case .notDetermined: return "아직 요청 안 함"
        @unknown default: return "알 수 없음"
        }
    }

    private func binding<Value>(_ keyPath: WritableKeyPath<AppSettings, Value>) -> Binding<Value> {
        Binding {
            model.settings[keyPath: keyPath]
        } set: { newValue in
            model.updateSettings { $0[keyPath: keyPath] = newValue }
        }
    }
}

private struct LogView: View {
    let lines: [String]

    var body: some View {
        List {
            if lines.isEmpty {
                Text("아직 기록이 없어요.")
                    .foregroundStyle(.secondary)
            }
            ForEach(Array(lines.reversed().enumerated()), id: \.offset) { _, line in
                Text(line)
                    .font(.caption.monospaced())
                    .textSelection(.enabled)
            }
        }
        .navigationTitle("동작 기록")
        .navigationBarTitleDisplayMode(.inline)
    }
}

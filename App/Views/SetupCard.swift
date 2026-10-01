import CoreLocation
import SwiftUI
import UIKit

/// 자동 감지에 필요한 준비물 체크리스트. 모두 끝나면 홈 화면에서 사라진다.
struct SetupCard: View {
    @Environment(AppModel.self) private var model
    let onOpenSettings: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("자동 기록 준비")
                .font(.headline)

            SetupRow(title: "집 주차장 위치",
                     detail: "집 근처에 오면 측정을 시작해요",
                     done: model.settings.hasHome,
                     buttonTitle: "설정",
                     action: onOpenSettings)

            SetupRow(title: "위치 ‘항상 허용’",
                     detail: "앱을 열지 않아도 집 근처에서 깨어나요",
                     done: model.hasAlwaysLocation,
                     buttonTitle: model.locationStatus == .notDetermined ? "허용" : "설정 열기") {
                if model.locationStatus == .notDetermined {
                    model.requestLocationPermission()
                } else {
                    openSystemSettings()
                }
            }

            SetupRow(title: "동작 및 피트니스",
                     detail: model.isBarometerAvailable ? "기압계로 층을 알아내요" : "이 기기는 기압계가 없어요",
                     done: model.hasMotion,
                     buttonTitle: model.motionStatus == .notDetermined ? "허용" : "설정 열기") {
                if model.motionStatus == .notDetermined {
                    model.requestMotionPermission()
                } else {
                    openSystemSettings()
                }
            }

            if !model.notificationsAllowed {
                SetupRow(title: "알림 (선택)",
                         detail: "주차하면 몇 층인지 바로 알려줘요",
                         done: false,
                         buttonTitle: "허용") {
                    model.requestNotificationPermission()
                }
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private func openSystemSettings() {
        if let url = URL(string: UIApplication.openSettingsURLString) {
            UIApplication.shared.open(url)
        }
    }
}

private struct SetupRow: View {
    let title: String
    let detail: String
    let done: Bool
    let buttonTitle: String
    let action: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: done ? "checkmark.circle.fill" : "circle")
                .font(.title3)
                .foregroundStyle(done ? Color.green : Color.secondary)
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            if !done {
                Button(buttonTitle, action: action)
                    .font(.subheadline.weight(.semibold))
                    .buttonStyle(.bordered)
                    .buttonBorderShape(.capsule)
            }
        }
    }
}

import SwiftUI
import UserNotifications

@main
struct ParkFloorApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @Environment(\.scenePhase) private var scenePhase
    @State private var model = AppModel()

    var body: some Scene {
        WindowGroup {
            HomeView()
                .environment(model)
        }
        .onChange(of: scenePhase) { _, phase in
            // 위젯 버튼이나 백그라운드 측정으로 바뀐 내용을 화면에 반영
            if phase == .active { model.reload() }
        }
    }
}

final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        // 지오펜스 이벤트로 백그라운드에서 실행된 경우에도 여기서 바로 위치 관리자를 붙여야 이벤트를 받는다.
        ParkingSessionManager.shared.activate()
        UNUserNotificationCenter.current().delegate = self
        return true
    }

    /// 앱을 보고 있는 중에도 주차 알림을 배너로 보여준다.
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .list])
    }
}

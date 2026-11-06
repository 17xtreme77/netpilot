import Foundation
import UIKit

/// 热点开关控制。
///
/// 三条路径，从优到劣依次尝试：
///
/// **A. root helper**（推荐）
///    App 以 `posix_spawn` 拉起包里自带的 `netpilot-helper`，由它 fork 后以 root 身份
///    对 `sharingd` 发信号重读配置 / 调私有框架。这是 TrollStore 环境下最接近原生的方式。
///    JAILBREAK: 依赖 `com.apple.private.persona-mgmt` entitlement 才能以 uid 0 执行。
///
/// **B. 直接写动态存储**
///    见 `HotspotMonitor.writeAndVerify`，多数版本无效，但成本低，先试。
///
/// **C. 跳转系统设置页**
///    永远可用的兜底，用 `prefs:root=INTERNET_TETHERING` 直接落到热点页。
enum HotspotController {

    enum ToggleOutcome {
        case success
        case failed(String)
        case needsManual(String)   // 需要用户手动操作，附带原因
    }

    /// 开关热点。
    @MainActor
    static func setEnabled(_ enabled: Bool) -> ToggleOutcome {
        // —— 路径 B：先试最便宜的动态存储直写
        if HotspotMonitor.shared.writeAndVerify(enabled) {
            return .success
        }

        // —— 路径 A：root helper
        if let helper = helperPath() {
            let action = enabled ? "hotspot-on" : "hotspot-off"
            let result = Shell.run(helper, [action])
            if result.isSuccess {
                Thread.sleep(forTimeInterval: 0.8)
                if HotspotMonitor.shared.read().isEnabled == enabled {
                    return .success
                }
            }
            // helper 存在但没生效，把它的输出带回去方便排查
            if !result.output.isEmpty {
                return .needsManual(result.output.trimmingCharacters(in: .whitespacesAndNewlines))
            }
        }

        // —— 路径 C：兜底跳转
        return .needsManual("当前系统不允许 App 直接开关热点")
    }

    /// 打开系统的个人热点设置页。
    @MainActor
    static func openSystemHotspotSettings() {
        let candidates = [
            "App-Prefs:root=INTERNET_TETHERING",
            "prefs:root=INTERNET_TETHERING",
            "App-Prefs:root=MOBILE_DATA_SETTINGS_ID&path=INTERNET_TETHERING"
        ]
        for string in candidates {
            guard let url = URL(string: string) else { continue }
            if UIApplication.shared.canOpenURL(url) {
                UIApplication.shared.open(url)
                return
            }
        }
        // 都打不开就退到本 App 的设置页
        if let url = URL(string: UIApplication.openSettingsURLString) {
            UIApplication.shared.open(url)
        }
    }

    /// 找包内的 root helper。
    private static func helperPath() -> String? {
        guard let bundle = Bundle.main.builtInPlugInsURL?
                .deletingLastPathComponent()
                .appendingPathComponent("netpilot-helper"),
              FileManager.default.isExecutableFile(atPath: bundle.path) else {
            return nil
        }
        return bundle.path
    }
}

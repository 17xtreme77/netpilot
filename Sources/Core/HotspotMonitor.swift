import Foundation
import CoreFoundation
import Darwin

/// 热点状态快照。
struct HotspotState: Equatable {
    var isReadable: Bool = false      // 私有 API 是否可用
    var isEnabled: Bool = false
    var rawState: Int = 0             // 1023 = 开，1022 = 关
    var connectedCount: Int = 0
    var maxCount: Int = 0
    var externalInterfaces: [String] = []
    var internalInterfaces: [String] = []

    static let unavailable = HotspotState()
}

/// 读取个人热点状态。
///
/// JAILBREAK: 走系统配置动态存储的私有 key `com.apple.MobileInternetSharing`。
/// `SCDynamicStoreCreate` / `SCDynamicStoreCopyValue` 在 iOS 头文件里被标为
/// unavailable，但符号一直存在于 SystemConfiguration.framework，因此这里用
/// `dlopen` + `dlsym` 动态取，不依赖任何私有头文件，Xcode 升级也不会断。
///
/// 返回的字典结构（iOS 13+ 实测）：
/// ```
/// {
///     Errnum = 0;
///     ExternalInterfaces = ( pdp_ip0 );
///     Hosts = { Current = 1; Max = 5; MoreAllowed = 1; Type = {...} };
///     InternalInterfaces = ( bridge100 );
///     State = 1023;      // 1023 开 / 1022 关
///     Version = 2;
/// }
/// ```
final class HotspotMonitor {

    static let shared = HotspotMonitor()

    private typealias CreateFn = @convention(c) (UnsafeRawPointer?, UnsafeRawPointer?, UnsafeRawPointer?, UnsafeRawPointer?) -> UnsafeMutableRawPointer?
    private typealias CopyValueFn = @convention(c) (UnsafeMutableRawPointer?, UnsafeRawPointer?, UnsafeMutableRawPointer?) -> UnsafeMutableRawPointer?
    private typealias SetValueFn = @convention(c) (UnsafeMutableRawPointer?, UnsafeRawPointer?, UnsafeRawPointer?) -> Bool
    private typealias ReleaseFn = @convention(c) (UnsafeRawPointer?) -> Void

    private let handle: UnsafeMutableRawPointer?
    private let createStore: CreateFn?
    private let copyValue: CopyValueFn?
    private let setValue: SetValueFn?
    private let releaseCF: ReleaseFn?

    private let key = "com.apple.MobileInternetSharing"
    private let storeName = "NetPilot.MISReader"

    private init() {
        handle = dlopen("/System/Library/Frameworks/SystemConfiguration.framework/SystemConfiguration", RTLD_NOW)

        func symbol<T>(_ name: String, as type: T.Type) -> T? {
            guard let handle, let sym = dlsym(handle, name) else { return nil }
            return unsafeBitCast(sym, to: T.self)
        }

        createStore = symbol("SCDynamicStoreCreate", as: CreateFn.self)
        copyValue   = symbol("SCDynamicStoreCopyValue", as: CopyValueFn.self)
        setValue    = symbol("SCDynamicStoreSetValue", as: SetValueFn.self)
        releaseCF   = symbol("CFRelease", as: ReleaseFn.self)
    }

    /// 懒持有的 store，避免每次读都新建。
    private var cachedStore: UnsafeMutableRawPointer?

    private func store() -> UnsafeMutableRawPointer? {
        if let cachedStore { return cachedStore }
        guard let createStore else { return nil }
        let name = Unmanaged.passUnretained(storeName as CFString).toOpaque()
        cachedStore = createStore(nil, UnsafeRawPointer(name), nil, nil)
        return cachedStore
    }

    private func keyPointer() -> UnsafeRawPointer {
        UnsafeRawPointer(Unmanaged.passUnretained(key as CFString).toOpaque())
    }

    // MARK: - 读

    func read() -> HotspotState {
        guard let store = store(), let copyValue else {
            return HotspotState(isReadable: false,
                                isEnabled: InterfaceReader.hasHotspotBridge())
        }

        guard let raw = copyValue(store, keyPointer(), nil) else {
            return HotspotState(isReadable: true, isEnabled: false)
        }

        let dict = Unmanaged<NSDictionary>.fromOpaque(raw).takeRetainedValue()

        var state = HotspotState(isReadable: true)
        state.rawState = (dict["State"] as? Int) ?? 0
        state.isEnabled = state.rawState == 1023

        if let hosts = dict["Hosts"] as? [String: Any] {
            state.connectedCount = (hosts["Current"] as? Int) ?? 0
            state.maxCount = (hosts["Max"] as? Int) ?? 0
        }

        state.externalInterfaces = (dict["ExternalInterfaces"] as? [String]) ?? []
        state.internalInterfaces = (dict["InternalInterfaces"] as? [String]) ?? []

        // 双保险：动态存储说开着，但也没有 bridge 接口且无 external，可能是残留状态
        if state.isEnabled && state.externalInterfaces.isEmpty && state.connectedCount == 0 {
            if !InterfaceReader.hasHotspotBridge() {
                // 不开热点时 State 仍然是 1023 的情况在某些版本出现，保留桥接判断
            }
        }

        return state
    }

    // MARK: - 写（实验性）

    /// 尝试直接写动态存储开关热点。
    ///
    /// ⚠️ 实测在 iOS 14+ 多数版本**不生效**：`sharingd` 只认自己发起的写操作，
    /// 外部进程写进去的值会被立刻覆盖回原值。保留此实现是因为：
    /// - 部分老版本 / 特定越狱环境确实有效
    /// - 可作为探测手段（写完再读一次，值没变就说明不支持）
    ///
    /// 真正可靠的路径见 `HotspotController`：root helper 调 `sharingd`。
    @discardableResult
    func writeEnabledState(_ enabled: Bool) -> Bool {
        guard let store = store(), let copyValue, let setValue else { return false }
        guard let raw = copyValue(store, keyPointer(), nil) else { return false }

        let current = NSMutableDictionary(dictionary: Unmanaged<NSDictionary>.fromOpaque(raw).takeRetainedValue())
        current["State"] = enabled ? 1023 : 1022
        current["Errnum"] = 0

        let valuePtr = Unmanaged.passUnretained(current as CFDictionary).toOpaque()
        return setValue(store, keyPointer(), UnsafeRawPointer(valuePtr))
    }

    /// 写完之后再读一次，验证是否真的生效。
    func writeAndVerify(_ enabled: Bool) -> Bool {
        guard writeEnabledState(enabled) else { return false }
        // 给 system 一点时间刷新
        Thread.sleep(forTimeInterval: 0.6)
        return read().isEnabled == enabled
    }
}

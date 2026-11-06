import Foundation
import Darwin

/// root 权限执行器。
///
/// JAILBREAK: App 通过 `posix_spawn` 拉起本程序，本程序带着
/// `com.apple.private.persona-mgmt` 签名，可以直接以 uid 0 跑。
/// 这是 TrollStore 官方 `Shared/TSUtil.m` 里 `spawnRoot` 的同一套思路。
///
/// 用法：
///   netpilot-helper hotspot-on
///   netpilot-helper hotspot-off
///   netpilot-helper status
///   netpilot-helper block 172.20.10.5
///   netpilot-helper unblock-all
///   netpilot-helper clients
///
/// 输出统一走 stdout，App 侧按文本读取。

// MARK: - 入口

let arguments = CommandLine.arguments.dropFirst()
guard let command = arguments.first else {
    print("usage: netpilot-helper <hotspot-on|hotspot-off|status|block|unblock-all|clients>")
    exit(2)
}

switch command {
case "hotspot-on":
    exit(Hotspot.toggle(enabled: true) ? 0 : 1)

case "hotspot-off":
    exit(Hotspot.toggle(enabled: false) ? 0 : 1)

case "status":
    Hotspot.printStatus()
    exit(0)

case "block":
    guard arguments.count >= 2 else {
        print("missing ip")
        exit(2)
    }
    let ip = Array(arguments)[1]
    exit(Firewall.block(ip: ip) ? 0 : 1)

case "unblock-all":
    exit(Firewall.clear() ? 0 : 1)

case "clients":
    print(Clients.dump())
    exit(0)

default:
    print("unknown command: \(command)")
    exit(2)
}

// MARK: - 热点

enum Hotspot {

    static let dynamicStoreKey = "com.apple.MobileInternetSharing"

    /// 开关热点。
    ///
    /// 以 root 身份执行时的顺序：
    /// 1. 写动态存储里的 State（1023/1022）
    /// 2. 通知 `sharingd` 重读：优先 `killall -HUP sharingd`
    /// 3. 再验证一次 State
    ///
    /// 注意：这里**没有**用 cycript / Frida 去 hook `sharingd`。那是最稳的但要额外
    /// 依赖注入框架。如果上面三步在目标系统上无效，下一步应该改成通过
    /// `libMobileInternetSharing` 的私有 C 函数（`MISManager`）直接调用，
    /// 或者对 `sharingd` 发 XPC。这两条都需要按具体 iOS 版本反汇编确认。
    static func toggle(enabled: Bool) -> Bool {
        let target = enabled ? 1023 : 1022

        guard writeState(target) else {
            print("write dynamic store failed")
            return false
        }

        // 让 sharingd 重新读取配置
        _ = run("/usr/bin/killall", ["-HUP", "sharingd"])
        Thread.sleep(forTimeInterval: 0.8)

        let current = readState()
        print("state=\(current) target=\(target)")
        return current == target
    }

    static func readState() -> Int {
        guard let value = copyDynamicStore() else { return -1 }
        return (value["State"] as? Int) ?? -1
    }

    static func printStatus() {
        guard let value = copyDynamicStore() else {
            print("unreadable")
            return
        }
        let state = (value["State"] as? Int) ?? -1
        let hosts = (value["Hosts"] as? [String: Any])?["Current"] as? Int ?? 0
        print("state=\(state) clients=\(hosts)")
    }

    static func copyDynamicStore() -> [String: Any]? {
        let handle = dlopen("/System/Library/Frameworks/SystemConfiguration.framework/SystemConfiguration", RTLD_NOW)
        guard let handle,
              let createSym = dlsym(handle, "SCDynamicStoreCreate"),
              let copySym = dlsym(handle, "SCDynamicStoreCopyValue") else { return nil }

        typealias CreateFn = @convention(c) (UnsafeRawPointer?, UnsafeRawPointer?, UnsafeRawPointer?, UnsafeRawPointer?) -> UnsafeMutableRawPointer?
        typealias CopyFn = @convention(c) (UnsafeMutableRawPointer?, UnsafeRawPointer?, UnsafeMutableRawPointer?) -> UnsafeMutableRawPointer?

        let create = unsafeBitCast(createSym, to: CreateFn.self)
        let copy = unsafeBitCast(copySym, to: CopyFn.self)

        let name = Unmanaged.passUnretained("NetPilotHelper" as CFString).toOpaque()
        let key = Unmanaged.passUnretained(dynamicStoreKey as CFString).toOpaque()

        guard let store = create(nil, UnsafeRawPointer(name), nil, nil) else { return nil }
        guard let raw = copy(store, UnsafeRawPointer(key), nil) else { return nil }

        return Unmanaged<NSDictionary>.fromOpaque(raw).takeRetainedValue() as? [String: Any]
    }

    static func writeState(_ state: Int) -> Bool {
        let handle = dlopen("/System/Library/Frameworks/SystemConfiguration.framework/SystemConfiguration", RTLD_NOW)
        guard let handle,
              let createSym = dlsym(handle, "SCDynamicStoreCreate"),
              let copySym = dlsym(handle, "SCDynamicStoreCopyValue"),
              let setSym = dlsym(handle, "SCDynamicStoreSetValue") else { return false }

        typealias CreateFn = @convention(c) (UnsafeRawPointer?, UnsafeRawPointer?, UnsafeRawPointer?, UnsafeRawPointer?) -> UnsafeMutableRawPointer?
        typealias CopyFn = @convention(c) (UnsafeMutableRawPointer?, UnsafeRawPointer?, UnsafeMutableRawPointer?) -> UnsafeMutableRawPointer?
        typealias SetFn = @convention(c) (UnsafeMutableRawPointer?, UnsafeRawPointer?, UnsafeRawPointer?) -> Bool

        let create = unsafeBitCast(createSym, to: CreateFn.self)
        let copy = unsafeBitCast(copySym, to: CopyFn.self)
        let set = unsafeBitCast(setSym, to: SetFn.self)

        let name = Unmanaged.passUnretained("NetPilotHelper" as CFString).toOpaque()
        let key = Unmanaged.passUnretained(dynamicStoreKey as CFString).toOpaque()

        guard let store = create(nil, UnsafeRawPointer(name), nil, nil),
              let raw = copy(store, UnsafeRawPointer(key), nil) else { return false }

        let dict = NSMutableDictionary(dictionary: Unmanaged<NSDictionary>.fromOpaque(raw).takeRetainedValue())
        dict["State"] = state
        dict["Errnum"] = state == 1023 ? 0 : 45

        return set(store, UnsafeRawPointer(key), UnsafeRawPointer(Unmanaged.passUnretained(dict as CFDictionary).toOpaque()))
    }

    /// iOS 上没有 `Process`（macOS 专属），只能用 posix_spawn。
    @discardableResult
    static func run(_ executable: String, _ args: [String]) -> String {
        guard FileManager.default.isExecutableFile(atPath: executable) else {
            return "not found: \(executable)"
        }

        var fds: [Int32] = [-1, -1]
        guard pipe(&fds) == 0 else { return "" }

        var actions: posix_spawn_file_actions_t?
        posix_spawn_file_actions_init(&actions)
        posix_spawn_file_actions_adddup2(&actions, fds[1], STDOUT_FILENO)
        posix_spawn_file_actions_adddup2(&actions, fds[1], STDERR_FILENO)
        posix_spawn_file_actions_addclose(&actions, fds[0])
        posix_spawn_file_actions_addclose(&actions, fds[1])

        var argv: [UnsafeMutablePointer<CChar>?] = ([executable] + args).map { strdup($0) }
        argv.append(nil)

        var envp: [UnsafeMutablePointer<CChar>?] =
            (["PATH=/var/jb/usr/bin:/usr/bin:/bin:/usr/sbin:/sbin"] as [String]).map { strdup($0) }
        envp.append(nil)

        var pid: pid_t = 0
        let spawnResult = posix_spawn(&pid, executable, &actions, nil, argv, envp)
        posix_spawn_file_actions_destroy(&actions)
        argv.forEach { free($0) }
        envp.forEach { free($0) }
        close(fds[1])

        guard spawnResult == 0 else {
            close(fds[0])
            return "spawn failed: \(spawnResult)"
        }

        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        while true {
            let n = read(fds[0], &buffer, buffer.count)
            if n > 0 { data.append(contentsOf: buffer[0..<n]) } else { break }
        }
        close(fds[0])

        var status: Int32 = 0
        waitpid(pid, &status, 0)
        return String(data: data, encoding: .utf8) ?? ""
    }
}

// MARK: - 防火墙

enum Firewall {

    static let anchor = "com.benteng.netpilot"
    static let rulesPath = "/var/mobile/Library/NetPilot/pf.rules"

    static func block(ip: String) -> Bool {
        let rule = """
        block drop quick from \(ip) to any
        block drop quick from any to \(ip)

        """

        var existing = (try? String(contentsOfFile: rulesPath, encoding: .utf8)) ?? ""
        guard !existing.contains(ip) else {
            print("already blocked: \(ip)")
            return true
        }
        existing += rule

        do {
            try FileManager.default.createDirectory(atPath: "/var/mobile/Library/NetPilot",
                                                    withIntermediateDirectories: true)
            try existing.write(toFile: rulesPath, atomically: true, encoding: .utf8)
        } catch {
            print("write rules failed: \(error)")
            return false
        }

        let output = Hotspot.run("/sbin/pfctl", ["-a", anchor, "-f", rulesPath])
        print(output)
        return true
    }

    static func clear() -> Bool {
        let output = Hotspot.run("/sbin/pfctl", ["-a", anchor, "-F", "rules"])
        print(output)
        try? FileManager.default.removeItem(atPath: rulesPath)
        return true
    }
}

// MARK: - 客户端列表

enum Clients {

    static func dump() -> String {
        let path = "/var/db/dhcpd_leases"
        guard let content = try? String(contentsOfFile: path, encoding: .utf8) else {
            return "unreadable: \(path)"
        }
        return content
    }
}

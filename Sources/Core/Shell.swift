import Foundation
import Darwin

/// 极简命令执行器。
///
/// iOS 上没有 `Process` / `NSTask`（那是 macOS 专属），只能用 `posix_spawn`。
/// JAILBREAK: 需要 `com.apple.private.security.no-sandbox` 才能 spawn 系统二进制，
/// 这也是 TrollStore 安装时必须预埋的 entitlement 之一。
enum Shell {

    struct Result {
        var status: Int32
        var output: String
        var isSuccess: Bool { status == 0 }
    }

    @discardableResult
    static func run(_ executable: String, _ arguments: [String] = []) -> Result {
        // 找可执行文件真实路径（越狱机 /var/jb 前缀由调用方处理）
        guard FileManager.default.isExecutableFile(atPath: executable) else {
            return Result(status: -1, output: "not found: \(executable)")
        }

        var fds: [Int32] = [-1, -1]
        guard pipe(&fds) == 0 else {
            return Result(status: -1, output: "pipe failed")
        }
        let readFD = fds[0]
        let writeFD = fds[1]

        var actions: posix_spawn_file_actions_t?
        posix_spawn_file_actions_init(&actions)
        posix_spawn_file_actions_adddup2(&actions, writeFD, STDOUT_FILENO)
        posix_spawn_file_actions_adddup2(&actions, writeFD, STDERR_FILENO)
        posix_spawn_file_actions_addclose(&actions, readFD)
        posix_spawn_file_actions_addclose(&actions, writeFD)

        var argv: [UnsafeMutablePointer<CChar>?] = ([executable] + arguments).map { strdup($0) }
        argv.append(nil)

        // Swift 里拿不到 _NSGetEnviron()，自己构造一份。
        // 顺带把 rootless 越狱（Dopamine）的 /var/jb/usr/bin 放进 PATH。
        var envp: [UnsafeMutablePointer<CChar>?] =
            (["PATH=/var/jb/usr/bin:/usr/bin:/bin:/usr/sbin:/sbin"] as [String]).map { strdup($0) }
        envp.append(nil)

        var pid: pid_t = 0
        let spawnStatus = posix_spawn(&pid, executable, &actions, nil, argv, envp)

        posix_spawn_file_actions_destroy(&actions)
        argv.forEach { free($0) }
        envp.forEach { free($0) }
        close(writeFD)

        guard spawnStatus == 0 else {
            close(readFD)
            return Result(status: spawnStatus, output: "spawn failed: \(spawnStatus)")
        }

        // 读管道
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        while true {
            let n = read(readFD, &buffer, buffer.count)
            if n > 0 {
                data.append(contentsOf: buffer[0..<n])
            } else {
                break
            }
        }
        close(readFD)

        var status: Int32 = 0
        waitpid(pid, &status, 0)
        let exitCode = (status & 0x7F) == 0 ? (status >> 8) : -1

        return Result(status: exitCode,
                      output: String(data: data, encoding: .utf8) ?? "")
    }

    /// 越狱环境下的路径解析：rootless 越狱二进制在 /var/jb 下。
    static func resolve(_ path: String) -> String {
        let jbPath = "/var/jb" + path
        if FileManager.default.isExecutableFile(atPath: jbPath) { return jbPath }
        return path
    }
}

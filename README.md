# NetPilot · iOS 网络助手

流量统计 + 个人热点管控 + 全流量代理，面向 **TrollStore / 越狱设备**的侧载 IPA。

> 本项目不针对 App Store。所有私有 API 用法在 `// JAILBREAK:` 注释中标注。

---

## 一、功能与可行性

| 模块 | 实现方式 | 状态 |
|---|---|---|
| 流量统计 | `getifaddrs` + `if_data` 网卡计数器，本地月度累加 | ✅ 稳定 |
| 热点状态 | 私有 API 读 `com.apple.MobileInternetSharing` 动态存储 | ✅ 稳定 |
| 热点开关 | root helper → 写动态存储 / 调 `sharingd` | ⚠️ 需真机验证 |
| 已连设备列表 | 解析 `/var/db/dhcpd_leases` | ⚠️ 路径随版本变化 |
| 设备拉黑 | `pf` 在 `bridge100` 上按源 IP 阻断 | ⚠️ 需真机验证 |
| 全流量代理 | `NEPacketTunnelProvider` + 自备内核 | 🔧 骨架已就位 |

### 已知边界（不要试着突破，浪费时间）

1. **流量分不出是哪个 App 用的**。`getifaddrs` 是内核网卡计数，系统不暴露 per-app 统计。设备重启清零，必须靠本地持久化累加。
2. **读不到运营商计费数据**。只有「设置」里有，第三方无 API。
3. **`SCDynamicStoreSetValue` 写热点开关在 iOS 14+ 大部分版本无效**。`sharingd` 会校验调用来源，纯写键值不生效。真正可靠的是 root helper 里对 `sharingd` 发 XPC 或用 `launchctl` 踢它重读配置。这部分需要按你的具体 iOS 版本调试。
4. **TrollStore 拿不到平台化签名**，起不了 launchd 守护进程、注不进系统进程。所以热点控制只能走「root helper 执行一次性命令行」的模式，不能挂常驻守护。
5. **NEPacketTunnel 扩展在 TrollStore 下可能被 `nehelper` 拒**。如果实测起不来，备选方案是越狱环境下直接用 `utun` 设备建隧道，跳过 NetworkExtension。代码里留了切换点。

---

## 二、构建

本机需要 **Xcode 15+**（写本工程时我没有 Xcode，代码未经编译验证，首次编译可能需要修小错）。

```bash
# 1. 安装 XcodeGen
brew install xcodegen

# 2. 生成 Xcode 工程
cd NetPilot
xcodegen generate

# 3. 打开
open NetPilot.xcodeproj
```

### 出 IPA（TrollStore 路线）

TrollStore 需要 **未签名 IPA + 预埋 entitlements**：

```bash
chmod +x Tools/build-ipa.sh
./Tools/build-ipa.sh
# 产物：build/NetPilot.ipa
```

脚本内部流程：
1. `xcodebuild CODE_SIGNING_ALLOWED=NO` 编译出 `.app`
2. 用 `ldid -SEntitlements/NetPilot.entitlements` 给主二进制假签名
3. 同样处理 `PlugIns/PacketTunnel.appex` 和 `Tools/RootHelper`
4. 打包成 `Payload/NetPilot.app` → zip → `.ipa`
5. 拖进 TrollStore 安装

> 需要 `ldid`：`brew install ldid`（或 `npm i -g ldid`）

### 真越狱路线（palera1n / Dopamine）

如果走 rootless 越狱，可以直接用 Theos 打成 deb，把 App 装进 `/var/jb/Applications`，root helper 装进 `/var/jb/usr/bin`。此时 `pf` 和 `sharingd` 的权限问题会小很多。

---

## 三、目录结构

```
NetPilot/
├── project.yml                  XcodeGen 配置（3 个 target）
├── Sources/
│   ├── App/
│   │   ├── NetPilotApp.swift    入口
│   │   └── RootView.swift       三个 Tab + 全部界面
│   └── Core/
│       ├── InterfaceReader.swift   getifaddrs 网卡计数器
│       ├── UsageStore.swift        月度流量累加与持久化
│       ├── HotspotMonitor.swift    热点状态（dlopen 私有符号）
│       ├── HotspotClients.swift    DHCP leases / ARP 解析
│       ├── HotspotController.swift 开关热点（root helper）
│       ├── ClientBlocker.swift     pf 规则阻断
│       └── ProxyManager.swift      NETunnelProviderManager 封装
├── Extension/
│   └── PacketTunnelProvider.swift  透明代理隧道
├── Tools/
│   ├── RootHelper/main.swift       root 权限执行器
│   └── build-ipa.sh               一键出 IPA
└── Entitlements/
    ├── NetPilot.entitlements
    ├── PacketTunnel.entitlements
    └── RootHelper.entitlements
```

---

## 四、私有 API 用了哪些

| 符号 / 路径 | 用途 | 稳定性 |
|---|---|---|
| `SCDynamicStoreCreate` / `SCDynamicStoreCopyValue` | 读热点状态字典 | 高（iOS 6+ 一直存在，只是头文件标了 unavailable） |
| `SCDynamicStoreSetValue` | 写热点开关 | 低，多数版本不生效 |
| `com.apple.MobileInternetSharing` | 动态存储 key | 高 |
| `/var/db/dhcpd_leases` | 热点已连设备 | 中，新版本可能迁移 |
| `prefs:root=INTERNET_TETHERING` | 跳转热点设置页 | 高（降级兜底） |
| `pfctl` | 阻断拉黑设备 | 低，需 root 且系统盘是 SSV 只读 |

读取类符号全部用 `dlsym` 动态取，**不依赖私有头文件**，不会因为 Xcode 版本升级而编译失败。

---

## 五、下一步待办

- [ ] 真机验证 `SCDynamicStoreSetValue` 写 State=1023 是否真的开热点（大概率不行，需换 sharingd XPC）
- [ ] 验证 `/var/db/dhcpd_leases` 在目标 iOS 版本上是否存在
- [ ] 验证 `pfctl` 在目标设备上可执行且能加载 anchor
- [ ] 接入代理内核（sing-box / Xray 的 XCFramework）
- [ ] 订阅管理、分流规则、按 App 代理
- [ ] 小组件（WidgetKit）显示当月流量

---

## 六、许可与风险

- 私有 API + 越狱环境，**仅限自用**，不得分发到 App Store。
- 修改网络栈有让设备无法联网的风险，建议先在一台备用机上测试。
- `pf` 规则写错可能导致手机自身断网，代码里已加 `pfctl -a <anchor> -F all` 的清理入口。

---

## 七、已跑通的本地测试

```bash
./Tools/test-local.sh
```

在没有 Xcode / iOS SDK 的环境下，把不依赖 UIKit 与 NetworkExtension 的纯逻辑模块用本机 Swift 真实编译并执行。

**当前结果：32 项全通过。**

覆盖范围：
- DHCP 租约解析（多设备、缺主机名、乱码输入、IP 数值排序）
- 流量增量算法（正常增长 / 数值不变 / 计数器归零视为重启 / 首次运行）
- 月份 key（跨年不串月）
- pf 规则生成（空列表 / 单 IP 双向 / 多 IP / 非法 IP 过滤）
- 真实网卡计数器（读本机 `getifaddrs`，发真实请求验证计数增长）
- 字节格式化

### 测试过程中修掉的两个真 bug

1. **`hasHotspotBridge()` 判定错误**
   原实现是「存在 `bridge*` 接口即视为热点开启」。实测 macOS 15.6 默认就带 `bridge0`、`bridge100`、`bridge101`（AirDrop / Continuity 在用），iOS 同样有常驻 bridge 接口。这会让热点状态永远显示「已开启」。
   已改为检查桥接接口是否持有 `172.20.10.1/28` 这个个人热点固定网关地址。

2. **`_NSGetEnviron()` 在 Swift 中不可用**
   `posix_spawn` 需要 envp 参数，原代码直接调 `_NSGetEnviron()` 编译失败。已改为自建环境变量数组，顺带把 rootless 越狱的 `/var/jb/usr/bin` 写进 PATH。

---

## 八、CI 构建（本机没有 Xcode 时的方案）

本机装不了 Xcode（磁盘只剩 6.4 GB，需要 15 GB 下载 + 约 40 GB 展开）。用 GitHub Actions 的 macOS 机器构建，不占本地磁盘：

```bash
cd NetPilot
git init && git add . && git commit -m "init"
gh repo create netpilot --private --source=. --push
```

推送后自动触发 `.github/workflows/build-ipa.yml`，在 Actions 页面下载 `NetPilot-ipa` 产物，传到手机用 TrollStore 安装。

工作流包含 11 个步骤：检查工具链 → 装 xcodegen/ldid → 生成工程 → 无签名编译 → 校验产物 → 放入 root helper → ldid 签名 → 打包 IPA → 上传产物 → 失败时上传日志。

---

## 九、iPhone 14 Pro / iOS 16.4.1 适配结论

这台机器（A16 + iOS 16.4.1）的条件比预想的好：

| 项目 | 结论 |
|---|---|
| TrollStore | ✅ 支持（TrollStore 2 覆盖 15.0 – 16.6.1） |
| Dopamine 2 越狱 | ✅ 支持（A15 – A16 覆盖 iOS 15.0 – 16.5，16.4.1 在内） |
| 越狱形态 | **无根（rootless）**，系统外文件全部在 `/var/jb` 下 |
| 被封禁的 entitlement | `cs.debugger`、`dynamic-codesigning`、`skip-library-validation` 三条，**本项目未使用** |
| `platform-application` | 可用，但拿不到真正的 `CS_PLATFORMIZED`，无法启动 LaunchDaemon |

**推荐组合：Dopamine 越狱 + TrollStore 装包。**
Dopamine 提供 root 与 `/var/jb` 环境（`Shell.resolve()` 已做前缀回退），TrollStore 负责带 entitlements 的永久安装。

### 因 rootless 需要调整的地方

- 所有二进制路径走 `Shell.resolve()`，优先 `/var/jb` 前缀
- `pfctl` 路径同样需要检查 `/var/jb/sbin/pfctl`
- 系统卷只读，**不能修改 `/etc/pf.conf`**，所以规则走独立 anchor + 自定义路径（已实现）

### 尚未解决的风险

`pf` 在 iOS 上是否可用存在争议：有资料称 iOS 内核未编译 pf/ipfw 模块，也有资料称 iOS 有 pf 且 `pfctl` 可用。**这一点必须真机验证**。若 `pf` 不可用，设备拉黑需要改用 ARP 层方案（向客户端伪造网关 MAC 使其断网），实现方式完全不同，代码尚未编写。


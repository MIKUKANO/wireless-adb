# 无线 ADB · 稳定连接

面向 SukiSU / KernelSU 的中文模块管理页。当前为 **v2.0.0-rc1 测试版，未在 ACE 6T 上实测**。

## 使用

1. 通过管理器安装 `wireless-adb-v2.0.0-rc1.zip` 后重启。
2. 在模块列表打开 WebUI，开启“启用无线 ADB”，选择模式，点击“保存并应用”。新安装默认关闭，升级保留原开关。
3. 复制管理页显示的 `adb connect` 命令，在电脑执行；首次连接按系统提示授权。
4. 不用时点击“关闭远程连接”。开关状态保留到下一次启动。

### 两种模式

| 模式 | 适用与边界 |
| --- | --- |
| 固定端口 TCP | 独立于系统无线调试开关，绑定当前 Wi-Fi IPv4 地址；保留系统 RSA 授权，但不加密传输。首次授权可能需要 USB 调试已启用。 |
| 原生 TLS | 请求系统启用无线调试，保留加密、配对、已配对设备与 mDNS 功能。端口由系统分配，仍受 ROM 的原生服务和网络策略影响。 |

TLS 首次使用：点击“系统配对与授权”，在系统页面获取配对码和配对端口，在电脑执行 `adb pair 手机IP:配对端口`，之后使用管理页显示的**连接端口**。配对端口和连接端口不同。移除已配对设备也通过系统页面完成。

## 产品行为与省电

- **无定时自检、无 watchdog、无页面自动刷新、无常驻模块进程、无唤醒锁。**
- 开机脚本仅等待系统启动完成，执行一次应用配置后退出。管理页只在打开、手动刷新或操作后读取状态。
- 不设置空闲断开；已有 TCP 监听正常时不主动重启。明确切换模式/端口或关闭功能会中断相应连接。
- **系统杀掉 adbd 后不会自动拉起**；需要打开通知或模块页重新应用。
- TCP 绑定的是启用当时的 Wi-Fi 地址；更换 Wi-Fi、IP 改变或开机时没有 Wi-Fi 后，需要重新应用。
- 不声明“零耗电”。adbd 和活动连接本身有开销，待机功耗需真机测量。

## 通知栏入口

使用系统 `cmd notification post` 和管理器公开的 `ksu://webui?id=wireless-adb` 深链，不注入 SystemUI，不安装额外 APK。已检查当前 KernelSU、SukiSU 的深链声明；具体版本点击能否直达需要实测。未知管理器不会猜测私有 Activity。

通知不展示 IP，可划除；关闭“通知栏管理入口”后不再发送，已存在的通知可手动划除。系统屏蔽通知时，入口可能不显示。重新应用可再次发送。它是通知快捷入口，不是不可清除的 LSPosed 式寄生管理器。

## 安全边界

- 无外部脚本、字体、统计、联网请求或下载执行；WebUI CSP 禁止网络连接和内联脚本。
- 端口与模式由前后端分别校验；配置按数据解析，不 `source` / `eval`；配置原子替换并限制权限。
- 不写入自带 ADB 密钥，不关闭 RSA 授权，不修改 `ro.adb.secure`、SELinux 或 USB 调试开关。
- `ro.adb.secure=1` 只作为保守前置检查，不能证明厂商 adbd 未被修改，仍需未授权客户端握手测试。
- 关闭 TCP 时绑定回环地址，避免某些 adbd 在 `-1` 时回退到默认 TCP 端口。USB 调试开关和授权密钥保留。
- 若 ROM 不支持指定监听地址且检测到远程监听残留，会尝试停止 adbd 并报错；此时 USB ADB 也可能暂时不可用，应先禁用模块并重启排查。
- 本模块不实现 root / ADB 环境伪装，不保证其他 App 检测不到。仅减少通知地址和日志信息暴露。
- 原生日志不记录密钥、设备序列号或 IP；诊断页包含本机连接地址，分享前自行查看。

本项目不是新写一套 adbd，也不宣称在所有 ROM 上完美替代原生无线调试。

## 恢复与卸载

首次接管前保存当前 TCP 监听与 TLS 开关。卸载时尝试恢复该快照；配置保留方便重装。异常时可在 root 终端执行：

```sh
sh /data/adb/modules/wireless-adb/scripts/control.sh pause
sh /data/adb/modules/wireless-adb/scripts/control.sh doctor
```

如需完全恢复接管前状态，先在模块页关闭功能，再执行：

```sh
sh /data/adb/modules/wireless-adb/scripts/control.sh restore
```

## 开发验证

无需 Android SDK，不引入运行时依赖。

```sh
node --test tests/model.test.mjs
sh tests/shell_test.sh
python tools/build.py
```

可选 UI 测试需安装 `playwright@1.65.0`；使用 `PLAYWRIGHT_CHROME` 指定已有 Chrome，或安装 Playwright Chromium 后执行 `node tests/ui.test.mjs`。测试使用替身桥接和替身 Android 命令，不是真机结果。

真机验收：**未执行**。下一步先在管理器安装测试 ZIP，再通过已有 USB ADB 执行：

```sh
adb shell "su -c 'sh /data/adb/modules/wireless-adb/scripts/control.sh doctor'"
```

随后分别验证新电脑首次授权、TLS 配对、通知直达和关闭后远程端口不可达；对比相同网络/亮度/时长的待机功耗。建议保留 USB 连接进行首次验证。

原始安全审查见 [SECURITY_REVIEW.zh-CN.md](SECURITY_REVIEW.zh-CN.md)。上游作者 dracediax，fork 维护 MIKUKANO；保留来源。上游 README 标注 MIT，但基线未提供 LICENSE 文件，本次未擅自补造授权文本。

# 原始代码安全审查

## 结论

**在所审查源码与提交历史中未发现高危后门证据。** 这不是对所有发行 ZIP、ROM 或管理器环境的安全保证。

基线为 `MIKUKANO/wireless-adb` 的 `923a0094f011e74528fea25264418f2dabdc1d22`：共 7 个受控文件、8 次提交，无附带二进制、依赖下载器或子模块。查询时上游 `dracediax/wireless-adb/main` 指向相同提交。

## 源码观察

- 安装器仅调用已安装 Magisk 的模块安装函数；开机脚本设置 TCP ADB 属性、重启 adbd、发送本地通知。
- 未发现预埋 ADB 公钥、凭据收集、远程命令服务器、上传、下载执行或混淆载荷。
- `ip route get 1.1.1.1` 用于路由查询，不等于向该地址发送数据，不能据此判断回传。
- 文档的徽章与 GitHub 链接不属于模块运行时回传行为。

## 风险与已做变更

| 原始位置 | 判断与条件 | 本次处理 |
| --- | --- | --- |
| `webroot/index.html:298,310,356` | 将配置/诊断值拼接到 root shell，缺少统一边界校验。普通 number 输入对部分载荷有限制；不能因此宣称远程可直接利用。若另有 WebView 注入则后果严重。 | 固定控制器入口、白名单参数、双层校验；不将日志写入 shell 命令。 |
| `webroot/index.html:349–353` | 配置/日志未经转义进入 innerHTML，存在条件性 HTML 注入风险。原始数据主要由 root 写入，未证实低权限外部攻击路径。 | 所有诊断与状态使用 textContent；禁用内联脚本和运行时网络请求。 |
| `webroot/index.html:216–230` | 假定 exec 同步返回，不符合当前 KernelSU 官方回调桥接；异常被吞掉。 | 异步回调/结果码/超时处理；错误可见，不将未知结果当成功。 |
| `webroot/index.html:298` | echo 写入换行的行为依赖实现，且直接截断配置；可能出现配置损坏或保存误报。 | printf 真换行、临时文件和原子替换、root 私有权限。 |
| `service.sh` 与 `customize.sh` | 默认开机启用固定 TCP 端口；未校验实际监听和授权状态，没有自动恢复常驻服务。不是“连接永久在线”保证。 | 新安装默认关闭；授权属性前置检查、实际 socket 检查；手动开关；按用户要求不保留自检或 watchdog。 |
| 传统 TCP ADB 模式 | RSA 授权不等于 TLS 加密；与 Android 原生无线配对不是同一模式。 | UI 区分 TCP / 系统 TLS；保留系统配对页面，不虚构独立 TLS 服务。 |

## 验证与未覆盖项

- Node 测试覆盖参数注入拒绝、状态解析、原生桥接、错误与超时。
- Shell 行为测试使用 Android 命令替身，不操作电脑或手机的 ADB 服务。
- 浏览器测试覆盖中文 UI、保存与应用、错误反馈、诊断 HTML 注入、手动关闭、无桥接状态、深浅色与手机尺寸；模拟状态不代表真机连接。
- 打包器只包含显式运行时文件，检查 LF、ZIP 完整性及包内/源码字节一致性。
- **未执行：** 原发行附件与源码的等价性验证、ACE 6T 实机安装、RSA 未授权握手阻断、TLS 配对、通知直达、重启/休眠稳定性与功耗测量。
- **未实现：** root / ADB 环境隐藏、SystemUI 注入、不可清除寄生通知。通知实现为管理器公开深链快捷入口。

## 技术依据

- [AOSP ADB Wi-Fi 架构：TCP 与 TLS 的区别](https://android.googlesource.com/platform/packages/modules/adb/+/refs/heads/main/docs/dev/adb_wifi.md)
- [AOSP adbd：监听地址、端口及默认回退](https://android.googlesource.com/platform/packages/modules/adb/+/refs/heads/main/daemon/main.cpp)
- [KernelSU WebUI 文档](https://kernelsu.org/guide/module-webui.html)
- [KernelSU JavaScript 桥接实现](https://github.com/tiann/KernelSU/blob/main/js/index.js)
- [KernelSU 深链声明](https://github.com/tiann/KernelSU/blob/main/manager/app/src/main/AndroidManifest.xml)
- [SukiSU 深链声明](https://github.com/SukiSU-Ultra/SukiSU-Ultra/blob/main/manager/app/src/main/AndroidManifest.xml)

以上动态分支资料用于解释实现；设备 ROM 和管理器版本仍需独立验证。

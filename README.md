# 无线 ADB

> 持久无线 ADB 调试 — 开机自动启用，持续保持可连接。

![KernelSU](https://img.shields.io/badge/KernelSU-Module-green?style=flat-square)
![Magisk](https://img.shields.io/badge/Magisk-Compatible-blue?style=flat-square)
![APatch](https://img.shields.io/badge/APatch-Compatible-purple?style=flat-square)
![Android](https://img.shields.io/badge/Android-12%2B-orange?style=flat-square)
![License](https://img.shields.io/badge/License-MIT-yellow?style=flat-square)

---

## 存在的问题

无线 ADB 在每次重启后都会重置，需要重新开启、查找端口并再次连接。

## 解决方式

刷入一次后，每次开机都会在固定端口启用无线 ADB，直接连接即可。

```
adb connect <phone-ip>:5555
```

---

## 快速开始

1. 从[发布页面](https://github.com/dracediax/wireless-adb/releases)下载最新的 `.zip`
2. 通过模块管理器刷入
3. 重启
4. 你会收到包含连接地址的通知
5. 在电脑上执行： `adb connect <ip>:5555`

---

## 网页管理界面

- **实时状态** — 启用时显示绿点，禁用时显示灰点
- **连接地址** — 点击即可复制 `adb connect <ip>:<port>`
- **启用／禁用开关** — 控制是否开机启用
- **自定义端口** — 默认 5555，可自行设置
- **立即应用** — 无需重启即可启用或禁用

---

<details>
<summary><b>电量影响</b></summary>

**无额外影响（原项目说明）。** 模块在开机时执行一次脚本，约 1 秒后退出；没有常驻后台进程、轮询或唤醒锁。

启用 USB 调试的手机本就运行着 ADB 守护进程（`adbd`）。本模块仅让它同时监听 TCP；原项目称不会增加电量消耗。

</details>

<details>
<summary><b>安全提示</b></summary>

**无线 ADB 会向能够连接的设备开放调试访问。**

- 仅在**可信的私有网络**中使用，例如防火墙后的家庭 Wi-Fi
- **切勿**在公共 Wi-Fi、咖啡馆、酒店或访客网络中启用
- **切勿**通过端口转发将调试端口暴露到外网
- 连接仍需要已授权的 ADB 密钥（RSA 指纹确认提示）
- 不进行调试时，可通过网页管理界面关闭

</details>

<details>
<summary><b>工作原理</b></summary>

开机后，`service.sh` 执行：
```bash
setprop service.adb.tcp.port 5555
stop adbd
start adbd
```

这会让 ADB 守护进程在配置的端口上监听 TCP。手机的 Wi-Fi IP 会自动检测并显示在通知及网页管理界面中。

配置保存在 `/data/adb/wadb_config`，模块更新后仍会保留。

### 通过 ADB 查看调试日志

```
adb shell "su -c 'cat /data/adb/modules/wireless-adb/debug.log'"
```

</details>

---

## 兼容性

| 管理器 | 是否支持 |
|---------|-------|
| KernelSU / KernelSU Next | 支持 |
| Magisk | 支持 |
| APatch | 支持 |
| KsuWebUI（独立版） | 支持 |

网页界面需要支持 WebUI 的管理器，或使用 [KsuWebUI](https://github.com/adivenxnataly/KsuWebUI).

---

## 许可证

MIT

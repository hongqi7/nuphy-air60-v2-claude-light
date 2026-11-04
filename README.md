# NuPhy Air60 V2 × AI Agent 状态灯

让 **NuPhy Air60 V2** 键盘两侧的 RGB 侧灯跟着 AI 编程助手的状态变化。支持 [Claude Code](https://claude.com/claude-code)、WorkBuddy、Devin（本机会话），几个工具、几个会话同时开也没问题：

| Agent 在做什么 | 侧灯 |
|---|---|
| 思考中、调用工具干活中 | 🟠 Claude 橙色呼吸，约 2 秒一次 |
| 等你确认（权限批准框、选择题提问框） | 🔵 蓝色呼吸，约 1.2 秒一次 |
| 这一轮回答完成 | 🟢 绿色呼吸，约 3 秒一次 |
| 会话结束 / 没在用 | 恢复你自己设置的侧灯效果 |

不用盯着屏幕，余光看一眼键盘就知道 agent 还在跑、在等你，还是已经干完了。蓝牙、有线下都能用。

**Mac 端推荐用 [Agent Lumen（灵光）](https://github.com/hongqi7/agent-lumen)**：一个状态栏小 App，下载即用。它负责接入各个 AI 工具、驱动键盘灯，还会在屏幕边缘和状态栏用同样的颜色、同样的呼吸节奏一起亮。本仓库的 `host/` 脚本是不装 App 的命令行方案，**两者二选一**：Agent Lumen 接入时会自动把这里的钩子换成它的。

另有 **NuPhy Halo65 V2** 的补丁（整圈光环显示状态），见[下文](#halo65-v2)。

> English summary is at the [bottom](#english-summary).

---

## 适用硬件

- **键盘：NuPhy Air60 V2（ANSI 配列）**，主控 STM32F072，出厂固件基于 QMK
- **电脑：macOS**（用到了 IOKit，Windows / Linux 暂不支持）
- **连接方式**：蓝牙、有线已实测；2.4G 接收器走的是同一条代码路径，理论上可用但未实测
- 键盘背面的系统开关需拨到 **Mac 模式**。Win 模式下固件行为和原厂完全一样

其他 NuPhy V2 系列（Air75 V2、Air96 V2 等）用的是同一套开源代码结构，改起来思路相同，但本仓库只在 Air60 V2 上验证过，**别直接把这里的 bin 刷到别的型号上**。Halo65 V2 有单独的补丁，已实机验证。

注意：NuPhy 后来的 V3 系列和标着「IO 版」的型号换成了闭源固件，没法这样改。

---

## 工作原理

```
Claude Code / WorkBuddy / Devin 钩子 ──► Agent Lumen（或 claude-light 脚本 + kbled）
                                              │  Num Lock / Scroll Lock 指示灯信号
                                              ▼  （标准 HID 输出报告，蓝牙也能传）
                                         键盘里改过的固件 ──► 两侧灯条
```

1. **借用两个没人用的指示灯信号传状态。** 电脑可以通过标准 HID 协议告诉键盘「Num Lock / Caps Lock / Scroll Lock 灯该不该亮」，这也是 Mac 点亮大写锁定灯的方式。macOS 平时根本不用 Num Lock 和 Scroll Lock，正好拿来当暗号：

   | Num Lock | Scroll Lock | 含义 |
   |:---:|:---:|---|
   | 1 | 0 | 工作中（橙） |
   | 0 | 1 | 完成（绿） |
   | 1 | 1 | 等你确认（蓝） |
   | 0 | 0 | 空闲，恢复原灯效 |

   NuPhy 的开源固件里，无线模块会把这 3 位指示灯状态原样转给主控（见上游 `rf.c` 里对 `rf_led` 的处理），所以**蓝牙下也能用**，不需要插线。

2. **固件改动**（[`firmware/claude-light.patch`](firmware/claude-light.patch)，只动了两个文件）：
   - `side.c`：新增 `claude_led_show()`，读到上面的信号就接管左右两条侧灯；没信号时完全不干预。大写锁定、低电量、连接状态等原有提示仍然优先显示。三种状态都呼吸（蓝 1.2 秒、橙 2 秒、绿 3 秒，35%～100%），节奏按时钟计算，和 Agent Lumen 的屏幕光用同一张呼吸曲线表。
   - `sleep.c`：Claude 工作中或等你确认时，键盘不进入 6 分钟无操作休眠，免得长任务跑到一半灯灭了。完成后照常休眠。
   - **亮度和「整个键盘一起呼吸」**（配合 Agent Lumen）：插着 USB 线时，Agent Lumen 通过 VIA 的 raw HID 通道把三种状态各自的亮度、以及「按键背光也跟着呼吸」的开关发给键盘，键盘存进 EEPROM（停手 2 秒后才写，避免拖滑块时反复写入）。拔线后走蓝牙 / 2.4G 照样按最后一次的设置亮。无线模块只转发指示灯那 3 位，所以无线时改不了设置，下次插线 App 会自动同步。
     协议：`'L' 'M' 0x01 <工作中> <完成> <等你确认> <flags>` 设置（flags bit0 = 整个键盘一起呼吸），`'L' 'M' 0x02` 读取；回包带当前值，第 8 字节是协议版本 1。
   - 注意：这一版在键盘设置区多占了 4 个字节，**Air60 刷完后侧灯模式、亮度会恢复默认一次**（用键盘快捷键重新调即可）；另外每次刷固件 VIA 改键都会被重置（QMK 用编译日期校验）。

3. **Mac 端**：推荐 [Agent Lumen](https://github.com/hongqi7/agent-lumen)。也可以用本仓库的命令行方案（[`host/`](host/)）：
   - `kbled`：约 130 行 C，用 IOKit 设置键盘的指示灯。只写指示灯，**不读取任何按键内容**，不联网。
   - `claude-light`：给各 agent 钩子调用的小脚本，按会话记录状态（其他 agent 的会话带上 `workbuddy-`、`devin-` 前缀），多个会话同时运行时显示最紧急的那个（蓝 > 橙 > 绿）。
   - `kbled watch`（可选的后台程序）：键盘断开重连后（切换模式、休眠醒来）指示灯状态会被清空，它会在键盘连上约 2 秒后补发当前状态，另外每 20 秒补发一次兜底。

### 关于颜色的一个坑

这块键盘的灯珠**绿色特别亮**：NuPhy 自己的代码里 `(255, 64, 0)` 显示出来是「黄色」（有线模式指示），`(255, 32, 0)` 才是「橙色」。所以 Claude 橙用的是 `(255, 20, 3)`。

另外，呼吸时如果直接把 RGB 按亮度整数缩放，绿色这个小数值在低亮度下会先被舍掉，导致颜色一会儿偏黄一会儿偏红。现在的实现是三个通道按同一比例、带四舍五入地缩放，并且最暗只到 35%，整个呼吸过程色相基本不变。

---

## 安装

### 0. 准备

```bash
brew install dfu-util
```

### 1. 进入刷机模式（DFU）

Air60 V2 有内置电池，**只拔插数据线不会让键盘重启**，所以按住 Esc 插线没用。正确做法：

1. 用数据线把键盘接到 Mac（最好直接插机身接口，别经过扩展坞）
2. 把连接方式开关拨到「关闭电源」
3. **按住 Esc**，把开关拨到中间的「有线模式」
4. 继续按住约 2 秒后松开

此时键盘不亮灯、打字没反应，是正常的。确认 Mac 认到了：

```bash
dfu-util -l
```

能看到 `[0483:df11] ... name="@Internal Flash ..."` 就对了。

### 2. 先备份键盘现在的固件（强烈建议）

出厂固件和公开源码编出来的不完全一样，想 100% 还原就靠这份备份：

```bash
dfu-util -d 0483:df11 -a 0 -s 0x08000000:131072 -U air60v2_backup.bin
```

### 3. 刷入状态灯固件

用仓库里编好的：

```bash
dfu-util -d 0483:df11 -a 0 -s 0x08000000:leave -D firmware/nuphy_air60_v2_ansi_via_claude-light.bin
```

或者自己从源码编译（会自动拉取 NuPhy 官方源码、打补丁、编译）：

```bash
./firmware/build.sh
dfu-util -d 0483:df11 -a 0 -s 0x08000000:leave -D firmware/nuphy_air60_v2_ansi_via.bin
```

刷完键盘自动重启。蓝牙配对信息存在无线模块里，刷机不影响；键位和灯效设置一般也会保留。

### 4. 安装 Mac 端

**推荐：** 下载 [Agent Lumen](https://github.com/hongqi7/agent-lumen/releases/latest)，打开后点「接入」。连上 NuPhy 键盘时 macOS 会请求「输入监控」权限，允许后重开一次 App。

**或者用命令行方案**（不装 App）：

```bash
./host/install.sh
```

它会：
- 编译 `host/kbled`
- 往 `~/.claude/settings.json` 加入钩子；装了 WorkBuddy（有 `~/.workbuddy`）或 Devin（有 `~/.config/devin`）的话，也往 `~/.workbuddy/settings.json`、`~/.config/devin/config.json` 里加。改之前都会自动备份原文件，重复运行不会重复添加
- 安装重连补发的后台程序（LaunchAgent `local.claude-light.watch`）。不想要后台程序就用 `./host/install.sh --no-agent`

安装后新开一个会话（Devin 桌面版要先退出重开），发条消息，侧灯应该变成橙色呼吸，答完变绿。

### 加入的钩子

三个工具的钩子格式相同（WorkBuddy、Devin 都沿用了 Claude Code 的格式），只是支持的事件不完全一样：

| 钩子 | 动作 | Claude Code | WorkBuddy | Devin |
|---|---|:---:|:---:|:---:|
| `UserPromptSubmit` | 橙 | ✓ | ✓ | ✓ |
| `PostToolUse`（所有工具） | 橙（也用于批准后从蓝切回橙） | ✓ | ✓ | ✓ |
| `PreToolUse`（`AskUserQuestion`） | 蓝 | ✓ | | |
| `Notification`（`permission_prompt`） | 蓝 | ✓ | ✓ | |
| `PermissionRequest` | 蓝 | | ✓ | ✓ |
| `Stop` / `StopFailure` | 绿 | ✓ | ✓ | ✓（仅 `Stop`） |
| `SessionEnd` | 清除该会话 | ✓ | ✓ | ✓ |

Devin 有两个坑：
- 只认 `PreToolUse`、`PostToolUse`、`PermissionRequest`、`UserPromptSubmit`、`Stop`、`PostCompaction`、`SessionStart`、`SessionEnd`。`hooks` 里只要出现别的事件名，整份钩子配置都会被丢掉，所以别往里加 `Notification`。
- 在你答复「是否信任此工作区」之前不会运行任何钩子。

只有本机运行的会话会亮灯，Devin 云端会话不会。

---

## 日常使用与排错

- **灯卡在某个状态**（比如按 Esc 打断了 Claude，`Stop` 钩子不会触发）：
  ```bash
  ./host/claude-light off
  ```
  不管它的话，2 小时没有更新的会话会自动算作完成（变绿）。
- **完全没反应**：先确认键盘背面拨在 **Mac 模式**；再用 `./host/kbled list` 看 Mac 有没有认到键盘（蓝牙下名字类似 `NuPhy Air60 V2-1`）。
- **键盘名字不一样**：设置环境变量 `CLAUDE_LIGHT_KEYBOARD`（按名字子串匹配，默认 `NuPhy`，Air60 V2 和 Halo65 V2 都能匹配）。
- **某个 agent 不亮灯**：看 `~/.claude/claude-light/kbled-error.log`。钩子传来的数据里找不到 `session_id` 时，这里会记下前 300 个字符。脚本这时只记日志、正常退出：在钩子协议里退出码 2 表示「拦截」，会挡住你的提问或权限请求。
- **后台程序日志**：`~/.claude/claude-light/watch.log`；灯控出错记录在 `~/.claude/claude-light/kbled-error.log`。如果日志里出现 `IOHIDManagerOpen ... Input Monitoring`，到「系统设置 → 隐私与安全性 → 输入监控」里允许 `kbled`，或重启一次后台程序：
  ```bash
  launchctl kickstart -k gui/$(id -u)/local.claude-light.watch
  ```
- **自己编译时报 `stdint.h: No such file`**：Homebrew 的 `arm-none-eabi-gcc` 不带 C 标准库（newlib），要用 `osx-cross/arm/arm-gcc-bin@8`，`build.sh` 已经处理。

---

## Halo65 V2

已在一把 ANSI 配列的 Halo65 V2 上实测：USB 有线下三种状态的光环、亮度同步和按键背光都正常，蓝牙下光环会跟随状态变色；2.4G 未实测。蓝牙配对：开关拨到无线档，长按 Fn+Q 约 3 秒（Fn+1 是调屏幕亮度，不是配对键）。

配合 Agent Lumen 1.9.1 及以上版本，面板里的两个方块在蓝牙下也能立即切换（刷机后先用 USB 连接一次，让 App 确认固件版本；四种组合已在蓝牙下实测，USB 有线和 2.4G 未逐一实测）：

| 方块 | 控制的灯 | 关闭后 |
|---|---|---|
| 键盘呼吸灯（每种状态分别设置） | 左上角灯条 | 全黑 |
| 按键背光（三种状态共用） | 所有按键、光环、HALO 标志 | 全黑，包括键盘自身的按键灯效 |

App 没有运行时，键盘按保存的设置工作。HALO 标志没有独立灯珠，由光环的导光条照亮，所以无法只亮标志：单独点亮最近的灯珠时，Ins 或 Backspace 旁的缝隙也会透光，因此标志归入光环。仓库里不提供编好的 bin，需要自己编译；刷之前一定先备份原厂固件。

Halo65 V2（65% 配列、高轴）和 Air60 V2 是同一颗芯片（STM32F072）、同一套开源代码结构，刷机方式也一样。区别在于状态显示在键盘四周那圈 **50 颗灯的光环**上：

| 状态 | 光环 |
|---|---|
| 工作中 | 整圈橙色呼吸，约 2 秒一次 |
| 等你确认 | 整圈蓝色呼吸，约 1.2 秒一次 |
| 完成 | 整圈绿色呼吸，约 3 秒一次 |

配色按 NuPhy 自己给光环调的比例来：它的光环绿、蓝灯珠特别亮，官方色表里纯绿、纯蓝只用到 `0x60`，红色用到 `0xff`。另外 10 颗灯 NuPhy 单独换了一套偏暗红的色表，补丁按同样比例做了补偿。

买的时候认准标「QMK/VIA」的版本，「Halo IO」是闭源固件。

```bash
./firmware/build.sh halo65        # 补丁：firmware/halo65-claude-light.patch
# 进入刷机模式（同 Air60）后：
dfu-util -d 0483:df11 -a 0 -s 0x08000000:131072 -U halo65v2_backup.bin   # 先备份
dfu-util -d 0483:df11 -a 0 -s 0x08000000:leave -D firmware/nuphy_halo65_v2_ansi_via.bin
```

Mac 端不用另装，默认的 `NuPhy` 名字匹配两把键盘都认。

---

## 卸载与还原

```bash
./host/uninstall.sh
```

移除三个工具里的钩子和后台程序，并把灯恢复正常。固件留在键盘上也没关系：没有信号时它和原厂行为一致。

想彻底还原固件，进入刷机模式后刷回第 2 步的备份：

```bash
dfu-util -d 0483:df11 -a 0 -s 0x08000000:leave -D air60v2_backup.bin
```

STM32 的 DFU 刷机模式固化在芯片 ROM 里，刷坏了也能重新进入刷机模式恢复。

---

## 已知限制

- Claude Code 在回复正文里用文字向你提问（而不是弹出提问框）时，算作「这一轮完成」，显示绿色。
- 用户按 Esc 中断时不会触发 `Stop`，灯会停在橙色，直到下一次动作、会话结束，或 2 小时后自动转为绿色。
- 只在 macOS 上实现了 Mac 端；Windows / Linux 需要另写一个设置键盘指示灯的小工具（原理相同）。
- 固件基于上游提交 `f1856912d603800eaca227ae2e1c5c8548fdf261`（`nuphy-src/qmk_firmware` 的 `nuphy-keyboards` 分支）。

---

## 免责声明

- 本项目为个人 DIY，**与 NuPhy、Anthropic 均无关联**，非官方。
- 刷写第三方固件有风险，请先备份，风险自负。

## 许可证

GPL-2.0-or-later（固件改动派生自 GPL 授权的 QMK / NuPhy 源码）。详见 [LICENSE](LICENSE)。

---

## English summary

Turns the RGB side lights of a **NuPhy Air60 V2** (ANSI) into an AI agent status indicator on macOS: **orange** (2 s breath) while the agent is working, **blue** (1.2 s) while it waits for your approval or an answer, **green** (3 s) when the turn is done, and your normal lighting otherwise. The recommended Mac side is [Agent Lumen](https://github.com/hongqi7/agent-lumen), a menu bar app that connects the agents, drives the keyboard and glows the screen edge with the same colours and timing; `host/` is a script-only alternative (use one or the other). Works over Bluetooth and USB. Supports Claude Code, WorkBuddy and Devin (local sessions), all of which use the same hook format; `host/install.sh` adds the hooks to every one it finds. An experimental, not yet hardware-tested patch for the **NuPhy Halo65 V2** shows the state on its 50-LED halo (`firmware/build.sh halo65`).

How: agent hooks call `host/claude-light`, which uses IOKit (`host/kbled`) to set the keyboard's **Num Lock / Scroll Lock** indicator bits (macOS never uses them). A small patch to NuPhy's open-source QMK firmware (`firmware/claude-light.patch`, touching `side.c` and `sleep.c`) maps those bits to the side lights and keeps the board awake while Claude is busy. NuPhy's wireless module forwards the 3 lock bits, so it works over Bluetooth too.

Install: enter DFU (cable in → power switch off → hold Esc → switch to wired → release), back up with `dfu-util -U`, flash `firmware/nuphy_air60_v2_ansi_via_claude-light.bin` (or build with `firmware/build.sh`), then run `host/install.sh`. Uninstall with `host/uninstall.sh`; restore stock firmware from your backup.

Unofficial; not affiliated with NuPhy or Anthropic. Flash at your own risk. GPL-2.0-or-later.

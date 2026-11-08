# AGENTS.md

给接手的 agent（或未来的自己）看的操作手册。
**只写「不看就会踩坑」的东西**，不写代码细节。

最后更新：2026-11-08

---

## 1. 这是什么

儿童跳绳 AI 计数项目。摄像头识别姿态 → 数跳绳次数。

```
Web 版（H5）  = 算法实验台，长期保留，调参主战场
Flutter 版    = 最终产品，仅 Android
```

当前阶段：**算法验证**。Flutter 只做了 Dart 计数核心，还没有 App。

文档：
- `docs/跳绳AI计数产品方案.md` —— 产品与技术方案
- `docs/Flutter迁移计划.md` —— 迁移计划 v3

---

## 2. 目录地图

```
/root/dsh/test/
├── jumprope/                    Web 版
│   ├── public/
│   │   ├── counter.mjs          ★ 计数核心（唯一真理）
│   │   ├── posture.mjs          姿态判定（站/弯/蹲）
│   │   ├── model-cache.mjs      模型 Cache Storage 缓存
│   │   ├── app.js               主页面逻辑
│   │   ├── analyze.js/.html     离线视频分析页
│   │   └── models/ wasm/        自托管的模型与 WASM
│   ├── test/
│   │   ├── verify_both.sh       ★ 一条命令验证 JS + Dart
│   │   ├── golden/*.json        ★ 黄金测试向量
│   │   ├── extract.py           视频 → 关键点（Python MediaPipe）
│   │   ├── replay.mjs           关键点 → 计数（JS）
│   │   ├── make_golden.mjs      关键点 → 黄金向量
│   │   └── count_golden.mjs     黄金向量 → 计数
│   └── server.js                HTTPS 8080 / HTTP 80 / 上传下载
│
├── dart_core/                   Dart 计数核心（无 Flutter 依赖）
│   ├── lib/counter.dart         ★ counter.mjs 的移植
│   ├── verify.dart              跑黄金向量验证
│   └── pubspec.yaml
│
├── video/                       三个校准视频（标注在文件名里）
└── docs/
```

---

## 3. 常用命令

### 起服务

```bash
cd /root/dsh/test/jumprope && node server.js
```

| 端口 | 用途 |
|---|---|
| 8080 | HTTPS 主站（自签证书） |
| 80 | HTTP 跳转 + **APK 上传/下载** |
| 8001 | 仅本机 HTTP，调试验证用 |

> ⚠️ 停服务**不要用** `pkill -f "node server.js"` —— 它会匹配到自己的 shell 把自己杀掉。用 `pgrep` 拿 PID 再 `kill`。

### 验证算法（最常用）

```bash
cd /root/dsh/test/jumprope
bash test/verify_both.sh /root/dsh/test/video/168个断0次.mp4 168
```

输出 JS 计数、Dart 计数、一致性。约 34 秒/视频。

**三个基准视频的期望值**：`145 / 162 / 170`（对应标注 145 / 168 / 184）。

### 单独跑一端

```bash
# 只跑 JS
node test/replay.mjs /tmp/lm_168个断0次.json 168

# 只跑 Dart
cd /root/dsh/test/dart_core
dart run verify.dart ../jumprope/test/golden
```

### 提取关键点（用于离线分析）

```bash
python3 test/extract.py 视频.mp4 /tmp/lm.json
node test/analyze  # 或者用 /analyze.html 页面
```

### GitHub Actions 上传 APK

```bash
curl -X POST -H "Authorization: Bearer <TOKEN>" \
  --data-binary @app-release.apk \
  "http://101.37.129.56/upload?name=jumprope-1.0.0.apk"
```

TOKEN 在服务启动日志里，可用环境变量 `UPLOAD_TOKEN` 固定。

---

## 4. 环境约束（重要）

### 必须设置的环境变量

```bash
# Python / MediaPipe
export PYTHONPATH=/root/dsh/test/.pylibs
export LD_LIBRARY_PATH=/root/dsh/test/.syslibs/usr/lib/x86_64-linux-gnu
export MPLCONFIGDIR=/root/dsh/test/.mpl

# Dart（必须设 HOME，否则 analytics 崩溃）
export PATH=/root/dsh/test/.dart/dart-sdk/bin:$PATH
export HOME=/root/dsh/test/.dart-home
export PUB_CACHE=/root/dsh/test/.pub-cache

# npm
export npm_config_cache=/root/dsh/test/.npm-cache
```

`verify_both.sh` 里已经全部设好了。

### 硬限制

| 项 | 数值 | 影响 |
|---|---|---|
| 内存 | 1.6GB（可用 ~460MB） | **无法构建 APK / 跑 Flutter** |
| swap | 不可用（`swapon` 被拒） | 无退路 |
| `/dev/kvm` | 不存在 | **跑不了安卓模拟器** |
| CPU | 2 核 | 构建极慢 |
| 磁盘 | 30GB 可用 | 够 |

**结论：这台机器只做代码托管、算法验证、APK 分发。构建必须上云。**

### 网络与端口

- 安全组放行：**80、8080**
- 被拦：443、8443、3000、6379 等
- 自签证书：`https://101.37.129.56:8080`（浏览器要手动点「高级→继续」）
- 外网可达：github.com、storage.googleapis.com、dl.google.com、mirrors.aliyun.com

### 沙箱

- 可写：`/root/dsh/test` 下任意路径
- 部分系统路径（`/root/.ssh`）可写
- **apt 被拒** → 缺系统库时从 `mirrors.aliyun.com` 下 `.deb`，用 `dpkg-deb -x` 解压到工作区，再设 `LD_LIBRARY_PATH`
- `pip` 必须用 `--target=/root/dsh/test/.pylibs`

---

## 5. 算法现状

**ZigZag 峰值确认**：信号上升时跟踪极大值，从极大值回落超过 `prom` 时确认一个峰。

### 基线（不要退化）

| 视频 | 标注 | 当前 |
|---|---|---|
| 145个断3次 | 145 | **145** |
| 168个断0次 | 168 | 162 |
| 184个断2次 | 184 | 170 |

离线参考检测器（可看未来）上限 151/163/172，当前距离天花板只差 1–2 个。

### 失败的方案（别再试）

| 方案 | 结果 | 死因 |
|---|---|---|
| 固定阈值 + 标定基线 | −44% / −14% / −15% | 偏置一旦超过 3%，漂移修正永不触发 |
| 分位数 + 迟滞状态机 | −18% / −7% / −8% | 复位线太深，信号够不到，靠超时兜底 |

### 关键参数

全在 `counter.mjs` 的 `DEFAULT_CFG`，**不要散落到别处**。

```
AMP_MIN=0.055   PROM_K=0.45   MIN_DT=150ms   SMOOTH=0.60
WIN_SEC=2.00    LAG_SEC=0.333  FAST_SEC=0.7667  X_SEC=1.20
MOVE_X_MAX=0.25  TILT_MAX=35   KNEE_MIN=100
```

**窗口一律按秒计**（曾按帧数，换帧率会改变行为）。

### 帧率无关性（P0 已完成）

窗口按秒计，同一段视频在 12–30fps 采样下计数稳定在 157–162。
原生相机帧间隔不均匀，按帧数计窗口会失真，按秒不会。

---

## 6. 踩过的坑

### 浏览器缓存

**Chrome 不会缓存 5MB 左右的 `.task` 模型文件**，即使响应头是 `immutable`。
每次访问都重新下 4.9MB。

解决：用 **Cache Storage API** 自己存（见 `model-cache.mjs`）。
不要指望 HTTP 缓存。

### 自签证书

- 页面能开，`isSecureContext === true`，`getUserMedia` 可用
- 但**升级到正式必须换真证书**（需要备案域名）
- 下载 APK 走 **80 端口纯 HTTP**，避开证书问题

### MediaPipe Python

- 需要 `libEGL/libGLESv2/libgbm`，系统没有，要从阿里云镜像下 deb
- `mediapipe>=1.0` 移除了 `mp.solutions`，只能用 Tasks API
- 退出时必崩，脚本末尾要 `os._exit(0)`

### Dart

- 首次运行会在 `$HOME` 建配置，沙箱拦了会抛栈**且错误信息看不懂**
- 必须 `export HOME=/root/dsh/test/.dart-home`

### 无头浏览器

Chromium 能跑（LibreOffice 那套依赖补齐了），但 **MediaPipe 用软件渲染，一帧要几秒**，
**不能用来验证性能**，只能验证页面不报错。

### npm

`/root/.npm` 不可写，必须设 `npm_config_cache` 到工作区。

---

## 7. 编码约定

1. **阈值只在 `counter.mjs` / `counter_config.dart`**，别处不许出现魔法数字
2. **计数逻辑两端必须同步**：改了 mjs 就要改 dart，跑 `verify_both.sh` 两边一致才算完
3. **Flutter 的 `domain/` 层禁止 `import 'package:flutter/...'`**（见迁移计划 §5.8）
4. **姿态模型必须同源**：只用 `pose_landmarker_lite.task`，**不要换 ML Kit**，换了阈值全废
5. 单文件 < 300 行

---

## 8. 不要做的事

- ❌ 在本机构建 APK / 装 Flutter（内存不够）
- ❌ 在无头浏览器里验证帧率和性能
- ❌ 换掉 MediaPipe 用 ML Kit
- ❌ 用 `pkill -f "node server.js"`
- ❌ 索要或使用用户的 GitHub 密码（需要时用 Deploy Key 或细粒度 PAT）
- ❌ 把「模型输出一致」当成理所当然 —— 必须用离线 video 模式量化

---

## 9. 验证清单（改完算法必跑）

```bash
cd /root/dsh/test/jumprope
bash test/verify_both.sh /root/dsh/test/video/145个断3次.mp4 145
bash test/verify_both.sh /root/dsh/test/video/168个断0次.mp4 168
bash test/verify_both.sh /root/dsh/test/video/184个断2次.mp4 184
```

三条都要求：`JS == Dart`，且结果接近标注值。

**任何一条不一致，不许合并。**

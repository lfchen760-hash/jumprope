# 跳绳计数 App：Web → Flutter 迁移计划

> 前置文档：[跳绳AI计数产品方案](跳绳AI计数产品方案.md)
> 版本：**v3** · 2026-11-08
>
> v2 补充：离线 video 调试模式、模型差异量化、Dart 核心落地
> **v3 补充：仅做 Android；新增工程架构设计（§5）**

---

## 1. 目标与原则

### 1.1 平台范围

```
✅ Android（本期唯一目标）
❌ iOS（本期不做，架构上预留，不写 iOS 代码）
```

**理由**：先把一条链路做扎实，验证模型差异和阈值可移植性。iOS 的 MediaPipe SDK 接口类似，将来补的成本远低于现在同时做两端的风险。

### 1.2 分工

```
Web 版  =  算法实验台（长期保留）
Flutter =  产品形态（Android）
```

### 1.3 三条铁律

| # | 原则 | 原因 |
|---|---|---|
| 1 | 计数逻辑只有一份真理 | 两端任一改动，另一端的测试必须同时通过 |
| 2 | 姿态模型必须同源 | 换模型 = 换信号，阈值全部作废 |
| 3 | 窗口按时间，不按帧数 | 帧率不同设备不同，按帧算等于换算法 |

### 1.4 架构铁律

| # | 原则 |
|---|---|
| 4 | **domain 层零 Flutter 依赖**，可在无模拟器环境单测 |
| 5 | **数据源可替换**：相机 / 视频文件 / 日志回放，同一接口 |
| 6 | **配置集中**：所有阈值只在一个文件里，禁止散落魔法数字 |

---

## 2. 现状盘点

### 2.1 已有资产

| 资产 | 位置 | 状态 |
|---|---|---|
| 计数核心（ZigZag 峰值确认） | `jumprope/public/counter.mjs` | ✅ |
| **计数核心 Dart 移植版** | `dart_core/lib/counter.dart` | ✅ 已验证一致 |
| **Dart 验证器** | `dart_core/verify.dart` | ✅ |
| 姿态判定 | `jumprope/public/posture.mjs` | ✅ |
| 姿态模型 | `pose_landmarker_lite.task` (5.6MB) | ✅ |
| 黄金测试向量 | `jumprope/test/golden/*.json` | ✅ 3 段 × 1800 帧 |
| **视频一键双端验证** | `jumprope/test/verify_both.sh` | ✅ 34 秒/视频 |
| 可视化分析页 | `/analyze.html` | ✅ |
| APK 上传/下载通道 | `/upload`、`/download/` | ✅ 实测可用 |
| Dart SDK（服务器内） | `/root/dsh/test/.dart` | ✅ 3.13.7 |

### 2.2 当前基线

| 视频 | 标注 | JS | Dart | 误差 |
|---|---|---|---|---|
| 145个断3次 | 145 | **145** | 145 | **0.0%** |
| 168个断0次 | 168 | 162 | 162 | −3.6% |
| 184个断2次 | 184 | 170 | 170 | −7.6% |

离线参考检测器上限：151 / 163 / 172。当前距离信号天花板只差 1–2 个。

### 2.3 关键参数

```
MIN_DT 150ms · SMOOTH 0.60 · BASE_ALPHA 0.06 · AMP_MIN 0.055
PROM_K 0.45 · WIN 60 · LAG 10 · FAST_WIN 24
MOVE_X_MAX 0.25 · TILT_MAX 35° · KNEE_MIN 100°
```

---

## 3. 三层一致性策略

### 3.1 策略层 —— 已证明可 100% 一致

```
JS   145 / 162 / 170
Dart 145 / 162 / 170   ✅ 完全相同
```

### 3.2 模型层 —— 必须同源，且需量化验证

| 方案 | 一致性 | 结论 |
|---|---|---|
| **MediaPipe Tasks（同一个 .task）** | 高 | ✅ 采用 |
| ML Kit Pose Detection | 低（另一套模型） | ❌ 阈值需全部重标 |

即使同源，Web(WASM) 与 Android(GPU delegate) 的关键点仍有微小差异，**必须测量**（见 §7.3）。

### 3.3 采样层 —— 用时间窗口规避

| 项 | Web | Android | 手段 |
|---|---|---|---|
| 帧率 | 22–25 fps | 25–30 fps | 窗口按秒 |
| 分辨率 | 640 长边 | 640 长边 | 统一 |

P0 改造：`WIN/LAG/FAST_WIN/X_WIN` → 秒。

---

## 4. 离线 video 模式

### 4.1 为什么不用"录相机"，用"离线视频"

| | 录相机 | 离线 video |
|---|---|---|
| 输入确定性 | 每次不同 | **同一 mp4 永远同批帧** |
| 可复现 | 难 | **100%** |
| 需要孩子 | 需要 | **不需要** |
| 与 Web 对比 | 无法 | **可逐点对比** |

### 4.2 流程

```
选择视频 → 按原生 fps 解码 → 逐帧喂 MediaPipe（同一个 .task）
   → 33 关键点序列 → ┬→ counter.dart 计数
                      ├→ 导出关键点日志
                      └→ 时间轴可视化
```

**时间基准必须是「帧序号 ÷ 视频 fps」**，用系统时钟会导致每次结果不同。

### 4.3 导出格式

```jsonc
{
  "video": "168个断0次.mp4",
  "fps": 30.0, "frames": 1823,
  "modelMd5": "a1b2c3...",
  "count": 162,
  "samples": [{ "t": 33, "lm": [[x,y,z,vis] × 33] }]
}
```

**必须导原始 33 点**，派生特征服务端可随时重算，反过来不行。

### 4.4 实现要点

| 环节 | 方案 |
|---|---|
| 视频解码 | `ffmpeg_kit_flutter_android` |
| 备选 | `MediaCodec` + `ImageReader` |

三个坑：旋转元数据、YUV→RGB 色域、可变帧率 PTS。

### 4.5 只在 debug 版启用

入口：设置页长按版本号。正式版编译期剔除。

---

## 5. 工程架构

> 目标：**任何一个文件都只干一件事，新增功能不改已有代码。**

### 5.1 分层

```
┌─────────────────────────────────────────────┐
│  presentation    UI / 状态管理               │  Flutter 依赖
├─────────────────────────────────────────────┤
│  domain          计数、姿态、实体、接口        │  纯 Dart，零 Flutter 依赖
├─────────────────────────────────────────────┤
│  data            相���、视频、模型桥、存储      │  平台相关实现
└─────────────────────────────────────────────┘

依赖方向：presentation → domain ← data
```

**关键约束**：`domain/` 目录下**不允许**出现 `import 'package:flutter/...'`。
这样它能在服务器上用 `dart test` 跑，不需要模拟器。

### 5.2 目录结构

```
app/
├── lib/
│   ├── main.dart                       # 入口，只做初始化
│   ├── app.dart                        # MaterialApp、路由、主题
│   ├── di.dart                         # 依赖装配（一个地方改实现）
│   │
│   ├── domain/                         # ★ 纯 Dart
│   │   ├── entities/
│   │   │   ├── landmark.dart           # 33 点数据结构
│   │   │   ├── pose_frame.dart         # 一帧：t + landmarks
│   │   │   ├── pose_sample.dart        # 派生特征：hipY/torso/hipX/tilt/knee
│   │   │   ├── framing.dart            # 取景判定结果
│   │   │   └── session_state.dart      # 会话状态
│   │   ├── counter/
│   │   │   ├── counter.dart            # 计数核心（从 dart_core 搬入）
│   │   │   └── counter_config.dart     # ★ 所有阈值集中在这
│   │   ├── posture/
│   │   │   └── posture.dart            # 姿态判定（移植 posture.mjs）
│   │   ├── session/
│   │   │   └── session_controller.dart # 编排：帧→特征→计数→状态
│   │   └── ports/                      # 抽象接口（依赖倒置）
│   │       ├── pose_source.dart
│   │       └── landmarker.dart
│   │
│   ├── data/
│   │   ├── pose/
│   │   │   ├── camera_pose_source.dart     # Android 相机
│   │   │   ├── video_pose_source.dart      # 离线视频（debug）
│   │   │   ├── replay_pose_source.dart     # 日志回放（测试）
│   │   │   └── mediapipe_landmarker.dart   # Platform Channel 封装
│   │   ├── decode/
│   │   │   └── video_decoder.dart          # ffmpeg 解码
│   │   └── storage/
│   │       └── golden_writer.dart          # 导出关键点日志
│   │
│   └── presentation/
│       ├── pages/          # home / framing / counting / result / settings
│       ├── widgets/        # skeleton_painter, count_display, wave_view
│       └── state/          # session_provider
│
├── android/
│   └── app/src/main/kotlin/.../
│       ├── PosePlugin.kt               # FlutterPlugin 注册
│       ├── PoseProcessor.kt            # MediaPipe Tasks 调用
│       └── CameraStreamHandler.kt      # CameraX → YUV
│
└── test/
    ├── unit/               # counter_test, posture_test
    ├── golden/             # *.json 向量（与 Web 共用）
    └── integration/        # replay_pose_source_test
```

### 5.3 核心抽象：PoseSource

**整个架构的关键设计。** 三种数据源，同一个接口：

```dart
/// 姿态数据源：相机 / 视频文件 / 日志回放，三者可互换
abstract class PoseSource {
  /// 帧流，t 为单调递增毫秒
  Stream<PoseFrame> get frames;

  Future<void> start();
  Future<void> stop();
  Future<void> dispose();

  SourceKind get kind;   // camera | videoFile | replay
}
```

三种实现：

| 实现 | 用途 | 输入 |
|---|---|---|
| `CameraPoseSource` | 正式使用 | CameraX 实时帧 |
| `VideoPoseSource` | 离线调试 | mp4 解码 |
| `ReplayPoseSource` | 单元测试 / 复现 | JSON 日志 |

**收益**：`SessionController` 完全不知道数据从哪来，调试模式和正式模式走**同一条代码路径**。

### 5.4 会话控制器

```dart
class SessionController {
  SessionController({
    required PoseSource source,
    required Counter counter,
    required SessionConfig config,
  });

  Stream<SessionState> get state;
  Future<void> start();
  void pause();
  void resume();
  Future<void> stop();
}
```

内部职责：

```
PoseFrame → PoseSample（派生 hipY/torso/hipX/tilt/knee）
          → Counter.feed(..., ctx)
          → SessionState（计数、剩余时间、闸门状态）
```

**只做编排，不做计算。** 所有数学都在 `domain/counter` 和 `domain/posture`。

### 5.5 平台桥（只管搬数据）

```dart
abstract class Landmarker {
  Future<void> init({required String modelPath, int numPoses = 1});

  /// 送一帧，返回 33 个点；无人时返回 null
  Future<List<Landmark>?> processFrame({
    required Uint8List bytes,
    required int width,
    required int height,
    required int timestampMs,
  });

  Future<void> dispose();
}
```

Android 实现调用 `com.google.mediapipe:tasks-vision`。
**这一层绝不做任何业务判断**——不算角度、不算计数、不判断取景。

### 5.6 配置集中

`domain/counter/counter_config.dart` 是**唯一**的阈值来源：

```dart
class CounterConfig {
  static const minDt = 150;
  static const smooth = 0.60;
  static const ampMin = 0.055;
  // ...
}
```

任何文件里出现 `0.055` 这种魔法数字都算错。

### 5.7 状态管理

推荐 **Riverpod**：

```dart
final sessionProvider = StateNotifierProvider<SessionController, SessionState>(...);
```

理由：`domain` 层不依赖它，只在 `presentation` 用；测试时可轻松替换。

### 5.8 边界规则（写进 CI）

| 规则 | 检查方式 |
|---|---|
| `domain/` 不得 import flutter | 自定义 lint / grep 脚本 |
| `data/` 不得 import presentation | 同上 |
| 不得出现裸数字阈值 | code review + grep |
| 每个文件 < 300 行 | 脚本检查 |

### 5.9 测试结构

```
test/unit/          counter_test.dart      —— 跑黄金向量
                    posture_test.dart
test/integration/   replay_source_test.dart —— 用 JSON 回放走完整控制器
test/widget/        关键页面渲染
```

**约 90% 的测试不需要模拟器**，这是分层最大的收益。

### 5.10 为什么这样分

| 未来需求 | 改动范围 |
|---|---|
| 调阈值 | 只改 `counter_config.dart` |
| 加离线视频模式 | 新增 `video_pose_source.dart`，不动其他 |
| 换姿态模型 | 只改 `mediapipe_landmarker.dart` |
| 加 iOS | 新增 iOS 桥，domain 不变 |
| 加排行榜 | 新增 data 层，domain 不变 |
| 修计数 bug | 只改 `counter.dart` + 跑测试 |

---

## 6. 阶段划分

### P0 · 一致性基建（3–5 天）— ⬜

| 任务 | 验收 |
|---|---|
| 窗口改按时间 | 三个视频仍为 145/162/170 |
| 扩充黄金向量到 5–8 段 | 覆盖暗光、远距离、大人跳 |
| 冻结模型版本（记录 MD5） | 两端同一文件 |

### P1 · Dart 核心（1 周）— 🟡 70%

| 任务 | 状态 |
|---|---|
| 移植 `counter.dart` | ✅ |
| 移植 `posture.dart` | ⬜ |
| 黄金向量验证脚本 | ✅ |
| `package:test` 单元测试 | ⬜ |
| 按时间窗口改造 | ⬜ 依赖 P0 |

### P2 · Android 原生桥 + 离线 video（2 周）

| 任务 |
|---|
| `PosePlugin.kt`：FlutterPlugin 注册与通道 |
| `PoseProcessor.kt`：MediaPipe Tasks 推理 |
| `CameraStreamHandler.kt`：CameraX → YUV → RGB |
| `CameraPoseSource` / `VideoPoseSource` / `ReplayPoseSource` |
| 离线 video 模式 + 关键点日志导出 |

**验收（全部满足才能进 P3）**：

- [ ] 真机跑 `168个断0次.mp4`，导出关键点日志
- [ ] 手机计数 = Web 计数 = 162
- [ ] 与服务器 Python 提取逐点偏差 **95 分位 < 0.01**
- [ ] 实时 fps ≥ 25
- [ ] `dart analyze` 无问题，unit + integration 测试全绿

> 偏差超阈值 → **立即停止**，先解决模型差异。

### P3 · Flutter UI（1.5 周）

| 页面 | 内容 |
|---|---|
| 首页 | 时长选择、开始 |
| 取景页 | 骨架、取景提示、语音引导、3-2-1 倒数 |
| 计数页 | 大数字、倒计时、波形、暂停 |
| 结果页 | 次数、频率、分享 |
| 设置页 | 语音模式、音效、灵敏度（暴露 AMP_MIN 三档） |

### P4 · 打包分发（3 天）

| 任务 |
|---|
| 签名 keystore（备份两份） |
| CI 构建（GitHub Actions / 阿里云效） |
| 上传 `/upload`，下载页 `/download/` |

---

## 7. 验证流水线

### 7.1 四层

| 层 | 内容 | 状态 |
|---|---|---|
| **L0 模型层** | 手机关键点 vs 服务器关键点 | ⬜ P2 |
| **L1 计数层** | JS vs Dart | ✅ |
| **L2 端到端** | 视频 → 计数 | ✅ |
| **L3 真机** | 手机 → 计数 | ⬜ P2 |

### 7.2 L1 + L2（现在就能跑）

```bash
bash test/verify_both.sh 视频.mp4 168
```

```
  视频      168个断0次.mp4
  标注      168
  JS 计数   162
  Dart 计数 162
  一致性    ✅ 完全相同
```

### 7.3 L0 模型差异量化（P2）

```bash
python3 test/extract.py 168个断0次.mp4 /tmp/lm_server.json
node test/compare_landmarks.mjs /tmp/lm_server.json 手机导出.json
```

判定：

| 95 分位偏差 | 结论 |
|---|---|
| < 0.01 | 阈值直接复用 |
| 0.01–0.03 | 微调 AMP_MIN 后重跑 |
| > 0.03 | 停止，检查解码/旋转/色域 |

### 7.4 变更流程

```
改算法 → verify_both.sh 三视频（JS==Dart）
      → 重新生成黄金向量
      → 真机离线模式（计数一致）
      → 全部通过才合并
```

---

## 8. 数据契约

```jsonc
{
  "t": 12345, "hipY": 0.5321, "torso": 0.1764,
  "hipX": 0.5012, "tilt": 3.2, "kneeL": 176.4, "kneeR": 178.1
}
```

输出：`true` = 本帧确认了一个新峰。

> ZigZag 是确认式计数，计数发生在峰值**之后**的回落时刻。

---

## 9. 构建与分发

### 9.1 本机限制

| 项 | 数值 |
|---|---|
| 内存 | 1.6GB（可用 ~460MB） |
| Android 构建峰值 | 3–4GB |
| swap | ❌ 不可用 |
| KVM | ❌ 无 |

**本机只做：代码托管、算法验证、APK 分发。**

### 9.2 CI

| 方案 | 费用 |
|---|---|
| GitHub Actions（公开仓库） | 免费无限 |
| GitHub Actions（私有） | 2000 分钟/月 |
| 阿里云效 | 个人版有免费额度 |

### 9.3 分发（已就绪）

```bash
curl -X POST -H "Authorization: Bearer <TOKEN>" \
  --data-binary @app-release.apk \
  "http://101.37.129.56/upload?name=jumprope-1.0.0.apk"
```

下载：`http://101.37.129.56/download/`（纯 HTTP，无证书问题）

---

## 10. 风险与对策

| 风险 | 影响 | 对策 |
|---|---|---|
| 双端算法漂移 | 高 | 黄金向量 CI 卡口 |
| 手机模型与 Web 不同 | **高** | P2 离线量化，超阈值止损 |
| 视频解码旋转/色域错 | 高 | 用已知视频先验证解码正确性 |
| 帧率差异 | 中 | P0 时间窗口 |
| 架构腐化 | 中 | §5.8 边界规则进 CI |
| 本机无法构建 | 已确认 | 云端 CI |
| 签名丢失 | 致命 | keystore 备份 2 份 |
| 阈值不适用某些孩子 | 中 | 设置页"灵敏度"三档 |

---

## 11. 验收标准

### 算法
- [ ] JS / Dart 输出完全相等（已达成）
- [ ] 三视频 145 / 162 / 170（已达成）
- [ ] 手机离线模式计数 = Web 计数
- [ ] 关键点偏差 95 分位 < 0.01

### 性能
- [ ] 中端安卓 ≥ 25fps
- [ ] 跳→报数 < 300ms
- [ ] 连续 10 分钟稳定

### 准确率
- [ ] 30 秒 100 次，误差 ≤ 2
- [ ] 停跳后误计 ≤ 1
- [ ] 调整期间误计 ≤ 2

### 工程
- [ ] `domain/` 无 Flutter 依赖
- [ ] `dart analyze` 无问题
- [ ] 单文件 < 300 行
- [ ] 无散落魔法数字

---

## 12. 时间表

| 阶段 | 工期 | 状态 | 累计 |
|---|---|---|---|
| P0 一致性基建 | 3–5 天 | ⬜ | 5 天 |
| P1 Dart 核心 | 1 周 | 🟡 70% | 12 天 |
| P2 Android 原生桥 + 离线 video | **2 周** | ⬜ | 26 天 |
| P3 Flutter UI | 1.5 周 | ⬜ | 37 天 |
| P4 打包分发 | 3 天 | ⬜ | **40 天** |

**约 5.5 周**（只做安卓，比 v2 少 1 周）。

---

## 13. 明确不做

- ❌ iOS（架构预留，不写代码）
- ❌ 多人同屏计数
- ❌ 动作质量分析
- ❌ 云端账号与排行榜
- ❌ 智能跳绳硬件
- ❌ 正式版开放离线 video 模式（仅 debug）

---

## 14. 下一步

1. **P0**：窗口改按时间（`counter.mjs` + `counter.dart` 同步）
2. **P1 收尾**：`posture.dart` + `package:test`
3. **P2 第一件事**：`PosePlugin.kt` + `ReplayPoseSource`（先跑通日志回放，再接相机）

P0 验收：

```bash
bash test/verify_both.sh /root/dsh/test/video/145个断3次.mp4 145
bash test/verify_both.sh /root/dsh/test/video/168个断0次.mp4 168
bash test/verify_both.sh /root/dsh/test/video/184个断2次.mp4 184
```

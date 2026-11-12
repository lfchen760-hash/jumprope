# AGENTS.md

给接手的 agent（或未来的自己）看的操作手册。
**只写「不看就会踩坑」的东西**，不写代码细节。

最后更新：2026-11-12

---

## 1. 这是什么

儿童跳绳 AI 计数项目。摄像头识别姿态 → 数跳绳次数。

```
Web 版（H5）  = 算法实验台，长期保留，调参主战场
Flutter 版    = 最终产品，仅 Android
```

当前阶段：**数据层 v1 + 正式 UI v0 + 成长日历 v1**（首页/结果/记录/我的，
记录页日/周/月/年切换）。算法验证继续；出框暂停、音效开关还没做。
签名已固定为公开 dev key，CI 构建可覆盖升级；正式发布前要换私有 release key。

文档：
- `docs/跳绳AI计数产品方案.md` —— 产品与技术方案
- `docs/Flutter迁移计划.md` —— 迁移计划 v3
- `docs/项目进展.md` —— 当前进度/下一步
- `design/storage-schema.md`、`design/data-logic.md` —— 数据要存什么、每个数字怎么算

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
├── dart_core/                   Dart 核心（无 Flutter 依赖，可本机验证）
│   ├── lib/counter.dart         ★ counter.mjs 的移植
│   ├── lib/posture.dart         姿态判定
│   ├── lib/pose_source.dart     数据源抽象（相机/视频/回放）
│   ├── lib/replay_pose_source.dart  日志回放
│   ├── lib/session_controller.dart  会话编排
│   ├── lib/session_result.dart  会话结果（jumps/activeMs/valid）
│   ├── verify.dart              跑黄金向量验证
│   └── test/all_tests.dart      ★ 全部单元测试（51 项）
│
├── flutter_app/                 Flutter 外壳
│   ├── lib/main.dart            入口（正式 App / CAMERA_TEST）
│   ├── lib/live_page.dart       计数页（按 mock-live：计时/大数字/进度/暂停）
│   ├── lib/tick_player.dart     每跳音效通道（原生 SoundPool）
│   ├── lib/app/                 ★ 正式 UI（首页/结果/记录/我的）
│   │   ├── home_page.dart       首页（目标环 + 开始）
│   │   ├── result_page.dart     结果页（表盘/统计/节奏）
│   │   ├── history_page.dart    记录页（日/周/月/年 + 汇总 + 明细）
│   │   ├── history/            ★ 日历组件（月历/周条/年柱/汇总/最佳）
│   │   ├── profile_page.dart    我的（展示 + 编辑入口）
│   │   ├── profile_form_page.dart 首启引导 / 档案表单
│   │   └── theme.dart / ui.dart 设计稿色板与通用组件
│   ├── lib/data/                ★ 本地数据层（SQLite v1）
│   │   ├── app_database.dart    建表/迁移/DAO
│   │   ├── data_repository.dart 门面 + 导入导出
│   │   ├── session_record.dart  会话（逐跳时间戳）
│   │   ├── session_saver.dart   结束后自动落库
│   │   ├── child_profile.dart   孩子档案
│   │   ├── jump_benchmark.dart  2014 国标阈值表
│   │   ├── period_stats.dart    日/周/月/年统计
│   │   └── period.dart          周期区间/月历格子/环比（纯逻辑）
│   ├── test/data_layer_test.dart 数据层纯逻辑测试
│   ├── test/period_test.dart    周期/月历/环比测试
│   ├── lib/data/pose/           通道封装 + 两个 PoseSource
│   └── android/.../com/jumprope/  PosePlugin / PoseProcessor / CameraStream
│       android/.../res/raw/      tick_low.wav / tick_high.wav
│
├── ci/android/                  DEV 签名（公开，见 §5.5）
├── design/                      UI 稿、数据口径、存储 schema
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

# 只跑 Dart 计数
cd /root/dsh/test/dart_core
dart run verify.dart ../jumprope/test/golden

# Dart 全部单元测试（计数 + 姿态 + 回放 + 会话，无第三方依赖）
cd /root/dsh/test/dart_core
dart run test/all_tests.dart
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

APK 构建完成后从 `apk` 分支同步到下载页：

```bash
cd jumprope && node sync-apk.mjs --once
```

脚本默认使用仓库的 Deploy Key；会更新 `jumprope.apk` 并留一份
`jumprope-<build>.apk` 版本副本。

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

## 5.5 数据层与签名（v1）

### 数据层（`flutter_app/lib/data/`）

- SQLite 库 `jumprope.db`，`schemaVersion = 1`；表：`profile` / `sessions` /
  `goal_history` / `settings`。
- **只存事实**：档案、每次会话（含 `jumps_json` 逐跳 offset）、目标历史、设置。
- **不存派生**：日/周/月/年总数、连续天数、个人最好、参考线状态、日历颜色，
  全部从会话算；避免两套数字打架。
- 会话存 `grade_at_session` / `gender_at_session` / `standard_version` 快照；
  2014 国标阈值表在 `jump_benchmark.dart`，不按用户复制。
- 迁移：`PRAGMA user_version`；只加不删；迁移前备份 `.bak-vN`；不要
  `DROP TABLE` / 删库重建。当前 v1，还没有 v2。
- 导入/导出：`ExportBundle`（JSON，含 schemaVersion）；导入前先导出一份
  backup；整体替换用 `replace: true`。
- 数据层测试：`flutter_app/test/data_layer_test.dart`（纯逻辑，不碰 sqflite）。
  CI 会跑 `flutter test`。
- 会话结束（`finished`）时 `SessionSaver` 自动写一条 `SessionRecord`：
  `SessionResult` → `SessionRecord.fromResult` → `DataRepository.saveSession`。
  只写一次；0 跳会话也存，但 `valid=false`（`no_jumps`），不进统计。

### 签名（DEV ONLY，已落地）

- `ci/android/dev-upload-keystore.p12` + `dev-keystore.properties` 提交在仓库里，
  **密码也是公开的**。这是为了不改 GitHub Secrets、保证 CI 每次同一证书。
- 证书 SHA-256：
  `F2:5A:84:D5:38:58:4A:F8:A1:9F:48:46:C1:69:CD:6E:54:9F:70:E3:A7:20:7C:C4:E5:04:0F:12:EA:36:67:A4`
- CI 构建后 `apksigner` 校验该指纹；不一致直接失败。
- `versionCode` 用 `github.run_number` 自增；`applicationId` 是
  `com.jumprope.jumprope_app`，**不要改**，改了就是另一个 App，数据不继承。
- 旧 debug 包（每次证书不同）需要卸载一次；从 dev key 这版起可以覆盖升级。
- 正式发布前换私有 release key（届时老用户需卸载一次）；不要把 release key
  提交到公开仓库。

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

### postureOf 的入参格式（踩过）

`postureOf` 要的是 `{x, y, visibility}` **对象**，而原始关键点 JSON 存的是
`[x, y, z, vis]` **数组**。

直接传数组不会报错，会静默取出 `undefined` → 全部走 NaN 兜底 →
`tilt=0, kneeL=180`，**弯腰闸门永远不触发，测试却"通过"**。

离线脚本里必须先转换：

```js
const toLm = (arr) => arr.map(([x, y, z, v]) => ({ x, y, z, visibility: v }));
const post = postureOf(toLm(lm));
```

判断有没有踩：抽查黄金向量里 `tilt` 是否全为 0。全 0 就是踩了。

### release 构建会压掉「动态引用」的 res/raw

音效资源一开始用 `resources.getIdentifier("tick_low","raw",packageName)` 加载，
release 构建的资源压缩不认这种动态引用，**wav 直接被删掉，APK 里只剩代码**，
表现就是「计数正常但完全没声音」。

解决：Kotlin 里写静态引用 `R.raw.tick_low`（可再加 `res/raw/keep.xml` 的
`tools:keep`）。验证方式：

```bash
unzip -l app-release.apk | grep wav   # 必须能看到 res/*.wav
```

改完音效务必解包确认，不要只看「编译通过」。

### Flutter 3.47 把 material.dart 标记为 deprecated

CI 用 `channel: stable`，Flutter 3.47 起 `package:flutter/material.dart`
会报 28 条 `deprecated_member_use` info，`flutter analyze` 直接非零退出，
和代码本身无关。已用 `flutter_app/analysis_options.yaml` 忽略这条诊断；
迁移到 `material_ui` 是独立任务，不要顺手改 import。

### Android release lint 在 camerax 上崩

构建报 `lintVitalAnalyzeRelease`，栈里是
`CommentDetector` → `NoSuchMethodError`（AGP/lint 自身 bug），跟 Dart 代码无关。
`prepare_android.sh` 里已对 app 和子工程关掉 `lintVital`；
#65/#66 已验证可以正常出 APK。再遇到类似“release 打包卡在插件 lint”，
先查这里，不要改相机代码。

### dart pub get 用不了

```
Rename failed ... Invalid cross-device link (errno 18)
```

沙箱限制 pub 缓存的 rename，**带依赖的包一律装不上**（包括 `package:test`）。

所以 `dart_core` 保持零依赖，测试用 `test/all_tests.dart`（纯 Dart 断言 + 退出码）。

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
- ❌ 把视频/原始帧/逐帧关键点写进数据库（隐私 + 体积）
- ❌ 在数据库里存日/周/月总数、连续天数等派生值（读时算）
- ❌ 随手改 `applicationId` 或签名 key（会丢数据/无法升级）
- ❌ 正式发布继续用公开 dev key；也不要提交私有 release key

---

## 9. GitHub

### 仓库

```
https://github.com/lfchen760-hash/jumprope
主分支: main
本地推送副本: /root/dsh/test/repo
```

### 认证：Deploy Key（不是 PAT，更不是密码）

| 项 | 值 |
|---|---|
| 私钥 | `/root/dsh/test/.ssh/deploy_key`（只在本机） |
| 公钥指纹 | `SHA256:3i/YNrkATvDn6vOHN1SCuIDDHDtGDLI9wVaAI8Tdc7M` |
| 权限 | 该仓库的 Deploy key + Allow write access |

能力边界：**只能读写 `jumprope` 一个仓库**；删不了仓库，看不到其他仓库，改不了账号设置。

### 推送

```bash
cd /root/dsh/test/repo
export GIT_SSH_COMMAND="ssh -i /root/dsh/test/.ssh/deploy_key \
  -o UserKnownHostsFile=/root/dsh/test/.ssh/known_hosts \
  -o IdentitiesOnly=yes"
git push
```

连通性自检：

```bash
ssh -i /root/dsh/test/.ssh/deploy_key -o IdentitiesOnly=yes -T git@github.com
# 期望输出: Hi lfchen760-hash/jumprope! You've successfully authenticated...
```

### 同步流程

源码在工作区，`repo/` 只是推送用的副本。改完代码要 rsync 过去：

```bash
cd /root/dsh/test/repo
rsync -a --exclude node_modules --exclude '.git' --exclude '*.log' --exclude '*.png' \
  --exclude 'public/models' --exclude 'public/wasm' --exclude 'public/download' --exclude 'certs' \
  /root/dsh/test/jumprope/ ./jumprope/
rsync -a --exclude '.dart_tool' --exclude '.packages' --exclude 'pubspec.lock' \
  /root/dsh/test/dart_core/ ./dart_core/
rsync -a --exclude 'build' --exclude '.dart_tool' --exclude 'pubspec.lock' \
  /root/dsh/test/flutter_app/ ./flutter_app/
cp /root/dsh/test/AGENTS.md .
cp /root/dsh/test/docs/*.md ./docs/
git add -A && git commit -m "..." && git push
```

> 注意：`repo/jumprope/` 会残留源目录里的临时脚本，提交前用 `git status` 检查一遍。

### 绝不入库

| 路径 | 原因 |
|---|---|
| `jumprope/certs/` | **私钥** |
| `public/models/*.task` | 5.6MB 二进制 |
| `public/wasm/*.wasm` | 9MB 二进制 |
| `public/download/` | 构建产物 |
| `.pylibs/ .syslibs/ .dart/ .npm-cache/` | 本地依赖 |

已在 `.gitignore` 里。模型由页面首次运行时自动下载。

### 安全约定

- **永远不要索要或使用用户的 GitHub 密码**
- 用户曾把密码贴在截图里，已提醒修改 + 开 2FA
- 需要写权限时：Deploy Key（单仓库）> 细粒度 PAT（7 天 + 单仓库）
- 拿到 token 后**不要写进文件、不要写进 git config**，用完即弃

### CI（已配置）

| 工作流 | 触发 | 内容 |
|---|---|---|
| `.github/workflows/ci.yml` | push / PR | Dart 核心测试 + Flutter analyze + 数据层 `flutter test`（ignore `deprecated_member_use`） |
| `.github/workflows/android-build.yml` | push（flutter/.github 变更）/ 手动 | 生成脚手架 → 固定 DEV 签名 → 校验证书 → 构建 APK |

**本地等价命令**（CI 会跑同样的东西）：

```bash
cd dart_core && dart analyze && dart run test/all_tests.dart
cd flutter_app && flutter pub get && flutter analyze && flutter test
```

**android-build 的已知风险**：`flutter create` 模板随版本变化，
补丁逻辑全在 `.github/scripts/prepare_android.sh`，首次构建失败基本改那里。
本机无 Android SDK，无法离线验证，只能靠 CI 日志迭代。

产物上传接口（已就绪）：

```bash
curl -X POST -H "Authorization: Bearer <TOKEN>" \
  --data-binary @app-release.apk \
  "http://101.37.129.56/upload?name=jumprope-1.0.0.apk"
```

下载页：`http://101.37.129.56/download/`

---

## 10. 验证清单（改完算法必跑）

```bash
cd /root/dsh/test/jumprope
bash test/verify_both.sh /root/dsh/test/video/145个断3次.mp4 145
bash test/verify_both.sh /root/dsh/test/video/168个断0次.mp4 168
bash test/verify_both.sh /root/dsh/test/video/184个断2次.mp4 184
```

三条都要求：`JS == Dart`，且结果接近标注值。

**任何一条不一致，不许合并。**

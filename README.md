# 跳绳 AI 计数

摄像头识别姿态 → 自动数跳绳次数。Web 版作为算法实验台，Flutter 版（仅 Android）为最终产品。

## 当前状态

算法验证阶段。三个校准视频的准确率：145/145、162/168、170/184。

## 目录

```
jumprope/     Web 版（算法实验台）
  public/counter.mjs     计数核心（唯一真理）
  public/posture.mjs     姿态判定
  test/verify_both.sh    一条命令验证 JS + Dart
  test/golden/           黄金测试向量

dart_core/    Dart 计数核心（无 Flutter 依赖）
  lib/counter.dart       counter.mjs 的移植
  verify.dart            跑黄金向量验证

docs/         产品方案 + 迁移计划
AGENTS.md     操作手册（环境、坑、验证流程）
```

## 快速开始

```bash
cd jumprope
npm install          # 安装 MediaPipe 依赖
node server.js       # HTTPS 8080 / HTTP 80
```

浏览器打开 `https://localhost:8080`（自签证书需手动信任）。

## 验证算法

```bash
bash jumprope/test/verify_both.sh 视频.mp4 168
```

要求 JS 计数与 Dart 计数完全一致。

## 文档

- [产品与技术方案](docs/跳绳AI计数产品方案.md)
- [Flutter 迁移计划](docs/Flutter迁移计划.md)
- [AGENTS.md](AGENTS.md)

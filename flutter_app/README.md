# jumprope_app（Flutter / Android）

## 这个目录是什么

P2 阶段的**代码骨架**。核心逻辑在 `../dart_core`（纯 Dart，可在无 Flutter 环境验证），
这里只放平台相关部分。

> ⚠️ 当前机器无法运行 Flutter（内存 1.6GB、无 KVM），所以这里的代码**尚未编译验证**。
> 编译交给 CI（见仓库根目录 `AGENTS.md`）。

## 目录

```
lib/
  data/pose/
    mediapipe_landmarker.dart   通道封装（只做协议转换）
    camera_pose_source.dart     相机数据源
    video_pose_source.dart      离线视频数据源（调试）
android/app/src/main/kotlin/com/jumprope/
  PosePlugin.kt                 通道注册 + 生命周期
  PoseProcessor.kt              MediaPipe 推理
  CameraStreamHandler.kt        CameraX 取帧
```

## 接入步骤

1. 在有 Flutter 的机器上生成脚手架：

```bash
flutter create --org com.jumprope --platforms=android . 
```

2. 用本目录的 `lib/`、`android/app/src/main/kotlin/` 覆盖生成的同名目录。

3. 把模型放进资源：

```bash
mkdir -p assets
cp ../jumprope/public/models/pose_landmarker_lite.task assets/
```

4. 添加依赖（`android/app/build.gradle`）：

```gradle
dependencies {
    implementation("com.google.mediapipe:tasks-vision:0.10.14")
    implementation("androidx.camera:camera-core:1.3.4")
    implementation("androidx.camera:camera-camera2:1.3.4")
    implementation("androidx.camera:camera-lifecycle:1.3.4")
}
```

5. Manifest 权限与最低版本：

```xml
<uses-permission android:name="android.permission.CAMERA" />
<uses-permission android:name="android.permission.READ_MEDIA_VIDEO" />
```

```gradle
android { defaultConfig { minSdk 24 } }
```

6. 注册插件（`MainActivity.kt`）：

```kotlin
class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        flutterEngine.plugins.add(PosePlugin())
    }
}
```

## 通道协议

```
MethodChannel  com.jumprope/pose
  init(modelAsset, useGpu) -> Boolean
  startCamera(front)       -> Boolean
  stopCamera()
  processVideo(path, fps)  -> Boolean
  stopVideo()
  dispose()

EventChannel   com.jumprope/pose_frames
  { "t": Int(ms), "lm": List<Double>? }   // 33*4，无人时 null
```

## 待办（P3）

- `lib/presentation/` 页面与状态管理
- `SessionController` 接 `XxxPoseSource`
- 语音报数（flutter_tts）

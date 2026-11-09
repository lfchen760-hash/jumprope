/// 构建标识，CI 用 --dart-define=BUILD_ID=xxxx 注入。
const String kBuildId = String.fromEnvironment('BUILD_ID', defaultValue: 'dev');

/// 相机最小验证模式：只需 --dart-define=CAMERA_TEST=true。
const bool kCameraTest = bool.fromEnvironment('CAMERA_TEST');

#!/usr/bin/env bash
# 把 flutter create 生成的工程改造成能编译本项目的样子。
# 这里集中了所有"模板差异"，第一次构建失败基本都改这个文件。
set -euo pipefail

APP_DIR="${1:-ci_app}"
MAIN_KT="$APP_DIR/android/app/src/main/kotlin/com/jumprope/jumprope_app/MainActivity.kt"
MANIFEST="$APP_DIR/android/app/src/main/AndroidManifest.xml"

echo "==> 1. 注册 PosePlugin"
mkdir -p "$(dirname "$MAIN_KT")"
cat > "$MAIN_KT" <<'KT'
package com.jumprope.jumprope_app

import com.jumprope.PosePlugin
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        flutterEngine.plugins.add(PosePlugin())
    }
}
KT

echo "==> 2. 加相机权限"
if ! grep -q "android.permission.CAMERA" "$MANIFEST"; then
  python3 - "$MANIFEST" <<'PY'
import sys, re
p = sys.argv[1]
s = open(p, encoding='utf-8').read()
perm = ('    <uses-permission android:name="android.permission.CAMERA" />\n'
        '    <uses-permission android:name="android.permission.READ_MEDIA_VIDEO" />\n')
s = re.sub(r'(<manifest[^>]*>\n)', r'\1' + perm, s, count=1)
open(p, 'w', encoding='utf-8').write(s)
PY
fi

echo "==> 3. 加依赖 + minSdk"
python3 - "$APP_DIR" <<'PY'
import sys, os, glob
app = sys.argv[1]
deps = '''
    implementation("com.google.mediapipe:tasks-vision:0.10.14")
    implementation("androidx.camera:camera-core:1.3.4")
    implementation("androidx.camera:camera-camera2:1.3.4")
    implementation("androidx.camera:camera-lifecycle:1.3.4")
'''

candidates = glob.glob(os.path.join(app, 'android/app/build.gradle*'))
assert candidates, '找不到 android/app/build.gradle'
path = candidates[0]
s = open(path, encoding='utf-8').read()

if 'mediapipe' not in s:
    if path.endswith('.kts'):
        s = s.replace('dependencies {', 'dependencies {' + deps, 1)
    else:
        s = s.replace('dependencies {', 'dependencies {' + deps, 1)

# minSdk 24（MediaPipe Tasks 要求）
for old in ['minSdkVersion flutter.minSdkVersion', 'minSdk = flutter.minSdkVersion',
            'minSdkVersion 21', 'minSdk = 21']:
    s = s.replace(old, old.replace('21', '24').replace('flutter.minSdkVersion', '24'))

open(path, 'w', encoding='utf-8').write(s)
print('已修改', path)
PY

echo "==> 完成"

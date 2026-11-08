#!/usr/bin/env bash
# 把 flutter create 生成的工程改造成能编译本项目的样子。
# 所有"模板差异"都集中在这里；构建失败优先查这个脚本。
set -euo pipefail

APP_DIR="${1:-ci_app}"
PKG_DIR="$APP_DIR/android/app/src/main/kotlin/com/jumprope/jumprope_app"
MAIN_KT="$PKG_DIR/MainActivity.kt"
MANIFEST="$APP_DIR/android/app/src/main/AndroidManifest.xml"
GRADLE_FILE="$(ls "$APP_DIR"/android/app/build.gradle* 2>/dev/null | head -1)"

echo "==> 目标工程: $APP_DIR"
echo "==> gradle 文件: $GRADLE_FILE"

[ -n "$GRADLE_FILE" ] || { echo "找不到 android/app/build.gradle"; exit 1; }

# ── 1. 注册 PosePlugin ────────────────────────────────
echo "==> 1/4 注册 PosePlugin"
mkdir -p "$PKG_DIR"
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
grep -q "PosePlugin" "$MAIN_KT" || { echo "MainActivity 写入失败"; exit 1; }

# ── 2. 相机权限 ───────────────────────────────────────
echo "==> 2/4 加相机权限"
python3 - "$MANIFEST" <<'PY'
import sys, re
p = sys.argv[1]
s = open(p, encoding='utf-8').read()
if 'android.permission.CAMERA' not in s:
    perm = ('    <uses-permission android:name="android.permission.CAMERA" />\n'
            '    <uses-permission android:name="android.permission.READ_MEDIA_VIDEO" />\n')
    s = re.sub(r'(<manifest[^>]*>\n?)', lambda m: m.group(1) + perm, s, count=1)
    open(p, 'w', encoding='utf-8').write(s)
PY
grep -q "android.permission.CAMERA" "$MANIFEST" || { echo "权限写入失败"; exit 1; }

# ── 2.5 关闭 Impeller（Texture 组件在黑屏问题修复前不可用）──
echo "==> 2.5 关闭 Impeller"
python3 - "$MANIFEST" <<'PYMSG'
import sys, re
p = sys.argv[1]
s = open(p, encoding='utf-8').read()
if 'EnableImpeller' not in s:
    meta = ('        <meta-data\n'
            '            android:name="io.flutter.embedding.android.EnableImpeller"\n'
            '            android:value="false" />\n')
    # 插到 <application ...> 之后
    s = re.sub(r'(<application[^>]*>\n?)', lambda m: m.group(1) + meta, s, count=1)
    open(p, 'w', encoding='utf-8').write(s)
PYMSG
grep -q "EnableImpeller" "$MANIFEST" || { echo "Impeller 开关写入失败"; exit 1; }

# ── 3. 依赖与 minSdk ──────────────────────────────────
echo "==> 3/4 注入依赖与 minSdk"
python3 - "$GRADLE_FILE" <<'PY'
import sys
path = sys.argv[1]
s = open(path, encoding='utf-8').read()

deps_body = '''
    implementation("com.google.mediapipe:tasks-vision:0.10.14")
    implementation("androidx.camera:camera-core:1.3.4")
    implementation("androidx.camera:camera-camera2:1.3.4")
    implementation("androidx.camera:camera-lifecycle:1.3.4")
'''

if 'mediapipe' not in s:
    # 模板里可能根本没有 dependencies 块，直接追加到文件末尾
    s = s.rstrip() + '\n\ndependencies {\n' + deps_body + '}\n'

# minSdk 24（MediaPipe Tasks 要求）
s = s.replace('minSdkVersion flutter.minSdkVersion', 'minSdkVersion 24')
s = s.replace('minSdk = flutter.minSdkVersion', 'minSdk = 24')
s = s.replace('minSdkVersion 21', 'minSdkVersion 24')
s = s.replace('minSdk = 21', 'minSdk = 24')
s = s.replace('minSdkVersion 19', 'minSdkVersion 24')

open(path, 'w', encoding='utf-8').write(s)
PY

grep -q "mediapipe" "$GRADLE_FILE" || { echo "❌ 依赖注入失败"; exit 1; }
echo "   依赖注入 OK"

# ── 4. Gradle 发行包换国内镜像（GitHub Release CDN 经常 504）──
echo "==> 4/5 检查 Gradle 发行包源"
WRAPPER="$APP_DIR/android/gradle/wrapper/gradle-wrapper.properties"
if [ -f "$WRAPPER" ]; then
  VER="$(grep -oE 'gradle-[0-9.]+-(all|bin)\.zip' "$WRAPPER" | head -1)"
  if [ -n "$VER" ]; then
    MIRROR="https://mirrors.cloud.tencent.com/gradle/$VER"
    CODE="$(curl -sI -m 20 -o /dev/null -w '%{http_code}' "$MIRROR" || echo 000)"
    echo "   版本 $VER  镜像 HTTP $CODE"
    if [ "$CODE" = "200" ]; then
      ESCAPED="$(printf '%s' "$MIRROR" | sed 's|:|\\:|g')"
      sed -i "s|distributionUrl=.*|distributionUrl=$ESCAPED|" "$WRAPPER"
      echo "   已切换到镜像源"
    else
      echo "   镜像不可用，保留原源"
    fi
  fi
fi

# ── 5. 打印结果，方便在日志里核对 ─────────────────────
echo "==> 5/5 校验"
echo "--- dependencies 片段 ---"
grep -n -A6 "^dependencies" "$GRADLE_FILE" || true
echo "--- minSdk ---"
grep -n "minSdk" "$GRADLE_FILE" || echo "(未找到 minSdk，使用模板默认)"
echo "==> 完成"

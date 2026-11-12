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

import android.Manifest
import android.content.pm.PackageManager
import android.graphics.Color
import android.graphics.drawable.ColorDrawable
import android.os.Bundle
import android.view.View
import android.view.ViewGroup
import com.jumprope.PosePlugin
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.android.FlutterView
import io.flutter.embedding.android.RenderMode
import io.flutter.embedding.engine.FlutterEngine

class MainActivity : FlutterActivity() {
    // 用 TextureView 渲染，才能把 Flutter 画面透明地叠在原生预览上
    override fun getRenderMode(): RenderMode = RenderMode.texture

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        flutterEngine.plugins.add(PosePlugin())
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        window.setBackgroundDrawable(ColorDrawable(Color.BLACK))
        makeFlutterTransparent(findViewById(android.R.id.content))
        ensureCameraPermission()
    }

    /** Android 6+ 必须运行时申请相机权限，否则 CameraX 直接抛异常 */
    private fun ensureCameraPermission() {
        if (checkSelfPermission(Manifest.permission.CAMERA) != PackageManager.PERMISSION_GRANTED) {
            requestPermissions(arrayOf(Manifest.permission.CAMERA), 1001)
        }
    }

    private fun makeFlutterTransparent(v: View) {
        if (v is FlutterView) {
            v.setBackgroundColor(Color.TRANSPARENT)
            return
        }
        if (v is ViewGroup) {
            for (i in 0 until v.childCount) makeFlutterTransparent(v.getChildAt(i))
        }
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
            '    <uses-permission android:name="android.permission.RECORD_AUDIO" />\n'
            '    <uses-permission android:name="android.permission.READ_MEDIA_VIDEO" />\n')
    s = re.sub(r'(<manifest[^>]*>\n?)', lambda m: m.group(1) + perm, s, count=1)
    open(p, 'w', encoding='utf-8').write(s)
PY
grep -q "android.permission.CAMERA" "$MANIFEST" || { echo "权限写入失败"; exit 1; }

# Android 11+ 需要声明 TTS 服务可见性，否则 TextToSpeech 找不到引擎（无声）
python3 - "$MANIFEST" <<'PYTTS'
import sys, re
p = sys.argv[1]
s = open(p, encoding='utf-8').read()
if 'TTS_SERVICE' not in s:
    queries = ('    <queries>\n'
               '        <intent>\n'
               '            <action android:name="android.intent.action.TTS_SERVICE" />\n'
               '        </intent>\n'
               '    </queries>\n')
    s = re.sub(r'(</manifest>)', queries + r'\1', s, count=1)
    open(p, 'w', encoding='utf-8').write(s)
PYTTS
grep -q "TTS_SERVICE" "$MANIFEST" || { echo "TTS 可见性写入失败"; exit 1; }
echo "   已声明 TTS 服务可见性"

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
    // 不升 1.2.2：它会带入 litertlm 依赖，缺类导致 R8 失败，
    // 而 platform_ 的问题靠 proguard keep 规则解决，与版本无关
    implementation("com.google.mediapipe:tasks-vision:0.10.14")
    implementation("androidx.camera:camera-core:1.3.4")
    implementation("androidx.camera:camera-camera2:1.3.4")
    implementation("androidx.camera:camera-lifecycle:1.3.4")
    implementation("androidx.camera:camera-view:1.3.4")
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

# ── 4.5 模型放到 Android 原生 assets ──────────────────
# Flutter 会把资源打包到 assets/flutter_assets/ 下，
# 而 MediaPipe 的 setModelAssetPath 读的是 Android assets 根目录，
# 所以必须另外复制一份到 android/app/src/main/assets/
echo "==> 4.5 放置姿态模型"
SRC_MODEL="$(ls "$APP_DIR"/assets/*.task 2>/dev/null | head -1 || true)"
if [ -z "$SRC_MODEL" ]; then
  echo "❌ 没找到模型文件（$APP_DIR/assets/*.task）"
  exit 1
fi
mkdir -p "$APP_DIR/android/app/src/main/assets"
cp "$SRC_MODEL" "$APP_DIR/android/app/src/main/assets/"
MODEL_NAME="$(basename "$SRC_MODEL")"
[ -f "$APP_DIR/android/app/src/main/assets/$MODEL_NAME" ] || {
  echo "❌ 模型复制失败"; exit 1; }
echo "   已放入 Android assets: $MODEL_NAME ($(du -h "$SRC_MODEL" | cut -f1))"

# ── 4.6 MediaPipe 的 R8 keep 规则 ─────────────────────
# MediaPipe Tasks 不提供 consumer rules。release 构建开了 R8 后，
# 它内部 protobuf-lite 的字段 platform_ 会被重命名，
# PoseLandmarker.createFromOptions 反射取值时抛
#   RuntimeException: Field platform_ for <obfuscated> not found
# 参见 sceneview/sceneview@0d31314 的修复。
echo "==> 4.6 写入 MediaPipe keep 规则"
cat > "$APP_DIR/android/app/proguard-rules.pro" <<'PROGUARD'
# MediaPipe Tasks：原生层按名字找 Java 类，选项走 protobuf-lite 且按字段名反射
-keep class com.google.mediapipe.** { *; }
-keepclassmembers class * extends com.google.protobuf.GeneratedMessageLite { <fields>; }
# MediaPipe 用 Flogger 记录日志，它靠栈帧找调用方；被重命名会抛 no caller found
-keep class com.google.common.flogger.** { *; }
-dontwarn com.google.mediapipe.proto.CalculatorProfileProto$CalculatorProfile
-dontwarn com.google.mediapipe.proto.GraphTemplateProto$CalculatorGraphTemplate
PROGUARD

python3 - "$APP_DIR" "$APP_DIR/android/app/build.gradle.kts" <<'PYPATCH'
import os, sys, glob
app = sys.argv[1]
files = glob.glob(os.path.join(app, 'android/app/build.gradle*'))
if not files:
    print('   ❌ 找不到 build.gradle')
    raise SystemExit(1)
path = files[0]
s = open(path, encoding='utf-8').read()
kts = path.endswith('.kts')
if 'proguard-rules.pro' not in s:
    if kts:
        add = ('        isMinifyEnabled = true\n'
               '        proguardFiles(getDefaultProguardFile("proguard-android-optimize.txt"), "proguard-rules.pro")\n')
    else:
        add = ("        minifyEnabled true\n"
               "        proguardFiles getDefaultProguardFile('proguard-android-optimize.txt'), 'proguard-rules.pro'\n")
    idx = s.find('release {')
    if idx < 0:
        print('   ❌ 找不到 release 块')
        raise SystemExit(1)
    insert_at = s.index('{', idx) + 1
    s = s[:insert_at] + '\n' + add + s[insert_at:]
    open(path, 'w', encoding='utf-8').write(s)
    print('   已注入 proguardFiles')
else:
    print('   已存在 proguardFiles')
PYPATCH

# ── 4.7 关闭 release lint ────────────────────────────
# 新版 AGP 的 lint 在 camera_android_camerax 上崩：
#   lintVitalAnalyzeRelease > CommentDetector > NoSuchMethodError
# 这是 lint 自身的 bug，与业务代码无关；release 只做打包，不跑 lint。
echo "==> 4.7 关闭 release lint"
python3 - "$APP_DIR" <<'PYLINT'
import glob, os, re, sys
app = sys.argv[1]
files = glob.glob(os.path.join(app, 'android/app/build.gradle*'))
if not files:
    print('   ❌ 找不到 build.gradle')
    raise SystemExit(1)
path = files[0]
s = open(path, encoding='utf-8').read()
if 'checkReleaseBuilds' in s:
    print('   已存在 lint 配置')
else:
    kts = path.endswith('.kts')
    add = ('\n    lint {\n'
           '        checkReleaseBuilds = false\n'
           '        abortOnError = false\n'
           '    }\n') if kts else ('\n    lint {\n'
                                   '        checkReleaseBuilds false\n'
                                   '        abortOnError false\n'
                                   '    }\n')
    m = re.search(r'\nandroid\s*\{', s)
    if not m:
        print('   ❌ 找不到 android 块')
        raise SystemExit(1)
    s = s[:m.end()] + add + s[m.end():]
    open(path, 'w', encoding='utf-8').write(s)
    print('   已关闭 checkReleaseBuilds')
PYLINT

# 插件子工程（camera_android_camerax）自己的 lintVital 也要关，
# 只改 app 的 lint 配置管不到它。
python3 - "$APP_DIR" <<'PYROOT'
import glob, os, sys
app = sys.argv[1]
files = glob.glob(os.path.join(app, 'android/build.gradle*'))
if not files:
    print('   ❌ 找不到根 build.gradle')
    raise SystemExit(1)
path = files[0]
s = open(path, encoding='utf-8').read()
if 'lintVital' not in s:
    kts = path.endswith('.kts')
    add = ('\nsubprojects {\n'
           '    tasks.matching { it.name.contains("lintVital") }.configureEach { enabled = false }\n'
           '}\n') if kts else ('\nsubprojects {\n'
                               "    tasks.matching { it.name.contains('lintVital') }.configureEach { enabled = false }\n"
                               '}\n')
    open(path, 'w', encoding='utf-8').write(s.rstrip() + '\n' + add)
    print('   已关闭子工程 lintVital')
else:
    print('   子工程 lintVital 已处理')
PYROOT

# ── 5. 打印结果，方便在日志里核对 ─────────────────────
echo "==> 5/5 校验"
echo "--- dependencies 片段 ---"
grep -n -A6 "^dependencies" "$GRADLE_FILE" || true
echo "--- minSdk ---"
grep -n "minSdk" "$GRADLE_FILE" || echo "(未找到 minSdk，使用模板默认)"
echo "==> 完成"

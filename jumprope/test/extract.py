#!/usr/bin/env python3
"""
从视频里逐帧提取 33 个姿态关键点，存成 JSON。
后续由 replay.mjs 用「和线上完全相同的计数代码」回放。

用法:
    python3 test/extract.py input.mp4 out.json
"""
import sys
import os
import json

import cv2
import mediapipe as mp
from mediapipe.tasks import python as mpp
from mediapipe.tasks.python import vision

MODEL = os.path.join(os.path.dirname(__file__), '..', 'public', 'models',
                     'pose_landmarker_lite.task')


def main(video_path, out_path):
    cap = cv2.VideoCapture(video_path)
    if not cap.isOpened():
        print(f'打不开视频: {video_path}', file=sys.stderr)
        sys.exit(1)

    fps = cap.get(cv2.CAP_PROP_FPS) or 30.0
    width = int(cap.get(cv2.CAP_PROP_FRAME_WIDTH))
    height = int(cap.get(cv2.CAP_PROP_FRAME_HEIGHT))
    total = int(cap.get(cv2.CAP_PROP_FRAME_COUNT))
    print(f'视频: {width}x{height} @ {fps:.2f}fps, 共 {total} 帧', flush=True)

    options = vision.PoseLandmarkerOptions(
        base_options=mpp.BaseOptions(model_asset_path=MODEL),
        running_mode=vision.RunningMode.VIDEO,
        num_poses=1,
        min_pose_detection_confidence=0.5,
        min_pose_presence_confidence=0.5,
        min_tracking_confidence=0.5,
    )
    landmarker = vision.PoseLandmarker.create_from_options(options)

    frames = []
    i = 0
    detected = 0
    while True:
        ok, frame = cap.read()
        if not ok:
            break

        rgb = cv2.cvtColor(frame, cv2.COLOR_BGR2RGB)
        mpimg = mp.Image(image_format=mp.ImageFormat.SRGB, data=rgb)
        ts = int(round(i * 1000.0 / fps))

        res = landmarker.detect_for_video(mpimg, ts)
        if res.pose_landmarks:
            pts = [[round(p.x, 5), round(p.y, 5), round(p.z, 5), round(p.visibility, 4)]
                   for p in res.pose_landmarks[0]]
            detected += 1
        else:
            pts = None
        frames.append({'t': ts, 'lm': pts})

        i += 1
        if i % 30 == 0:
            print(f'  已处理 {i}/{total} 帧, 检出 {detected}', flush=True)

    cap.release()

    with open(out_path, 'w', encoding='utf-8') as f:
        json.dump({'fps': fps, 'width': width, 'height': height, 'frames': frames}, f)

    print(f'完成: {len(frames)} 帧, 检出人体 {detected} 帧 -> {out_path}', flush=True)
    # 绕开 mediapipe 退出时的已知崩溃
    sys.stdout.flush()
    os._exit(0)


if __name__ == '__main__':
    if len(sys.argv) != 3:
        print(__doc__)
        sys.exit(1)
    main(sys.argv[1], sys.argv[2])

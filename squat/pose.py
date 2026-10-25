"""Thin wrapper over MediaPipe PoseLandmarker (video mode)."""
from pathlib import Path

import cv2
import mediapipe as mp
import numpy as np
from mediapipe.tasks.python import BaseOptions, vision

MODELS = {m: Path(__file__).parent / "models" / f"pose_landmarker_{m}.task" for m in ("lite", "full", "heavy")}

# Landmark indices we use (MediaPipe BlazePose, 33 points).
NOSE, L_SHO, R_SHO, L_HIP, R_HIP, L_KNEE, R_KNEE, L_ANK, R_ANK = 0, 11, 12, 23, 24, 25, 26, 27, 28


class Pose:
    """Returns pixel x/y, z, visibility; None for missing poses or nonincreasing timestamps."""

    def __init__(self, model: Path = MODELS["full"]):
        opts = vision.PoseLandmarkerOptions(
            base_options=BaseOptions(model_asset_path=str(model)),
            running_mode=vision.RunningMode.VIDEO,
        )
        self._lm = vision.PoseLandmarker.create_from_options(opts)
        self._last_timestamp_ms = None

    def __call__(self, bgr: np.ndarray, t_ms: int):
        if self._last_timestamp_ms is not None and t_ms <= self._last_timestamp_ms:
            return None
        self._last_timestamp_ms = t_ms
        h, w = bgr.shape[:2]
        rgb = np.ascontiguousarray(cv2.cvtColor(bgr, cv2.COLOR_BGR2RGB))
        res = self._lm.detect_for_video(mp.Image(image_format=mp.ImageFormat.SRGB, data=rgb), t_ms)
        if not res.pose_landmarks:
            return None
        return np.array([[p.x * w, p.y * h, p.z * w, p.visibility] for p in res.pose_landmarks[0]], np.float32)

    def close(self):
        self._lm.close()

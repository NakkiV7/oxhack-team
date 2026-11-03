#!/bin/sh
# Downloads the MediaPipe Pose Landmarker model (about 9 MB, Apache-2.0) into models/.
set -e
cd "$(dirname "$0")/.."
mkdir -p models
curl -L --fail -o models/pose_landmarker_full.task \
  https://storage.googleapis.com/mediapipe-models/pose_landmarker/pose_landmarker_full/float16/latest/pose_landmarker_full.task
echo "Model saved to models/pose_landmarker_full.task"

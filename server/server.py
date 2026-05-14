"""
포스처가드 모바일 전용 서버
폰 카메라 프레임을 받아 MediaPipe로 분석 후 결과 반환

실행: uvicorn server:app --host 0.0.0.0 --port 8000
의존: pip install fastapi "uvicorn[standard]" mediapipe opencv-python numpy
"""

import asyncio
import base64
import concurrent.futures
import math
import os
import sys
import time
import urllib.request

import cv2
import numpy as np
import mediapipe as mp
from fastapi import FastAPI, WebSocket, WebSocketDisconnect
from fastapi.middleware.cors import CORSMiddleware

# ── 모델 다운로드 ─────────────────────────────────────────────────
POSE_MODEL_URL  = "https://storage.googleapis.com/mediapipe-models/pose_landmarker/pose_landmarker_heavy/float16/1/pose_landmarker_heavy.task"
POSE_MODEL_PATH = "pose_landmarker.task"
FACE_MODEL_URL  = "https://storage.googleapis.com/mediapipe-models/face_landmarker/face_landmarker/float16/1/face_landmarker.task"
FACE_MODEL_PATH = "face_landmarker.task"

def download_model(url, path, retries=3):
    for attempt in range(1, retries + 1):
        try:
            print(f"[모델] {os.path.basename(path)} 다운로드 중... ({attempt}/{retries})")
            urllib.request.urlretrieve(url, path)
            print(f"[모델] {os.path.basename(path)} 완료.")
            return True
        except Exception as e:
            print(f"[모델] 실패: {e}")
    return False

for url, path in [(POSE_MODEL_URL, POSE_MODEL_PATH), (FACE_MODEL_URL, FACE_MODEL_PATH)]:
    if not os.path.exists(path):
        if not download_model(url, path):
            print(f"[오류] {path} 다운로드 실패. 종료합니다.")
            sys.exit(1)

print("[서버] 모델 로드 완료.")

# ── MediaPipe API ─────────────────────────────────────────────────
BaseOptions           = mp.tasks.BaseOptions
VisionRunningMode     = mp.tasks.vision.RunningMode
PoseLandmarker        = mp.tasks.vision.PoseLandmarker
PoseLandmarkerOptions = mp.tasks.vision.PoseLandmarkerOptions
FaceLandmarker        = mp.tasks.vision.FaceLandmarker
FaceLandmarkerOptions = mp.tasks.vision.FaceLandmarkerOptions

# ── 분석 파라미터 ────────────────────────────────────────────────
WEIGHT_PITCH     = 0.40
WEIGHT_EYE       = 0.30
WEIGHT_VIS       = 0.15
WEIGHT_Z         = 0.15
PITCH_DANGER_DEG = 12.0
CALIB_SECONDS    = 5

FACE_3D = np.array([
    [0.0, 0.0, 0.0], [0.0, -330.0, -65.0],
    [-225.0, 170.0, -135.0], [225.0, 170.0, -135.0],
    [-150.0, -150.0, -125.0], [150.0, -150.0, -125.0],
], dtype=np.float64)
FACE_LM_IDX = [1, 152, 263, 33, 287, 57]

_executor = concurrent.futures.ThreadPoolExecutor(max_workers=4)

# ── 분석 헬퍼 함수 ───────────────────────────────────────────────
def get_dist(p1, p2):
    return math.sqrt((p1.x - p2.x)**2 + (p1.y - p2.y)**2)

def get_head_pitch(face_lm, w, h):
    try:
        pts_2d = np.array(
            [[face_lm[i].x * w, face_lm[i].y * h] for i in FACE_LM_IDX],
            dtype=np.float64)
        focal = float(w)
        cam_mat = np.array([[focal,0,w/2],[0,focal,h/2],[0,0,1]], dtype=np.float64)
        ok, rvec, _ = cv2.solvePnP(FACE_3D, pts_2d, cam_mat, np.zeros((4,1)))
        if not ok: return None
        rmat, _ = cv2.Rodrigues(rvec)
        return math.degrees(math.atan2(rmat[2][1], rmat[2][2]))
    except:
        return None

def get_eye_ratio(face_lm, pose_lm, shld_w):
    try:
        eye_y = (face_lm[33].y + face_lm[133].y +
                 face_lm[263].y + face_lm[362].y) / 4
        shoulder_y = (pose_lm[11].y + pose_lm[12].y) / 2
        return abs(eye_y - shoulder_y) / shld_w
    except:
        return None

# ── 모바일 세션 (연결 1개당 독립 상태) ──────────────────────────
class MobileSession:
    def __init__(self, client_addr):
        self.client = client_addr
        pose_opts = PoseLandmarkerOptions(
            base_options=BaseOptions(model_asset_path=POSE_MODEL_PATH),
            running_mode=VisionRunningMode.IMAGE,
        )
        face_opts = FaceLandmarkerOptions(
            base_options=BaseOptions(model_asset_path=FACE_MODEL_PATH),
            running_mode=VisionRunningMode.IMAGE,
            num_faces=1,
        )
        self.pose_lmk   = PoseLandmarker.create_from_options(pose_opts)
        self.face_lmk   = FaceLandmarker.create_from_options(face_opts)
        self.calib      = {'z_diff':[],'ear_vis':[],'pitch':[],'eye_ratio':[]}
        self.golden     = {'z_diff':0.0,'ear_vis':0.0,'pitch':0.0,'eye_ratio':0.0}
        self.calibrated = False
        self.start_time = time.time()
        print(f"[모바일] {client_addr} 세션 시작.")

    def close(self):
        try: self.pose_lmk.close()
        except: pass
        try: self.face_lmk.close()
        except: pass
        print(f"[모바일] {self.client} 세션 종료.")

    def process(self, frame_b64: str) -> dict:
        try:
            frame = cv2.imdecode(
                np.frombuffer(base64.b64decode(frame_b64), np.uint8),
                cv2.IMREAD_COLOR)
            if frame is None:
                return self._err("프레임 디코딩 실패")

            frame = cv2.flip(frame, 1)           # 전면 카메라 좌우 반전
            h, w  = frame.shape[:2]
            rgb   = cv2.cvtColor(frame, cv2.COLOR_BGR2RGB)
            mp_img = mp.Image(image_format=mp.ImageFormat.SRGB, data=rgb)

            pr = self.pose_lmk.detect(mp_img)
            fr = self.face_lmk.detect(mp_img)

            if not pr.pose_landmarks:
                return self._no_person()

            pose_lm = pr.pose_landmarks[0]
            face_lm = fr.face_landmarks[0] if fr.face_landmarks else None
            shld_w  = get_dist(pose_lm[11], pose_lm[12])
            if shld_w == 0:
                return self._no_person()

            elapsed = time.time() - self.start_time

            # 캘리브레이션 (5초 또는 첫 프레임)
            # 현재 프레임을 먼저 수집해야 5초 경과 후 첫 프레임도 반영됨
            if not self.calibrated:
                self.calib['ear_vis'].append(
                    (pose_lm[7].visibility + pose_lm[8].visibility) / 2)
                self.calib['z_diff'].append(
                    (pose_lm[11].z + pose_lm[12].z)/2 -
                    (pose_lm[7].z  + pose_lm[8].z )/2)
                if face_lm:
                    p = get_head_pitch(face_lm, w, h)
                    if p: self.calib['pitch'].append(p)
                    r = get_eye_ratio(face_lm, pose_lm, shld_w)
                    if r: self.calib['eye_ratio'].append(r)

                if elapsed < CALIB_SECONDS:
                    cd = max(0, CALIB_SECONDS - int(elapsed))
                    return {"status":"calibrating","countdown":cd,"score":0,
                            "is_fhp":False,
                            "scores":{"pitch":1.0,"eye":1.0,"vis":1.0,"z":1.0}}
                else:
                    for k in self.golden:
                        v = self.calib[k]
                        self.golden[k] = float(np.mean(v)) if v else 0.0
                    self.calibrated = True
                    print(f"[캘리브레이션] {self.client} 완료 "
                          f"pitch={self.golden['pitch']:.1f}°")

            # 점수 계산
            ear_vis = (pose_lm[7].visibility + pose_lm[8].visibility) / 2
            curr_z  = ((pose_lm[11].z + pose_lm[12].z)/2 -
                       (pose_lm[7].z  + pose_lm[8].z )/2)

            # golden_z_diff가 0이면 캘리브레이션 실패 → 현재 프레임으로 즉시 보정
            if self.golden['z_diff'] == 0.0 and curr_z != 0.0:
                self.golden['z_diff'] = curr_z
                print(f"[보정] golden_z_diff가 0 → curr_z({curr_z:.4f})로 대체")
            if self.golden['ear_vis'] == 0.0:
                self.golden['ear_vis'] = ear_vis
                print(f"[보정] golden_ear_vis가 0 → {ear_vis:.4f}로 대체")

            s_vis = float(np.clip(1-(self.golden['ear_vis']-ear_vis)/0.15, 0,1))
            # z 임계값을 0.1→0.25로 확대 (0.1은 너무 민감해 항상 0이 됨)
            s_z   = float(np.clip(1-(curr_z-self.golden['z_diff'])/0.25,   0,1))
            s_pitch, s_eye = 1.0, 1.0
            face_detected = face_lm is not None

            if face_lm:
                p = get_head_pitch(face_lm, w, h)
                if p and self.golden['pitch'] != 0:
                    s_pitch = float(np.clip(
                        1-(p-self.golden['pitch'])/PITCH_DANGER_DEG, 0,1))
                r = get_eye_ratio(face_lm, pose_lm, shld_w)
                if r and self.golden['eye_ratio'] > 0:
                    s_eye = float(np.clip(
                        (r/self.golden['eye_ratio']-0.7)/0.3, 0,1))

            score  = max(0, min(100, int((
                s_pitch*WEIGHT_PITCH + s_eye*WEIGHT_EYE +
                s_vis*WEIGHT_VIS     + s_z*WEIGHT_Z) * 100)))
            is_fhp = score < 80

            print(
                f"[점수] face={face_detected} "
                f"golden_z={self.golden['z_diff']:.4f} curr_z={curr_z:.4f} delta_z={curr_z-self.golden['z_diff']:.4f} "
                f"golden_pitch={self.golden['pitch']:.2f} | "
                f"s_pitch={s_pitch:.3f} s_eye={s_eye:.3f} s_vis={s_vis:.3f} s_z={s_z:.3f} "
                f"=> score={score}"
            )

            return {
                "status":    "warning" if is_fhp else "ok",
                "score":     score,
                "is_fhp":    is_fhp,
                "countdown": 0,
                "scores": {
                    "pitch": round(s_pitch,3),
                    "eye":   round(s_eye,3),
                    "vis":   round(s_vis,3),
                    "z":     round(s_z,3),
                },
            }
        except Exception as e:
            print(f"[분석 오류] {e}")
            return self._no_person()

    @staticmethod
    def _no_person():
        return {"status":"no_person","score":0,"is_fhp":False,"countdown":0,
                "scores":{"pitch":1.0,"eye":1.0,"vis":1.0,"z":1.0}}

    @staticmethod
    def _err(msg):
        print(f"[오류] {msg}")
        return MobileSession._no_person()


# ── FastAPI 앱 ────────────────────────────────────────────────────
app = FastAPI()
app.add_middleware(CORSMiddleware, allow_origins=["*"],
                   allow_methods=["*"], allow_headers=["*"])

@app.on_event("startup")
async def startup():
    print("[서버] 모바일 전용 모드로 시작됨.")
    print("[서버] 폰에서 ws://<이 PC IP>:8000/ws/mobile 으로 연결하세요.")

@app.websocket("/ws/mobile")
async def websocket_mobile(websocket: WebSocket):
    await websocket.accept()
    client = websocket.client
    session = MobileSession(client)
    loop    = asyncio.get_event_loop()
    try:
        while True:
            data = await websocket.receive_json()
            if data.get("type") == "frame":
                result = await loop.run_in_executor(
                    _executor, session.process, data["frame"])
                await websocket.send_json(result)
    except (WebSocketDisconnect, Exception) as e:
        print(f"[모바일 WS] 해제: {type(e).__name__}")
    finally:
        session.close()

# 연결 테스트용 (브라우저에서 http://<IP>:8000/ping 접속)
@app.get("/ping")
async def ping():
    return {"pong": True, "server": "포스처가드 모바일"}

@app.get("/health")
async def health():
    return {"ok": True}

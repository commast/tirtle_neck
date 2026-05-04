"""
거북목 감지 FastAPI WebSocket 서버
실행: uvicorn server:app --host 0.0.0.0 --port 8000
의존: pip install fastapi "uvicorn[standard]" mediapipe opencv-python numpy
"""

import asyncio
import base64
import threading
import time
import math
import os
import sys
import urllib.request
import traceback
from collections import deque

import cv2
import numpy as np
import mediapipe as mp
from fastapi import FastAPI, WebSocket, WebSocketDisconnect
from fastapi.middleware.cors import CORSMiddleware
import uvicorn

# ── 모델 다운로드 ─────────────────────────────────────────────────
POSE_MODEL_URL  = "https://storage.googleapis.com/mediapipe-models/pose_landmarker/pose_landmarker_heavy/float16/1/pose_landmarker_heavy.task"
POSE_MODEL_PATH = "pose_landmarker.task"
FACE_MODEL_URL  = "https://storage.googleapis.com/mediapipe-models/face_landmarker/face_landmarker/float16/1/face_landmarker.task"
FACE_MODEL_PATH = "face_landmarker.task"

def download_model(url, path, retries=3):
    for attempt in range(1, retries + 1):
        try:
            print(f"[모델] {os.path.basename(path)} 다운로드 {attempt}/{retries}...")
            urllib.request.urlretrieve(url, path)
            print(f"[모델] {os.path.basename(path)} 완료.")
            return True
        except Exception as e:
            print(f"[모델] 실패: {e}")
    return False

for url, path in [(POSE_MODEL_URL, POSE_MODEL_PATH), (FACE_MODEL_URL, FACE_MODEL_PATH)]:
    if not os.path.exists(path):
        if not download_model(url, path):
            print(f"[오류] {path} 다운로드 불가. 종료합니다.")
            sys.exit(1)

# ── MediaPipe 초기화 ──────────────────────────────────────────────
try:
    BaseOptions           = mp.tasks.BaseOptions
    VisionRunningMode     = mp.tasks.vision.RunningMode
    PoseLandmarker        = mp.tasks.vision.PoseLandmarker
    PoseLandmarkerOptions = mp.tasks.vision.PoseLandmarkerOptions
    FaceLandmarker        = mp.tasks.vision.FaceLandmarker
    FaceLandmarkerOptions = mp.tasks.vision.FaceLandmarkerOptions
except AttributeError as e:
    print(f"[오류] MediaPipe Tasks API 초기화 실패: {e}")
    sys.exit(1)

# ── 파라미터 ─────────────────────────────────────────────────────
WEIGHT_PITCH     = 0.40
WEIGHT_EYE       = 0.30
WEIGHT_VIS       = 0.15
WEIGHT_Z         = 0.15
PITCH_DANGER_DEG = 12.0
CALIB_SECONDS    = 5
GRAPH_LEN        = 180   # 그래프에 표시할 프레임 수

# ── 공유 상태 ─────────────────────────────────────────────────────
state = {
    "status": "starting", "score": 0, "countdown": CALIB_SECONDS,
    "scores": {"pitch": 1.0, "eye": 1.0, "vis": 1.0, "z": 1.0},
    "is_fhp": False,
}
state_lock = threading.Lock()

# 히스토리 버퍼 (그래프용)
score_buf   = deque(maxlen=GRAPH_LEN)
sub_bufs    = {k: deque(maxlen=GRAPH_LEN) for k in ('pitch', 'eye', 'vis', 'z')}

# 최신 프레임 (Flutter 스트리밍용)
_frame_lock:    threading.Lock = threading.Lock()
_latest_frame:  str = ""   # base64 JPEG

def _encode_frame(frame: np.ndarray, max_w: int = 480) -> str:
    h, w = frame.shape[:2]
    scale = max_w / w
    small = cv2.resize(frame, (max_w, int(h * scale)))
    _, buf = cv2.imencode('.jpg', small, [cv2.IMWRITE_JPEG_QUALITY, 55])
    return base64.b64encode(buf).decode()

# ── solvePnP 기준점 ───────────────────────────────────────────────
FACE_3D = np.array([
    [  0.0,    0.0,   0.0],
    [  0.0, -330.0, -65.0],
    [-225.0,  170.0,-135.0],
    [ 225.0,  170.0,-135.0],
    [-150.0, -150.0,-125.0],
    [ 150.0, -150.0,-125.0],
], dtype=np.float64)
FACE_LM_IDX = [1, 152, 263, 33, 287, 57]

# Pose 연결선 (Tasks API 인덱스)
POSE_CONNECTIONS = [
    (0, 7), (0, 8),
    (11, 12), (11, 13), (13, 15), (12, 14), (14, 16),
    (11, 23), (12, 24), (23, 24),
]

# ── 그리기 함수 ───────────────────────────────────────────────────

def draw_pose(frame, pose_lm, h, w):
    pts = {i: (int(lm.x * w), int(lm.y * h)) for i, lm in enumerate(pose_lm)}
    for a, b in POSE_CONNECTIONS:
        if a in pts and b in pts:
            cv2.line(frame, pts[a], pts[b], (0, 200, 80), 2)
    for i, (x, y) in pts.items():
        cv2.circle(frame, (x, y), 4, (0, 255, 120), -1)


def draw_face(frame, face_lm, h, w):
    # 얼굴 윤곽 + 눈 핵심 포인트만 그림
    OUTLINE = [10, 338, 297, 332, 284, 251, 389, 356, 454,
               323, 361, 288, 397, 365, 379, 378, 400, 377,
               152, 148, 176, 149, 150, 136, 172, 58, 132,
               93, 234, 127, 162, 21, 54, 103, 67, 109, 10]
    pts = [(int(face_lm[i].x * w), int(face_lm[i].y * h)) for i in OUTLINE]
    for j in range(1, len(pts)):
        cv2.line(frame, pts[j-1], pts[j], (255, 180, 0), 1)


def _score_color(val: float):
    """0-1 값을 BGR 색상으로."""
    if val > 0.65:
        return (50, 230, 50)
    if val > 0.40:
        return (0, 165, 255)
    return (50, 50, 230)


def draw_graph_panel(h: int, w_panel: int = 280) -> np.ndarray:
    panel = np.full((h, w_panel, 3), 18, dtype=np.uint8)

    # ── 상단: 메인 점수 그래프 ────────────────────────────────────
    g_top    = 36
    g_bot    = h // 2 - 10
    g_h      = g_bot - g_top
    g_left   = 10
    g_right  = w_panel - 10
    g_w      = g_right - g_left

    cv2.putText(panel, "Posture Score", (g_left, 24),
                cv2.FONT_HERSHEY_SIMPLEX, 0.52, (200, 200, 200), 1, cv2.LINE_AA)

    # 그리드
    for pct in (25, 50, 75):
        gy = g_bot - int(pct / 100 * g_h)
        cv2.line(panel, (g_left, gy), (g_right, gy), (40, 40, 40), 1)
        cv2.putText(panel, str(pct), (g_right + 2, gy + 4),
                    cv2.FONT_HERSHEY_SIMPLEX, 0.32, (80, 80, 80), 1)

    # 점수 라인
    buf = list(score_buf)
    if len(buf) > 1:
        for i in range(1, len(buf)):
            x1 = g_left + int((i - 1) * g_w / GRAPH_LEN)
            x2 = g_left + int(i       * g_w / GRAPH_LEN)
            y1 = g_bot  - int(buf[i-1] / 100 * g_h)
            y2 = g_bot  - int(buf[i]   / 100 * g_h)
            col = _score_color(buf[i] / 100)
            cv2.line(panel, (x1, y1), (x2, y2), col, 2, cv2.LINE_AA)

    # 현재 점수 텍스트
    cur = buf[-1] if buf else 0
    col = _score_color(cur / 100)
    cv2.putText(panel, f"{cur}", (g_left, g_bot + 22),
                cv2.FONT_HERSHEY_SIMPLEX, 0.75, col, 2, cv2.LINE_AA)
    cv2.putText(panel, "/ 100", (g_left + 44, g_bot + 22),
                cv2.FONT_HERSHEY_SIMPLEX, 0.38, (120, 120, 120), 1)

    # ── 하단: 서브 지표 4개 미니 그래프 ──────────────────────────
    labels  = {'pitch': 'Pitch', 'eye': 'Eye/Sh', 'vis': 'Ear Vis', 'z': 'Z-axis'}
    sub_h   = (h - h // 2 - 20) // 4
    sub_top = h // 2 + 10

    for idx, (key, label) in enumerate(labels.items()):
        sy_top = sub_top + idx * sub_h
        sy_bot = sy_top + sub_h - 6
        s_h    = sy_bot - sy_top - 14

        cv2.putText(panel, label, (g_left, sy_top + 12),
                    cv2.FONT_HERSHEY_SIMPLEX, 0.38, (160, 160, 160), 1, cv2.LINE_AA)

        sbuf = list(sub_bufs[key])
        if len(sbuf) > 1:
            for i in range(1, len(sbuf)):
                x1 = g_left + int((i - 1) * g_w / GRAPH_LEN)
                x2 = g_left + int(i       * g_w / GRAPH_LEN)
                y1 = sy_bot - int(sbuf[i-1] * s_h)
                y2 = sy_bot - int(sbuf[i]   * s_h)
                cv2.line(panel, (x1, y1), (x2, y2), _score_color(sbuf[i]), 1, cv2.LINE_AA)

        # 현재 값 수치
        cur_sub = sbuf[-1] if sbuf else 1.0
        cv2.putText(panel, f"{int(cur_sub*100)}%",
                    (g_right - 30, sy_top + 12),
                    cv2.FONT_HERSHEY_SIMPLEX, 0.36, _score_color(cur_sub), 1)

    # 구분선
    cv2.line(panel, (w_panel - 1, 0), (w_panel - 1, h), (50, 50, 50), 1)
    return panel


# ── 감지 루프 (별도 스레드) ───────────────────────────────────────
def detection_loop():
    pose_options = PoseLandmarkerOptions(
        base_options=BaseOptions(model_asset_path=POSE_MODEL_PATH),
        running_mode=VisionRunningMode.VIDEO
    )
    face_options = FaceLandmarkerOptions(
        base_options=BaseOptions(model_asset_path=FACE_MODEL_PATH),
        running_mode=VisionRunningMode.VIDEO,
        num_faces=1
    )

    cap = None
    for idx in (0, 1, 2):
        cap = cv2.VideoCapture(idx, cv2.CAP_DSHOW)
        if cap.isOpened():
            ret, _ = cap.read()
            if ret:
                print(f"[카메라] 인덱스 {idx} 연결.")
                break
        cap.release()
        cap = None

    if cap is None:
        with state_lock:
            state["status"] = "error_no_camera"
        return

    calib_data     = {'z_diff': [], 'ear_vis': [], 'pitch': [], 'eye_ratio': []}
    golden         = {'z_diff': 0.0, 'ear_vis': 0.0, 'pitch': 0.0, 'eye_ratio': 0.0}
    is_calibrated  = False
    fhp_start_time = None

    try:
        with PoseLandmarker.create_from_options(pose_options) as pose_lmk, \
             FaceLandmarker.create_from_options(face_options) as face_lmk:

            start_time = time.time()
            consecutive_errors = 0

            while True:
                success, frame = cap.read()
                if not success:
                    consecutive_errors += 1
                    if consecutive_errors >= 10:
                        print("[카메라] 연속 오류 10회. 감지 종료.")
                        break
                    time.sleep(0.05)
                    continue

                consecutive_errors = 0
                frame        = cv2.flip(frame, 1)
                h, w         = frame.shape[:2]
                elapsed      = time.time() - start_time
                timestamp_ms = int(elapsed * 1000)

                rgb    = cv2.cvtColor(frame, cv2.COLOR_BGR2RGB)
                mp_img = mp.Image(image_format=mp.ImageFormat.SRGB, data=rgb)

                try:
                    pose_result = pose_lmk.detect_for_video(mp_img, timestamp_ms)
                    face_result = face_lmk.detect_for_video(mp_img, timestamp_ms)
                except Exception as e:
                    print(f"[감지] 오류: {e}")
                    continue

                if not pose_result.pose_landmarks:
                    with state_lock:
                        state["status"] = "no_person"
                    cv2.putText(frame, "사람을 찾을 수 없습니다", (20, 50),
                                cv2.FONT_HERSHEY_SIMPLEX, 0.9, (0, 165, 255), 2, cv2.LINE_AA)
                    panel   = draw_graph_panel(h)
                    display = np.hstack([panel, frame])
                    cv2.imshow("꼬부랑목 모니터", display)
                    cv2.waitKey(1)
                    continue

                pose_lm = pose_result.pose_landmarks[0]
                face_lm = face_result.face_landmarks[0] if face_result.face_landmarks else None
                shld_w  = get_dist(pose_lm[11], pose_lm[12])
                if shld_w == 0:
                    continue

                # ── 캘리브레이션 단계 ─────────────────────────────────
                if not is_calibrated:
                    countdown = max(0, CALIB_SECONDS - int(elapsed))
                    if elapsed < CALIB_SECONDS:
                        calib_data['ear_vis'].append(
                            (pose_lm[7].visibility + pose_lm[8].visibility) / 2)
                        calib_data['z_diff'].append(
                            (pose_lm[11].z + pose_lm[12].z) / 2 - (pose_lm[7].z + pose_lm[8].z) / 2)
                        if face_lm is not None:
                            p = get_head_pitch(face_lm, w, h)
                            if p is not None:
                                calib_data['pitch'].append(p)
                            r = get_eye_ratio(face_lm, pose_lm, shld_w)
                            if r is not None:
                                calib_data['eye_ratio'].append(r)
                        with state_lock:
                            state["status"]    = "calibrating"
                            state["countdown"] = countdown

                        draw_pose(frame, pose_lm, h, w)
                        if face_lm:
                            draw_face(frame, face_lm, h, w)
                        overlay = frame.copy()
                        cv2.rectangle(overlay, (0, 0), (w, 70), (0, 0, 0), -1)
                        cv2.addWeighted(overlay, 0.5, frame, 0.5, 0, frame)
                        cv2.putText(frame, "바른 자세로 앉아주세요", (20, 35),
                                    cv2.FONT_HERSHEY_SIMPLEX, 0.9, (0, 255, 255), 2, cv2.LINE_AA)
                        cv2.putText(frame, f"캘리브레이션: {countdown}초",  (20, 62),
                                    cv2.FONT_HERSHEY_SIMPLEX, 0.65, (0, 220, 220), 1, cv2.LINE_AA)
                    else:
                        for key in golden:
                            golden[key] = float(np.mean(calib_data[key])) if calib_data[key] else 0.0
                        is_calibrated = True
                        print(f"[캘리브레이션] pitch={golden['pitch']:.1f}° | ear_vis={golden['ear_vis']:.2f}")

                    panel   = draw_graph_panel(h)
                    display = np.hstack([panel, frame])
                    cv2.imshow("꼬부랑목 모니터", display)
                    cv2.waitKey(1)
                    continue

                # ── 점수 계산 ─────────────────────────────────────────
                try:
                    ear_vis = (pose_lm[7].visibility + pose_lm[8].visibility) / 2
                    curr_z  = (pose_lm[11].z + pose_lm[12].z) / 2 - (pose_lm[7].z + pose_lm[8].z) / 2

                    s_vis   = float(np.clip(1 - (golden['ear_vis'] - ear_vis) / 0.15, 0, 1))
                    s_z     = float(np.clip(1 - (curr_z - golden['z_diff']) / 0.1,   0, 1))
                    s_pitch = 1.0
                    s_eye   = 1.0

                    if face_lm is not None:
                        pitch = get_head_pitch(face_lm, w, h)
                        if pitch is not None:
                            s_pitch = float(np.clip(
                                1 - (pitch - golden['pitch']) / PITCH_DANGER_DEG, 0, 1))
                        ratio = get_eye_ratio(face_lm, pose_lm, shld_w)
                        if ratio is not None and golden['eye_ratio'] > 0:
                            s_eye = float(np.clip(
                                (ratio / golden['eye_ratio'] - 0.7) / 0.3, 0, 1))

                    final_score = max(0, min(100, int((
                        s_pitch * WEIGHT_PITCH +
                        s_eye   * WEIGHT_EYE   +
                        s_vis   * WEIGHT_VIS   +
                        s_z     * WEIGHT_Z
                    ) * 100)))
                    is_fhp = final_score < 80

                    if is_fhp:
                        fhp_start_time = fhp_start_time or time.time()
                    else:
                        fhp_start_time = None

                    # 히스토리 업데이트
                    score_buf.append(final_score)
                    sub_bufs['pitch'].append(s_pitch)
                    sub_bufs['eye'].append(s_eye)
                    sub_bufs['vis'].append(s_vis)
                    sub_bufs['z'].append(s_z)

                    with state_lock:
                        state["status"]  = "warning" if is_fhp else "ok"
                        state["score"]   = final_score
                        state["is_fhp"]  = is_fhp
                        state["scores"]  = {
                            "pitch": round(s_pitch, 3),
                            "eye":   round(s_eye,   3),
                            "vis":   round(s_vis,   3),
                            "z":     round(s_z,     3),
                        }

                    # ── 카메라 창 렌더링 ──────────────────────────────
                    draw_pose(frame, pose_lm, h, w)
                    if face_lm:
                        draw_face(frame, face_lm, h, w)

                    # 상단 HUD (점수 바)
                    bar_color = _score_color(final_score / 100)
                    cv2.rectangle(frame, (0, 0), (w, 52), (0, 0, 0), -1)
                    bar_w = int(final_score / 100 * (w - 20))
                    cv2.rectangle(frame, (10, 8), (10 + bar_w, 36), bar_color, -1)
                    cv2.rectangle(frame, (10, 8), (w - 10, 36), (80, 80, 80), 1)
                    label = "WARNING: 스트레칭 하세요!" if is_fhp else "자세 양호"
                    cv2.putText(frame, f"{final_score}  {label}", (14, 30),
                                cv2.FONT_HERSHEY_SIMPLEX, 0.62, (10, 10, 10), 2, cv2.LINE_AA)
                    cv2.putText(frame, f"{final_score}  {label}", (14, 30),
                                cv2.FONT_HERSHEY_SIMPLEX, 0.62, (240, 240, 240), 1, cv2.LINE_AA)

                    # Flutter 스트리밍용 프레임 저장
                    with _frame_lock:
                        global _latest_frame
                        _latest_frame = _encode_frame(frame)

                    panel   = draw_graph_panel(h)
                    display = np.hstack([panel, frame])
                    cv2.imshow("꼬부랑목 모니터", display)
                    cv2.waitKey(1)

                except Exception as e:
                    print(f"[점수 계산] 오류: {e}")
                    traceback.print_exc()

    except Exception as e:
        print(f"[감지 스레드] 치명적 오류: {e}")
        traceback.print_exc()
    finally:
        if cap:
            cap.release()
        cv2.destroyAllWindows()
        print("[감지 스레드] 종료.")


def get_dist(p1, p2):
    return math.sqrt((p1.x - p2.x)**2 + (p1.y - p2.y)**2)

def get_head_pitch(face_lm, w, h):
    try:
        pts_2d = np.array(
            [[face_lm[i].x * w, face_lm[i].y * h] for i in FACE_LM_IDX],
            dtype=np.float64
        )
        focal   = float(w)
        cam_mat = np.array([[focal, 0, w/2], [0, focal, h/2], [0, 0, 1]], dtype=np.float64)
        ok, rvec, _ = cv2.solvePnP(FACE_3D, pts_2d, cam_mat, np.zeros((4, 1)))
        if not ok:
            return None
        rmat, _ = cv2.Rodrigues(rvec)
        return math.degrees(math.atan2(rmat[2][1], rmat[2][2]))
    except Exception:
        return None

def get_eye_ratio(face_lm, pose_lm, shld_w):
    try:
        eye_y = (face_lm[33].y + face_lm[133].y +
                 face_lm[263].y + face_lm[362].y) / 4
        shoulder_y = (pose_lm[11].y + pose_lm[12].y) / 2
        return abs(eye_y - shoulder_y) / shld_w
    except Exception:
        return None


# ── FastAPI 앱 ────────────────────────────────────────────────────
app = FastAPI()
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_methods=["*"],
    allow_headers=["*"],
)

connected_clients: list[WebSocket] = []

@app.on_event("startup")
async def startup():
    t = threading.Thread(target=detection_loop, daemon=True)
    t.start()
    print("[서버] 감지 스레드 시작.")

@app.websocket("/ws")
async def websocket_endpoint(websocket: WebSocket):
    await websocket.accept()
    connected_clients.append(websocket)
    print(f"[WebSocket] 클라이언트 연결. 총 {len(connected_clients)}명")
    try:
        while True:
            with state_lock:
                payload = dict(state)
            with _frame_lock:
                payload["frame"] = _latest_frame
            await websocket.send_json(payload)
            await asyncio.sleep(0.05)
    except WebSocketDisconnect:
        pass
    except Exception as e:
        print(f"[WebSocket] 오류: {e}")
    finally:
        connected_clients.remove(websocket)
        print(f"[WebSocket] 클라이언트 해제. 총 {len(connected_clients)}명")

@app.get("/health")
async def health():
    with state_lock:
        return {"ok": True, "state": dict(state)}

if __name__ == "__main__":
    uvicorn.run(app, host="0.0.0.0", port=8000, log_level="warning")

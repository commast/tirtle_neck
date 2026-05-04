# 포스처가드 — 구조 & 기능 요약

## 프로젝트 파일 구조

```
tirtle_ml/
├─ server/
│   ├─ server.py              ← Python FastAPI 서버 (WebSocket + MediaPipe)
│   └─ requirements.txt
│
├─ lib/
│   ├─ main.dart              ← 앱 진입점 + TirtleApp (MaterialApp 설정만)
│   ├─ constants.dart         ← 상수 (kServerUrl, kGreen, kBg, kGraphMax)
│   │
│   ├─ models/
│   │   └─ posture_state.dart ← PostureState 데이터 모델 + fromJson
│   │
│   ├─ painters/
│   │   ├─ arc_gauge_painter.dart   ← 원형 호 게이지 CustomPainter
│   │   └─ area_line_painter.dart   ← 면적 채움 선 그래프 CustomPainter
│   │
│   └─ screens/
│       ├─ main_screen.dart   ← WebSocket 연결 + 바텀 네비게이션 + 탭 라우팅
│       ├─ home_tab.dart      ← 홈 (점수 카드, 그래프, 이슈, 가이드)
│       ├─ report_tab.dart    ← 리포트 (원형 게이지, 추이, 생체 데이터)
│       ├─ camera_tab.dart    ← 카메라 실시간 피드 + 서브 지표
│       ├─ reward_tab.dart    ← 보상 센터 (토큰, 랜덤 보상)
│       └─ profile_tab.dart   ← 프로필 + 설정
│
├─ PLAN.md                    ← 이 파일
└─ PLAN2.md                   ← Python 서버 내부 상세 문서
```

## 각 파일 역할

| 파일 | 역할 | 의존 |
|------|------|------|
| `main.dart` | 앱 시작, 테마 설정 | constants, main_screen |
| `constants.dart` | 색상·URL·상수 공유 | 없음 |
| `models/posture_state.dart` | WebSocket JSON → 객체 변환 | 없음 |
| `painters/arc_gauge_painter.dart` | 270° 원형 점수 게이지 | flutter/material |
| `painters/area_line_painter.dart` | 면적 채움 실시간 그래프 | flutter/material |
| `screens/main_screen.dart` | WebSocket 연결·재연결, 바텀 네비 | 모든 탭 |
| `screens/home_tab.dart` | 메인 대시보드 | constants, model, painters |
| `screens/report_tab.dart` | 분석 리포트 | constants, model, painters |
| `screens/camera_tab.dart` | 카메라 피드, 경고 배너 | constants, model |
| `screens/reward_tab.dart` | 토큰 시스템 | constants |
| `screens/profile_tab.dart` | 프로필, 설정 목록 | constants |

## 전체 데이터 흐름

```
[PC 웹캠]
    ↓ OpenCV (CAP_DSHOW)
[detection_loop 스레드]
    ├─ MediaPipe Tasks API
    │   ├─ PoseLandmarker  → 어깨/귀 랜드마크, z축
    │   └─ FaceLandmarker  → solvePnP 피치각, 눈-어깨 비율
    ├─ 점수 계산 (pitch 40% + eye 30% + vis 15% + z 15%)
    ├─ 캘리브레이션 보정 (5초 기준값 대비 편차)
    └─ JPEG 인코딩 → base64
         ↓ 공유 state + frame (threading.Lock)
[FastAPI WebSocket /ws]
    ↓ JSON (20fps)
[MainScreen — WebSocket 수신]
    ├─ PostureState.fromJson()
    ├─ _scoreHistory / _subHistory 업데이트
    └─ setState() → 하위 탭 리빌드
```

## WebSocket JSON 구조

```json
{
  "status":    "calibrating | ok | warning | no_person | error_no_camera",
  "score":     85,
  "countdown": 3,
  "is_fhp":    false,
  "scores": { "pitch": 0.9, "eye": 0.8, "vis": 1.0, "z": 0.7 },
  "frame":     "<base64 JPEG>"
}
```

## 점수 체계

| 지표 | 방법 | 가중치 |
|------|------|--------|
| pitch | solvePnP 머리 피치각 vs 기준 | 40% |
| eye | 눈-어깨 수직 비율 vs 기준 | 30% |
| vis | 귀 가시성 | 15% |
| z | 어깨-귀 z축 차이 | 15% |

- `score` 0–100, 높을수록 좋은 자세
- `is_fhp = score < 80`

## 주요 기능

| 기능 | 설명 | 구현 위치 |
|------|------|-----------|
| 서버 자동 시작 | 앱 실행 시 `"포스처가드 서버"` 창이 자동으로 열리며 uvicorn 서버 시작 | `main_screen.dart` `_startServer()` |
| **서버 자동 종료** | **Flutter 창 X버튼으로 닫으면 Python 서버 창도 함께 종료** (`taskkill /F /FI WINDOWTITLE`) | `main_screen.dart` `_killServer()` |
| WebSocket 자동 재연결 | 서버 연결 끊기면 3초 후 자동 재연결 | `main_screen.dart` `_onDisconnect()` |
| 자세 스냅샷 측정 | 앱 시작 직후 즉시 1회 + 이후 **2분마다** 자동 측정, `PostureSnapshot` 객체로 저장 | `main_screen.dart` `_takeSnapshot()` |
| 오늘의 자세 점수 | 스냅샷 점수의 평균값 (홈 화면 표시) | `main_screen.dart` `_todayScore` |
| 리포트 — 자세 건강 점수 | 원형 게이지 + 상위 몇% 동기부여 문구 | `report_tab.dart` `_scoreGaugeCard()` |
| 리포트 — 시간대별 변화 | 스냅샷 기반 타임라인 그래프 (시각 라벨, 면적 채움, 최저 시각 분석) | `report_tab.dart` `_timelineCard()` |
| 리포트 — 각도 분석 | 현재/평균 목 각도(°) + 사람 실루엣 그림으로 FHP 시각화 | `report_tab.dart` `_biometricCard()` |
| 리포트 — 이전 대비 개선도 | 이전·현재 점수 바 차트 + 점수 차이 표시 | `report_tab.dart` `_comparisonCard()` |
| 실시간 카메라 피드 | 서버에서 base64 JPEG를 20fps로 수신해 표시 | `camera_tab.dart` |
| 5초 캘리브레이션 | 앱 첫 실행 시 바른 자세 기준값 수집 | `server/server.py` |

## 실행 방법

```bash
# Flutter 앱만 실행하면 Python 서버가 자동으로 함께 시작됩니다
flutter run

# 최초 1회만: Python 패키지 설치
cd tirtle_ml/server
pip install fastapi "uvicorn[standard]" mediapipe opencv-python numpy
```

## 서버 주소 변경

[lib/constants.dart](lib/constants.dart) 의 `kServerUrl` 수정:
- Windows 앱: `ws://localhost:8000/ws`
- 안드로이드 에뮬레이터: `ws://10.0.2.2:8000/ws`
- 실기기 (같은 와이파이): `ws://<PC IP>:8000/ws`

## 주요 오류 해결

| 오류 | 해결 |
|------|------|
| `No supported WebSocket library` | `pip install "uvicorn[standard]"` |
| 카메라 안 열림 | 자동으로 0→1→2 순서 시도, CAP_DSHOW 사용 |
| 항상 no_person | 조명 개선, 카메라를 눈높이에 |
| Flutter 재연결 중 | 서버가 실행 중인지 확인 |

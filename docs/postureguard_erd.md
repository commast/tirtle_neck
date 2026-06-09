# 포스처가드 논리 ERD

현재 앱은 서버 DB가 아니라 `SharedPreferences` 기반으로 데이터를 저장한다.
따라서 이 ERD는 실제 테이블 구현도가 아니라, `PLAN.md`와 현재 모델 코드를 기준으로 정리한 발표용 논리 ERD이다.

## ERD

```mermaid
erDiagram
    USER ||--|| ALERT_SETTINGS : has
    USER ||--o{ CAMERA_MODE_SETTING : configures
    USER ||--o{ CALIBRATION_PROFILE : calibrates
    USER ||--o{ DAILY_USAGE_SNAPSHOT : owns
    USER ||--o{ WARNING_EVENT : receives
    USER ||--o{ POSTURE_SNAPSHOT : records

    APP_CATEGORY ||--o{ FOREGROUND_APP : classifies
    APP_CATEGORY ||--o{ APP_USAGE_RECORD : aggregates
    APP_CATEGORY ||--o{ HOURLY_WARNING_BUCKET : groups
    APP_CATEGORY ||--o{ WARNING_EVENT : groups

    DETECTED_CONTEXT ||--o{ CONTEXT_SNAPSHOT : resolves
    DETECTED_CONTEXT ||--o{ CALIBRATION_PROFILE : has_baseline
    DETECTED_CONTEXT ||--o{ CAMERA_MODE_SETTING : allows_camera
    DETECTED_CONTEXT ||--o{ WARNING_EVENT : occurs_in

    NECK_RISK_LEVEL ||--o{ WARNING_EVENT : labels
    FOREGROUND_APP ||--o{ CONTEXT_SNAPSHOT : appears_as
    FOREGROUND_APP ||--o{ APP_USAGE_RECORD : accumulates
    FOREGROUND_APP ||--o{ WARNING_EVENT : triggers

    DAILY_USAGE_SNAPSHOT ||--o{ APP_USAGE_RECORD : contains
    DAILY_USAGE_SNAPSHOT ||--o{ HOURLY_WARNING_BUCKET : contains
    WARNING_EVENT }o--|| APP_USAGE_RECORD : updates_count
    WARNING_EVENT }o--|| HOURLY_WARNING_BUCKET : updates_hour

    USER {
        string user_id PK
        string display_name
        string email
    }

    ALERT_SETTINGS {
        string user_id PK, FK
        boolean vibration_enabled
        boolean sound_enabled
        double vibration_level
        double sound_level
    }

    CAMERA_MODE_SETTING {
        string user_id FK
        string context_code FK
        boolean camera_enabled
    }

    CALIBRATION_PROFILE {
        string user_id FK
        string context_code FK
        double baseline_tilt_deg
        datetime set_at
    }

    DETECTED_CONTEXT {
        string context_code PK
        string label
        double pitch_threshold_deg
        double risk_weight
        boolean overlay_visible
        boolean camera_supported
    }

    APP_CATEGORY {
        string category_code PK
        string label
        string color_hex
    }

    FOREGROUND_APP {
        string package_name PK
        string app_label
        string category_code FK
        string system_category
        datetime last_seen_at
    }

    CONTEXT_SNAPSHOT {
        string snapshot_id PK
        datetime detected_at
        string context_code FK
        string package_name FK
        string foreground_label
        string category_code FK
        boolean screen_on
        boolean in_call
        string sensor_posture
    }

    DAILY_USAGE_SNAPSHOT {
        string date PK
        string user_id FK
    }

    APP_USAGE_RECORD {
        string date PK, FK
        string package_name PK, FK
        string app_label
        string category_code FK
        int usage_seconds
        int warning_count
    }

    HOURLY_WARNING_BUCKET {
        string date PK, FK
        int hour PK
        string category_code PK, FK
        int warning_count
    }

    WARNING_EVENT {
        string warning_id PK
        datetime occurred_at
        string user_id FK
        string package_name FK
        string category_code FK
        string context_code FK
        string risk_level FK
        int risk_score
    }

    NECK_RISK_LEVEL {
        string risk_level PK
        string label
        int min_score
        int max_score
        string color_hex
    }

    POSTURE_SNAPSHOT {
        string snapshot_id PK
        string user_id FK
        datetime captured_at
        int score
        double pitch_deg
    }
```

## 현재 저장 구조 매핑

| 논리 엔티티 | 현재 구현/저장 위치 |
|---|---|
| `DAILY_USAGE_SNAPSHOT` | `SharedPreferences` key: `usage_history_v1` |
| `APP_USAGE_RECORD` | `DailyUsageSnapshot.apps[]` 내부 JSON |
| `HOURLY_WARNING_BUCKET` | `DailyUsageSnapshot.hourly`, `DailyUsageSnapshot.cat_hourly` |
| `POSTURE_SNAPSHOT` | `SharedPreferences` key: `capture_history_v1` |
| `CALIBRATION_PROFILE` | `posture_calibration_tilt_{mode}`, `posture_calibration_setAt_{mode}` |
| `ALERT_SETTINGS` | `alert_vibration_v1`, `alert_sound_v1`, `alert_vib_level_v1`, `alert_snd_level_v1` |
| `CAMERA_MODE_SETTING` | `camera_in_gaming`, `camera_in_video` |
| `FOREGROUND_APP`, `CONTEXT_SNAPSHOT`, `WARNING_EVENT` | 현재는 주로 런타임 상태/집계로 처리. DB화 시 분리 가능 |

## 발표용 핵심 설명

- 사용자는 앱을 실행하고 센서 측정을 시작한다.
- 포그라운드 앱은 `FOREGROUND_APP`으로 식별되고 `APP_CATEGORY`로 분류된다.
- 포그라운드 앱, 화면 상태, 통화 상태, 센서 자세가 합쳐져 `DETECTED_CONTEXT`가 결정된다.
- 자세 위험이 발생하면 `WARNING_EVENT`가 생기고, 일별/시간대별 리포트 집계에 반영된다.
- 캘리브레이션과 알림, 카메라 설정은 사용자별 설정 데이터로 분리된다.

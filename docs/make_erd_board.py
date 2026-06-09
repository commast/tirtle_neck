from pathlib import Path

from PIL import Image, ImageDraw, ImageFont


ROOT = Path(__file__).resolve().parent
OUT = ROOT / "postureguard_erd.png"


def font(size, bold=False):
    candidates = [
        "C:/Windows/Fonts/malgunbd.ttf" if bold else "C:/Windows/Fonts/malgun.ttf",
        "C:/Windows/Fonts/NotoSansKR-Bold.ttf" if bold else "C:/Windows/Fonts/NotoSansKR-Regular.ttf",
    ]
    for item in candidates:
        path = Path(item)
        if path.exists():
            return ImageFont.truetype(str(path), size)
    return ImageFont.load_default()


F_TITLE = font(44, True)
F_SUB = font(22)
F_ENTITY = font(24, True)
F_FIELD = font(18)
F_NOTE_TITLE = font(24, True)
F_NOTE = font(19)


COLORS = {
    "core": ("#e9f9f5", "#12a886"),
    "report": ("#fff4df", "#de8d00"),
    "setting": ("#f3eafb", "#8e24aa"),
    "lookup": ("#eaf3ff", "#1e88e5"),
    "runtime": ("#f2f4f7", "#667085"),
    "concept": ("#fff0f0", "#e53935"),
}


def rounded(draw, box, radius, fill, outline, width=2):
    draw.rounded_rectangle(box, radius=radius, fill=fill, outline=outline, width=width)


def entity(draw, xy, w, title, fields, kind):
    x, y = xy
    fill, outline = COLORS[kind]
    row_h = 27
    h = 56 + row_h * len(fields)
    rounded(draw, (x, y, x + w, y + h), 13, "#ffffff", outline, 3)
    rounded(draw, (x, y, x + w, y + 46), 13, fill, outline, 3)
    draw.rectangle((x + 2, y + 32, x + w - 2, y + 47), fill=fill)
    draw.text((x + 16, y + 11), title, font=F_ENTITY, fill="#111827")
    yy = y + 58
    for f in fields:
        color = "#111827" if "PK" in f else "#4b5563"
        draw.text((x + 18, yy), f, font=F_FIELD, fill=color)
        yy += row_h
    return h


def panel(draw, xy, w, title, lines, accent="#12a886"):
    x, y = xy
    h = 62 + len(lines) * 31
    rounded(draw, (x, y, x + w, y + h), 14, "#f9fafb", "#d1d5db", 2)
    draw.rectangle((x, y, x + 8, y + h), fill=accent)
    draw.text((x + 24, y + 18), title, font=F_NOTE_TITLE, fill="#111827")
    yy = y + 64
    for line in lines:
        draw.text((x + 28, yy), f"- {line}", font=F_NOTE, fill="#374151")
        yy += 31


def main():
    img = Image.new("RGB", (2400, 1500), "#ffffff")
    draw = ImageDraw.Draw(img)

    draw.text((80, 54), "포스처가드 저장 데이터 ERD", font=F_TITLE, fill="#111827")
    draw.text(
        (82, 112),
        "PLAN.md 기준 논리 ERD. 실제 구현은 SharedPreferences 저장이며, 발표용으로 DB화 가능한 엔티티를 정리",
        font=F_SUB,
        fill="#6b7280",
    )

    xs = [80, 600, 1120, 1640]
    ys = [190, 520, 850]
    w = 430

    entity(draw, (xs[0], ys[0]), w, "USER", [
        "user_id PK",
        "display_name",
        "email",
    ], "core")

    entity(draw, (xs[1], ys[0]), w, "USER_SETTINGS", [
        "user_id PK, FK",
        "vibration_enabled",
        "sound_enabled",
        "camera_in_video",
        "camera_in_game",
    ], "setting")

    entity(draw, (xs[2], ys[0]), w, "DAILY_USAGE_SNAPSHOT", [
        "date PK",
        "user_id FK",
    ], "core")

    entity(draw, (xs[3], ys[0]), w, "APP_USAGE_RECORD", [
        "date PK, FK",
        "package_name PK, FK",
        "app_label",
        "category_code FK",
        "usage_seconds",
        "warning_count",
    ], "report")

    entity(draw, (xs[0], ys[1]), w, "DETECTED_CONTEXT", [
        "context_code PK",
        "label",
        "pitch_threshold_deg",
        "risk_weight",
        "overlay_visible",
    ], "lookup")

    entity(draw, (xs[1], ys[1]), w, "CALIBRATION_PROFILE", [
        "user_id FK",
        "context_code FK",
        "baseline_tilt_deg",
        "set_at",
    ], "setting")

    entity(draw, (xs[2], ys[1]), w, "HOURLY_WARNING_BUCKET", [
        "date PK, FK",
        "hour PK",
        "category_code PK, FK",
        "warning_count",
    ], "report")

    entity(draw, (xs[3], ys[1]), w, "POSTURE_SNAPSHOT", [
        "snapshot_id PK",
        "user_id FK",
        "captured_at",
        "score",
        "pitch_deg",
    ], "report")

    entity(draw, (xs[0], ys[2]), w, "APP_CATEGORY", [
        "category_code PK",
        "label",
        "color_hex",
    ], "lookup")

    entity(draw, (xs[1], ys[2]), w, "FOREGROUND_APP", [
        "package_name PK",
        "app_label",
        "category_code FK",
        "system_category",
        "last_seen_at",
    ], "runtime")

    entity(draw, (xs[2], ys[2]), w, "WARNING_EVENT", [
        "warning_id PK",
        "occurred_at",
        "package_name FK",
        "category_code FK",
        "context_code FK",
        "risk_score",
    ], "concept")
    draw.text((xs[2] + 18, ys[2] + 225), "현재는 개별 저장 없이 집계만 저장", font=F_FIELD, fill="#e53935")

    panel(draw, (80, 1165), 980, "주요 관계", [
        "USER 1:1 USER_SETTINGS",
        "USER 1:N DAILY_USAGE_SNAPSHOT / CALIBRATION_PROFILE / POSTURE_SNAPSHOT",
        "DAILY_USAGE_SNAPSHOT 1:N APP_USAGE_RECORD / HOURLY_WARNING_BUCKET",
        "APP_CATEGORY 1:N FOREGROUND_APP / APP_USAGE_RECORD / HOURLY_WARNING_BUCKET",
        "DETECTED_CONTEXT 1:N CALIBRATION_PROFILE / WARNING_EVENT",
        "FOREGROUND_APP 1:N APP_USAGE_RECORD / WARNING_EVENT",
    ], "#12a886")

    panel(draw, (1120, 1165), 950, "현재 저장 키 매핑", [
        "usage_history_v1 → DAILY_USAGE, APP_USAGE, HOURLY_WARNING_BUCKET",
        "capture_history_v1 → POSTURE_SNAPSHOT",
        "posture_calibration_tilt_{mode}, setAt_{mode} → CALIBRATION_PROFILE",
        "alert_* / camera_in_* → USER_SETTINGS",
        "WARNING_EVENT는 DB화 시 분리 가능, 현재는 warning_count로만 집계",
    ], "#de8d00")

    # Small legend
    lx, ly = 1640, 880
    legend = [
        ("핵심", "core"),
        ("설정", "setting"),
        ("분류 기준", "lookup"),
        ("리포트/기록", "report"),
        ("런타임", "runtime"),
        ("DB화 후보", "concept"),
    ]
    rounded(draw, (lx, ly, lx + 430, ly + 245), 14, "#ffffff", "#d1d5db", 2)
    draw.text((lx + 20, ly + 18), "범례", font=F_NOTE_TITLE, fill="#111827")
    yy = ly + 62
    for label, kind in legend:
        fill, outline = COLORS[kind]
        rounded(draw, (lx + 24, yy + 2, lx + 52, yy + 30), 7, fill, outline, 2)
        draw.text((lx + 66, yy + 4), label, font=F_NOTE, fill="#374151")
        yy += 31

    img.save(OUT, quality=95)
    print(OUT)


if __name__ == "__main__":
    main()

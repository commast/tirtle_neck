from pathlib import Path

from PIL import Image, ImageDraw, ImageFont


ROOT = Path(__file__).resolve().parent
ASSETS = ROOT / "screen_design_assets"
OUT = ROOT / "screen_flow_design_notion.png"


def font(size, bold=False):
    names = [
        "C:/Windows/Fonts/malgunbd.ttf" if bold else "C:/Windows/Fonts/malgun.ttf",
        "C:/Windows/Fonts/NotoSansKR-Bold.ttf" if bold else "C:/Windows/Fonts/NotoSansKR-Regular.ttf",
    ]
    for name in names:
        path = Path(name)
        if path.exists():
            return ImageFont.truetype(str(path), size)
    return ImageFont.load_default()


F_TITLE = font(56, True)
F_H2 = font(30, True)
F_BODY = font(23)
F_SMALL = font(19)
F_TAG = font(19, True)
F_CARD = font(25, True)


def rounded(draw, box, radius, fill, outline=None, width=1):
    draw.rounded_rectangle(box, radius=radius, fill=fill, outline=outline, width=width)


def wrap_text(draw, text, fnt, max_width):
    words = text.split(" ")
    lines = []
    current = ""
    for word in words:
        test = word if not current else f"{current} {word}"
        if draw.textbbox((0, 0), test, font=fnt)[2] <= max_width:
            current = test
        else:
            if current:
                lines.append(current)
            current = word
    if current:
        lines.append(current)
    return lines


def text_block(draw, xy, text, fnt, fill, width, line_gap=8):
    x, y = xy
    for line in wrap_text(draw, text, fnt, width):
        draw.text((x, y), line, font=fnt, fill=fill)
        y += fnt.size + line_gap
    return y


def draw_tag(draw, x, y, text, color):
    pad_x = 18
    pad_y = 8
    bbox = draw.textbbox((0, 0), text, font=F_TAG)
    w = bbox[2] - bbox[0] + pad_x * 2
    h = bbox[3] - bbox[1] + pad_y * 2
    rounded(draw, (x, y, x + w, y + h), 22, color)
    draw.text((x + pad_x, y + pad_y - 2), text, font=F_TAG, fill="white")


def load_phone(name, max_w=210, max_h=445):
    img = Image.open(ASSETS / name).convert("RGB")
    img.thumbnail((max_w, max_h), Image.LANCZOS)
    return img


def draw_arrow(draw, x1, y, x2):
    draw.line((x1, y, x2, y), fill="#7b5536", width=6)
    draw.polygon([(x2, y), (x2 - 20, y - 12), (x2 - 20, y + 12)], fill="#7b5536")


def screen_card(draw, canvas, x, y, w, h, index, title, tag, tag_color, desc, image_name, callouts):
    rounded(draw, (x, y, x + w, y + h), 14, "#ffffff", "#d9dee8", 2)
    rounded(draw, (x, y, x + w, y + 102), 14, "#fbfcfe", "#d9dee8", 2)
    draw.rectangle((x + 2, y + 80, x + w - 2, y + 102), fill="#fbfcfe")
    draw.text((x + 22, y + 22), f"{index}. {title}", font=F_CARD, fill="#16191f")
    draw_tag(draw, x + w - 110, y + 20, tag, tag_color)
    text_block(draw, (x + 22, y + 60), desc, F_SMALL, "#6f7785", w - 44, 5)

    phone = load_phone(image_name)
    px = x + (w - phone.width) // 2
    py = y + 132
    rounded(draw, (px - 8, py - 8, px + phone.width + 8, py + phone.height + 8), 12, "#eef1f7")
    canvas.paste(phone, (px, py))

    for cx, cy, text, color in callouts:
        lines = text.split("\n")
        max_line = max(draw.textbbox((0, 0), line, font=F_SMALL)[2] for line in lines)
        cw = max_line + 26
        ch = len(lines) * 25 + 18
        rounded(draw, (x + cx, y + cy, x + cx + cw, y + cy + ch), 10, "#ffffff", color, 2)
        ty = y + cy + 9
        for line in lines:
            draw.text((x + cx + 13, ty), line, font=F_SMALL, fill=color)
            ty += 25


def main():
    canvas = Image.new("RGB", (2400, 1500), "#ffffff")
    draw = ImageDraw.Draw(canvas)

    bullets = [
        ("홈 화면", "연결 상태와 오늘의 사용/주의 추이를 확인하고 중앙 측정 버튼으로 시작한다."),
        ("오버레이", "영상앱 위에 영상 모드가 표시되며, 실제 액션은 측정 버튼 클릭이다."),
        ("리포트", "오늘/주간/월간 탭에서 사용 시간과 주의 횟수를 확인한다."),
        ("앱 설정", "자세 오버레이, 모드별 카메라, 알람, 측정 기준을 조정한다."),
    ]
    bx, by, bw, bh, gap = 90, 70, 520, 118, 28
    for i, (title, body) in enumerate(bullets):
        x = bx + i * (bw + gap)
        rounded(draw, (x, by, x + bw, by + bh), 12, "#fbfcfe", "#d9dee8", 2)
        draw.text((x + 22, by + 18), title, font=F_H2, fill="#16191f")
        text_block(draw, (x + 22, by + 58), body, F_SMALL, "#6f7785", bw - 44, 5)

    cards = [
        (90, 250, "홈", "대기", "#12c59b", "연결됨 상태와 오늘의 주요 앱/주의 추이를 확인한다.", "home.jpg", [(285, 405, "중앙 버튼 클릭\n측정 시작", "#07896b")]),
        (665, 250, "측정 시작", "ON", "#ef3b3b", "초록 버튼을 누르면 빨간 측정 상태로 바뀌고 센서 측정을 시작한다.", "home.jpg", [(275, 70, "빨간 상태 전환\n센서 측정 시작", "#c22222")]),
        (1240, 250, "앱 감지", "오버레이", "#9b29cf", "영상앱 위에 영상 모드가 표시되고 측정 버튼으로 센서 측정을 시작한다.", "youtube_overlay.jpg", [(260, 72, "영상 모드 표시\n현재 앱 상태", "#8021a8"), (270, 405, "측정 버튼 클릭\n측정 시작", "#07896b")]),
        (1815, 250, "리포트 반영", "주의", "#f5a623", "주의가 발생하면 앱, 카테고리, 시간 기준으로 저장되어 리포트에 반영된다.", "report_today.jpg", [(270, 75, "주의 횟수\n리포트 반영", "#a46700")]),
        (90, 885, "오늘 리포트", "오늘", "#12c59b", "카테고리별 사용 비율과 주의 횟수를 한눈에 확인한다.", "report_today.jpg", [(275, 180, "영상 30m\n주의 36회", "#07896b")]),
        (665, 885, "주간 리포트", "주간", "#12c59b", "요일별 사용량과 주의 횟수를 막대 그래프로 비교한다.", "report_week.jpg", [(38, 70, "오늘 / 주간 / 월간\n탭 전환", "#07896b")]),
        (1240, 885, "카드 펼침", "상세", "#707782", "카테고리 카드를 펼쳐 앱별 사용 시간과 주의 횟수를 본다.", "report_expanded.jpg", [(260, 405, "앱별 상세\n주의 횟수", "#a46700")]),
        (1815, 885, "앱 설정", "설정", "#178eea", "프로필에서 자세 오버레이, 모드별 카메라, 알람과 측정 기준을 설정한다.", "profile_settings.jpg", [(38, 80, "자세 오버레이\n시작", "#8021a8"), (245, 405, "모드별 카메라\n사용 설정", "#a46700")]),
    ]
    cw, ch = 495, 545
    for card in cards:
        x, y, title, tag, tag_color, desc, image, callouts = card
        screen_card(draw, canvas, x, y, cw, ch, cards.index(card) + 1, title, tag, tag_color, desc, image, callouts)

    for x1 in (585, 1160, 1735):
        draw_arrow(draw, x1, 525, x1 + 62)
        draw_arrow(draw, x1, 1160, x1 + 62)

    canvas.save(OUT, quality=95)
    print(OUT)


if __name__ == "__main__":
    main()

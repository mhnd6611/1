#!/bin/bash
set +m

# ═════════════════════════════════════════════
#  إعدادات البث — Respect
# ═════════════════════════════════════════════

TITLE="لم يبدأ ستريمرز ريسبكت"
SUBTITLE="جاري انتضار ستريمرز ريسبكت المذكورين اعلاه"
LABEL="قائمة الستريمرز:"

COLOR_T="#b266ff"
COLOR_S="#ffffff"
COLOR_L="#b266ff"
COLOR_NAME="#d9b3ff"

FS_T=100
FS_S=58
FS_L=22
FS_NAME=22

Y_LIST=60
Y_TITLE=200
Y_SUB=370

LOGO_URL="https://i.top4top.io/p_39264fv5g0.png"
LOGO_W=150
LOGO_BOTTOM=40
LOGO_SHOW=5
LOGO_CYCLE=7

FPS=60
GOP=120

BG_TOP_R=13; BG_TOP_G=5;  BG_TOP_B=24
BG_BOT_R=26; BG_BOT_G=10; BG_BOT_B=48
GLOW_R=150;  GLOW_G=80;   GLOW_B=220
# ═════════════════════════════════════════════

RESTREAM_KEY="${RESTREAM_KEY:-}"
[ -z "$RESTREAM_KEY" ] && { echo "❌ مفتاح فارغ"; exit 1; }
[ -z "$STREAMERS_LIST" ] && { echo "❌ قائمة فارغة"; exit 1; }

UA="Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"
RESTREAM_URL="rtmp://live.restream.io/live/$RESTREAM_KEY"
UDP_PORT=9999
UDP_OUT="udp://127.0.0.1:$UDP_PORT?pkt_size=1316"
UDP_IN="udp://127.0.0.1:$UDP_PORT?fifo_size=5000000&overrun_nonfatal=1&reuse=1"

FONT_AR=""
for C in "$HOME/.fonts/Cairo-var.ttf" "$HOME/.fonts/NotoSansArabic-Bold.ttf"; do
    [ -s "$C" ] && { FONT_AR="$C"; break; }
done
[ -z "$FONT_AR" ] && { echo "❌ لا يوجد خط عربي"; exit 1; }

FONT_EN="$HOME/.fonts/Orbitron-var.ttf"
[ ! -s "$FONT_EN" ] && { echo "❌ لا يوجد Orbitron"; exit 1; }

echo "🔤 عربي: $FONT_AR"
echo "🔤 إنجليزي: $FONT_EN"
echo "🎬 FPS: $FPS"

IFS=',' read -r -a STREAMERS <<< "$STREAMERS_LIST"
echo "🔢 عدد الستريمرز: ${#STREAMERS[@]}"

# ═════════ توليد صورة الانتظار كاملة ═════════
cat > /tmp/make_standby.py <<PYEOF
from PIL import Image, ImageDraw, ImageFont, ImageFilter

W, H = 1920, 1080
FONT_AR = "$FONT_AR"
FONT_EN = "$FONT_EN"
TITLE = "$TITLE"
SUBTITLE = "$SUBTITLE"
LABEL = "$LABEL"
COLOR_T = "$COLOR_T"
COLOR_S = "$COLOR_S"
COLOR_L = "$COLOR_L"
COLOR_NAME = "$COLOR_NAME"
FS_T = $FS_T
FS_S = $FS_S
FS_L = $FS_L
FS_NAME = $FS_NAME
Y_LIST = $Y_LIST
Y_TITLE = $Y_TITLE
Y_SUB = $Y_SUB
BG_TOP = ($BG_TOP_R, $BG_TOP_G, $BG_TOP_B)
BG_BOT = ($BG_BOT_R, $BG_BOT_G, $BG_BOT_B)
GLOW = ($GLOW_R, $GLOW_G, $GLOW_B, 65)
STREAMERS = "${STREAMERS_LIST}"

def load_font(path, size, weight=700):
    font = ImageFont.truetype(path, size)
    try:
        axes = font.get_variation_axes()
        if len(axes) == 1:
            font.set_variation_by_axes([weight])
        elif len(axes) == 2:
            font.set_variation_by_axes([0, weight])
        elif len(axes) == 3:
            font.set_variation_by_axes([0, weight, 0])
    except Exception:
        pass
    return font

bg = Image.new("RGB", (W, H))
d = ImageDraw.Draw(bg)
for y in range(H):
    t = y / H
    r = int(BG_TOP[0] + (BG_BOT[0] - BG_TOP[0]) * t)
    g = int(BG_TOP[1] + (BG_BOT[1] - BG_TOP[1]) * t)
    b = int(BG_TOP[2] + (BG_BOT[2] - BG_TOP[2]) * t)
    d.line([(0, y), (W, y)], fill=(r, g, b))

bg = bg.convert("RGBA")
glow = Image.new("RGBA", (W, H), (0, 0, 0, 0))
gd = ImageDraw.Draw(glow)
gd.ellipse([W//2 - 700, H//2 - 500, W//2 + 700, H//2 + 500], fill=GLOW)
glow = glow.filter(ImageFilter.GaussianBlur(250))
bg = Image.alpha_composite(bg, glow)

pattern = Image.new("RGBA", (W, H), (0, 0, 0, 0))
pd = ImageDraw.Draw(pattern)
size = 90
start_y = H - 320
row = 0
y = start_y
while y < H + size:
    x = (size // 2) if row % 2 else 0
    while x < W + size:
        pts = [(x, y - size//2), (x + size//2, y), (x, y + size//2), (x - size//2, y)]
        pd.polygon(pts, outline=(0, 0, 0, 220), width=2)
        x += size
    y += size // 2
    row += 1
mask = Image.new("L", (W, H), 0)
md = ImageDraw.Draw(mask)
for yy in range(start_y, H):
    a = min(255, int((yy - start_y) / 0.7))
    md.line([(0, yy), (W, yy)], fill=a)
pattern.putalpha(mask)
bg = Image.alpha_composite(bg, pattern)

texts = Image.new("RGBA", (W, H), (0, 0, 0, 0))
td = ImageDraw.Draw(texts)

def draw_outline(xy, text, font, fill, outline, w, direction, anchor):
    x, y = xy
    for dx in range(-w, w + 1):
        for dy in range(-w, w + 1):
            if dx*dx + dy*dy <= w*w:
                td.text((x+dx, y+dy), text, font=font, fill=outline, direction=direction, anchor=anchor)
    td.text((x, y), text, font=font, fill=fill, direction=direction, anchor=anchor)

font_ar = load_font(FONT_AR, FS_T, 700)
font_ar_sub = load_font(FONT_AR, FS_S, 700)
font_ar_label = load_font(FONT_AR, FS_L, 700)
font_en = load_font(FONT_EN, FS_NAME, 700)

items = [s.strip() for s in STREAMERS.split(',') if s.strip()]
total = len(items)
per_line = max(4, (total + 2) // 3)
lines = []
for i in range(0, total, per_line):
    lines.append(items[i:i+per_line])

label_w = td.textlength(LABEL, font=font_ar_label)
x_start = W - 40

if lines:
    line1 = " ◆ ".join(lines[0]).upper()
    draw_outline((x_start, Y_LIST), LABEL, font_ar_label, COLOR_L, "black", 2, "rtl", "ra")
    tx = x_start - label_w - 15
    for dx in range(-1, 2):
        for dy in range(-1, 2):
            if dx == 0 and dy == 0: continue
            td.text((tx+dx, Y_LIST+2+dy), line1, font=font_en, fill="black", direction="ltr", anchor="ra")
    td.text((tx, Y_LIST+2), line1, font=font_en, fill=COLOR_NAME, direction="ltr", anchor="ra")

for idx, line_items in enumerate(lines[1:], start=1):
    line = " ◆ ".join(line_items).upper()
    y_line = Y_LIST + idx * (FS_NAME + 20)
    for dx in range(-1, 2):
        for dy in range(-1, 2):
            if dx == 0 and dy == 0: continue
            td.text((x_start+dx, y_line+dy), line, font=font_en, fill="black", direction="ltr", anchor="ra")
    td.text((x_start, y_line), line, font=font_en, fill=COLOR_NAME, direction="ltr", anchor="ra")

title_bbox = td.textbbox((0, 0), TITLE, font=font_ar, direction="rtl")
tw = title_bbox[2] - title_bbox[0]
title_x = (W + tw) // 2
draw_outline((title_x, Y_TITLE), TITLE, font_ar, COLOR_T, "black", 4, "rtl", "ra")

sub_bbox = td.textbbox((0, 0), SUBTITLE, font=font_ar_sub, direction="rtl")
sw = sub_bbox[2] - sub_bbox[0]
sub_x = (W + sw) // 2
draw_outline((sub_x, Y_SUB), SUBTITLE, font_ar_sub, COLOR_S, "black", 3, "rtl", "ra")

final = Image.alpha_composite(bg, texts)
final.convert("RGB").save("/tmp/standby.png", "PNG")
print("OK")
PYEOF

echo "🎨 توليد صورة الانتظار..."
python3 /tmp/make_standby.py
[ ! -s /tmp/standby.png ] && { echo "❌ فشل الصورة"; exit 1; }

# ═════════ الشعار (إعادة ترميز) ═════════
echo "⬇️ الشعار..."
LOGO=""
if curl -sL --max-time 25 -A "Mozilla/5.0" "$LOGO_URL" -o /tmp/logo_raw.png 2>/dev/null; then
    if [ -s /tmp/logo_raw.png ]; then
        python3 - <<PYEOF
from PIL import Image
try:
    img = Image.open("/tmp/logo_raw.png").convert("RGBA")
    img.thumbnail(($LOGO_W * 2, $LOGO_W * 4), Image.LANCZOS)
    img.save("/tmp/logo.png", "PNG")
    print("OK")
except Exception as e:
    print(f"ERR: {e}")
    exit(1)
PYEOF
        [ -s /tmp/logo.png ] && { LOGO="/tmp/logo.png"; echo "✅ الشعار"; }
    fi
fi
[ -z "$LOGO" ] && echo "⚠️ بلا شعار"

# ═════════ المخرج (يقرأ UDP — لا ينهار) ═════════
start_output() {
    echo "🔗 اتصال مع Restream..."
    ffmpeg -y -hide_banner -loglevel warning -nostdin \
        -thread_queue_size 1024 \
        -fflags +genpts+igndts+discardcorrupt \
        -analyzeduration 5000000 -probesize 2000000 \
        -f mpegts -i "$UDP_IN" \
        -c copy -max_muxing_queue_size 4096 \
        -flvflags no_duration_filesize \
        -f flv "$RESTREAM_URL" >/tmp/out.log 2>&1 &
    OUT=$!
    sleep 5
    if ! kill -0 $OUT 2>/dev/null; then
        echo "❌ فشل المخرج:"; cat /tmp/out.log
        return 1
    fi
    echo "✅ المخرج (PID: $OUT)"
    return 0
}

# ═════════ منتج الانتظار (يرسل UDP) ═════════
start_producer_standby() {
    echo "⏳ شاشة الانتظار..."
    if [ -n "$LOGO" ]; then
        ffmpeg -y -hide_banner -loglevel warning -nostdin \
            -loop 1 -framerate $FPS -i /tmp/standby.png \
            -loop 1 -framerate $FPS -i "$LOGO" \
            -f lavfi -i "anullsrc=r=44100:cl=stereo" \
            -filter_complex "[0:v][1:v]overlay=x=(W-w)/2:y=H-h-$LOGO_BOTTOM:enable='lt(mod(t\,$LOGO_CYCLE)\,$LOGO_SHOW)'[v]" \
            -map "[v]" -map 2:a:0 \
            -c:v libx264 -preset ultrafast -tune zerolatency -pix_fmt yuv420p \
            -r $FPS -g $GOP \
            -c:a aac -b:a 128k -ar 44100 -ac 2 \
            -max_muxing_queue_size 4096 \
            -f mpegts "$UDP_OUT" >/tmp/prod.log 2>&1 &
    else
        ffmpeg -y -hide_banner -loglevel warning -nostdin \
            -loop 1 -framerate $FPS -i /tmp/standby.png \
            -f lavfi -i "anullsrc=r=44100:cl=stereo" \
            -map 0:v:0 -map 1:a:0 \
            -c:v libx264 -preset ultrafast -tune zerolatency -pix_fmt yuv420p \
            -r $FPS -g $GOP \
            -c:a aac -b:a 128k -ar 44100 -ac 2 \
            -max_muxing_queue_size 4096 \
            -f mpegts "$UDP_OUT" >/tmp/prod.log 2>&1 &
    fi
    PROD=$!
    sleep 4
    if ! kill -0 $PROD 2>/dev/null; then
        echo "❌ فشل المنتج:"; cat /tmp/prod.log; return 1
    fi
    echo "✅ منتج الانتظار (PID: $PROD)"
    return 0
}

start_producer_live() {
    local M3U8="$1"
    local NAME="$2"
    echo "🔴 منتج مباشر: $NAME"
    ffmpeg -y -hide_banner -loglevel warning -nostdin \
        -headers "User-Agent: $UA" \
        -reconnect 1 -reconnect_at_eof 1 -reconnect_streamed 1 \
        -reconnect_delay_max 5 \
        -analyzeduration 2000000 -probesize 2000000 \
        -fflags +genpts+igndts \
        -i "$M3U8" \
        -c:v copy -c:a aac -b:a 128k -ar 44100 -ac 2 \
        -max_muxing_queue_size 4096 \
        -muxdelay 0.1 -muxpreload 0.1 \
        -f mpegts "$UDP_OUT" >/tmp/prod.log 2>&1 &
    PROD=$!
    sleep 6
    if ! kill -0 $PROD 2>/dev/null; then
        echo "⚠️ فشل $NAME"; tail -n 5 /tmp/prod.log
        return 1
    fi
    echo "✅ منتج مباشر (PID: $PROD)"
    return 0
}

kill_producer() {
    [ -n "$PROD" ] && kill -9 $PROD 2>/dev/null
    [ -n "$PROD" ] && wait $PROD 2>/dev/null
    PROD=""
}

kill_all() {
    kill_producer
    [ -n "$OUT" ] && kill -9 $OUT 2>/dev/null
    [ -n "$OUT" ] && wait $OUT 2>/dev/null
    OUT=""
}

# ═════════ التشغيل ═════════
echo "🚀 بدء..."
start_producer_standby || exit 1
start_output || { kill_producer; exit 1; }

( if [ -n "$GH_TOKEN" ] && [ -n "$GITHUB_RUN_ID" ]; then
    OLD=$(timeout 10 gh run list --workflow="main.yml" --status=in_progress \
          --json databaseId -q ".[].databaseId" 2>/dev/null | \
          awk -v m="$GITHUB_RUN_ID" '$1 < m')
    for R in $OLD; do
        echo "🛑 إلغاء: $R"
        timeout 8 gh run cancel "$R" 2>/dev/null
    done
  fi ) >/tmp/cancel.log 2>&1 &

MODE="انتظار"; ACTIVE=""; ACTIVE_IDX=-1; TICK=0

while true; do
    if ! kill -0 $OUT 2>/dev/null; then
        echo "⚠️ المخرج مات — إعادة"
        kill_producer
        sleep 2
        start_output || exit 1
        sleep 3
        continue
    fi

    if ! kill -0 $PROD 2>/dev/null; then
        echo "⚠️ المنتج مات — إعادة"
        if [ "$MODE" = "مباشر" ] && [ -n "$ACTIVE" ]; then
            URL=$(timeout 20 streamlink --http-header "User-Agent=$UA" \
                  --stream-timeout 15 "https://kick.com/$ACTIVE" best \
                  --stream-url 2>/dev/null | grep -m1 "^http")
            if [ -n "$URL" ]; then
                start_producer_live "$URL" "$ACTIVE"
            else
                MODE="انتظار"; ACTIVE=""; ACTIVE_IDX=-1
                start_producer_standby
            fi
        else
            MODE="انتظار"
            start_producer_standby
        fi
        sleep 3
        continue
    fi

    FOUND=""; FOUND_URL=""; FOUND_IDX=-1
    LIMIT=${#STREAMERS[@]}
    if [ "$MODE" = "مباشر" ] && [ "$ACTIVE_IDX" -ge 0 ]; then
        LIMIT=$((ACTIVE_IDX + 1))
    fi

    for ((i=0; i<LIMIT; i++)); do
        S=$(echo "${STREAMERS[$i]}" | xargs); [ -z "$S" ] && continue
        URL=$(timeout 20 streamlink --http-header "User-Agent=$UA" \
              --stream-timeout 15 "https://kick.com/$S" best \
              --stream-url 2>/dev/null | grep -m1 "^http")
        if [ -n "$URL" ]; then
            FOUND="$S"; FOUND_URL="$URL"; FOUND_IDX=$i; break
        fi
    done

    if [ -n "$FOUND" ]; then
        if [ "$MODE" != "مباشر" ] || [ "$ACTIVE" != "$FOUND" ]; then
            echo "🎯 $FOUND"
            kill_producer
            sleep 1
            if start_producer_live "$FOUND_URL" "$FOUND"; then
                MODE="مباشر"; ACTIVE="$FOUND"; ACTIVE_IDX=$FOUND_IDX
                echo "✅ مباشر: $FOUND"
            else
                MODE="فارغ"
            fi
        fi
    else
        if [ "$MODE" != "انتظار" ]; then
            echo "⏳ انتظار"
            kill_producer
            sleep 1
            if start_producer_standby; then
                MODE="انتظار"; ACTIVE=""; ACTIVE_IDX=-1
            fi
        fi
    fi

    TICK=$((TICK+1))
    if [ $((TICK % 4)) -eq 0 ]; then
        OS=$(kill -0 $OUT 2>/dev/null && echo حي || echo ميت)
        PS=$(kill -0 $PROD 2>/dev/null && echo حي || echo ميت)
        echo "── [$(date -u +%H:%M:%S)] $MODE | OUT=$OS | PROD=$PS ──"
    fi
    sleep 15
done

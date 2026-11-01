#!/bin/bash
set +m

# ═══════════════════════════════════════════════════
#  Respect Broadcast — Absolute Zero-Gap Architecture
# ═══════════════════════════════════════════════════

TITLE_AR="RESPECT"
SUBTITLE_AR="جاري انتظار انضمام الستريمرز..."
COLOR_TITLE="#d4b3ff"
COLOR_SUB="#ffffff"
COLOR_NEON="#a64dff"
COLOR_TEXT="#ffffff"

STREAMERS_LIST="${STREAMERS_LIST:-drb7h,S5B,ABO8ALYY,ID7O,F1AISAL,xmusabrt,TAF86,abo_khrbaa,Peerless,Seagull,iMonkey_D,FHLWY,Hook,okb8,wolf,NASSER,Aymnalsatam,BoQamar,NEFOXD,RAYN,xya7ya,W1pey,AL_Hashidi,moustache,ALRND,klash,OGxHusni,Sayko_911,ZAiKRx}"

LOGO_URL="https://i.top4top.io/p_39264fv5g0.png"
FPS=60
GOP=120
UA="Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"

RESTREAM_KEY="${RESTREAM_KEY:-}"
[ -z "$RESTREAM_KEY" ] && { echo "❌ مفتاح Restream فارغ"; exit 1; }

RESTREAM_URL="rtmp://live.restream.io/live/$RESTREAM_KEY"
FIFO="/tmp/relay.ts"
WORKDIR="/tmp/respect_ui"

IFS=',' read -r -a STREAMERS <<< "$STREAMERS_LIST"
echo "🔢 عدد الستريمرز: ${#STREAMERS[@]}"
mkdir -p "$WORKDIR"

# ═══════════════════════════════════════════════════
#  توليد شاشة الانتظار
# ═══════════════════════════════════════════════════
cat > /tmp/make_ui.py <<PYEOF
from PIL import Image, ImageDraw, ImageFilter, ImageFont
import urllib.request, io, os

W, H = 1920, 1080
WORKDIR = "$WORKDIR"
FONT_AR = os.path.expanduser("~/.fonts/Cairo-var.ttf")
FONT_EN = os.path.expanduser("~/.fonts/Orbitron-var.ttf")

def load_font(path, size, weight=700):
    font = ImageFont.truetype(path, size)
    try:
        axes = font.get_variation_axes()
        if len(axes) == 1: font.set_variation_by_axes([weight])
        elif len(axes) == 2: font.set_variation_by_axes([0, weight])
        elif len(axes) == 3: font.set_variation_by_axes([0, weight, 0])
    except Exception: pass
    return font

bg = Image.new("RGB", (W, H))
d = ImageDraw.Draw(bg)
for y in range(H):
    t = y / H
    r = int(10 + (30 - 10) * t)
    g = int(2 + (10 - 2) * t)
    b = int(20 + (50 - 20) * t)
    d.line([(0, y), (W, y)], fill=(r, g, b))
bg = bg.convert("RGBA")

grid_bg = Image.new("RGBA", (W, H), (0, 0, 0, 0))
gd = ImageDraw.Draw(grid_bg)
for x in range(0, W, 100): gd.line([(x, 0), (x, H)], fill=(166, 77, 255, 15), width=1)
for y in range(0, H, 100): gd.line([(0, y), (W, y)], fill=(166, 77, 255, 15), width=1)
bg = Image.alpha_composite(bg, grid_bg)

font_title = load_font(FONT_EN, 120, 900)
tmp_t = Image.new("RGBA", (10, 10), (0,0,0,0))
bbox_t = ImageDraw.Draw(tmp_t).textbbox((0,0), "RESPECT", font=font_title)
tw, th = bbox_t[2]-bbox_t[0], bbox_t[3]-bbox_t[1]
title_img = Image.new("RGBA", (tw + 100, th + 100), (0,0,0,0))
td = ImageDraw.Draw(title_img)
td.text(((title_img.width - tw)//2, (title_img.height - th)//2), "RESPECT", font=font_title, fill=(212, 179, 255, 255))
glow = title_img.filter(ImageFilter.GaussianBlur(25))
title_img = Image.alpha_composite(glow, title_img)
bg.alpha_composite(title_img, ((W - title_img.width)//2, 150))

font_sub = load_font(FONT_AR, 50, 700)
sub_img = Image.new("RGBA", (1000, 100), (0,0,0,0))
sd = ImageDraw.Draw(sub_img)
bbox_s = sd.textbbox((0,0), "$SUBTITLE_AR", font=font_sub, direction="rtl")
sw = bbox_s[2] - bbox_s[0]
sd.text(((sub_img.width - sw)//2, 20), "$SUBTITLE_AR", font=font_sub, fill=(255, 255, 255), direction="rtl")
sub_glow = sub_img.filter(ImageFilter.GaussianBlur(10))
bg.alpha_composite(sub_glow, ((W - 1000)//2, 320))
bg.alpha_composite(sub_img, ((W - 1000)//2, 320))

items = [s.strip() for s in "$STREAMERS_LIST".split(',') if s.strip()]
font_list = load_font(FONT_EN, 24, 700)
COLS = 5
ROWS = (len(items) + COLS - 1) // COLS
CARD_W, CARD_H, GAP_X, GAP_Y = 300, 60, 30, 30
GRID_W = COLS * CARD_W + (COLS - 1) * GAP_X
GRID_H = ROWS * CARD_H + (ROWS - 1) * GAP_Y
grid_img = Image.new("RGBA", (GRID_W, GRID_H), (0,0,0,0))

for i, item in enumerate(items):
    row, col = i // COLS, i % COLS
    x, y = col * (CARD_W + GAP_X), row * (CARD_H + GAP_Y)
    card = Image.new("RGBA", (CARD_W, CARD_H), (0,0,0,0))
    cd = ImageDraw.Draw(card)
    cd.rounded_rectangle([(0,0), (CARD_W, CARD_H)], radius=10, fill=(255, 255, 255, 10), outline=(166, 77, 255, 100), width=2)
    bbox = cd.textbbox((0,0), item.upper(), font=font_list)
    cd.text(((CARD_W - (bbox[2]-bbox[0]))//2, (CARD_H - (bbox[3]-bbox[1]))//2 - bbox[1]), item.upper(), font=font_list, fill=(255, 255, 255))
    grid_img.alpha_composite(card, (x, y))

bg.alpha_composite(grid_img, ((W - GRID_W)//2, 500))

try:
    req = urllib.request.Request("$LOGO_URL", headers={"User-Agent": "Mozilla/5.0"})
    logo = Image.open(io.BytesIO(urllib.request.urlopen(req, timeout=25).read())).convert("RGBA")
    logo = logo.resize((120, int(logo.height * (120 / logo.width))), Image.LANCZOS)
    bg.alpha_composite(logo, ((W - 120)//2, 60))
except Exception:
    pass

bg.convert("RGB").save(f"{WORKDIR}/bg.png", "PNG")
PYEOF

echo "🎨 توليد شاشة الانتظار..."
python3 /tmp/make_ui.py
[ ! -s "$WORKDIR/bg.png" ] && { echo "❌ فشل توليد الصورة"; exit 1; }

# ═══════════════════════════════════════════════════
#  إعداد FIFO (لا يغلق أبداً)
# ═══════════════════════════════════════════════════
rm -f "$FIFO"
mkfifo "$FIFO"
exec 3<>"$FIFO"

cleanup() {
    kill -TERM "$OUT" 2>/dev/null
    kill -TERM "$PROD" 2>/dev/null
    pkill -f streamlink 2>/dev/null
    sleep 1
    kill -9 "$OUT" 2>/dev/null
    kill -9 "$PROD" 2>/dev/null
    exit 0
}
trap cleanup SIGTERM SIGINT

# ═══════════════════════════════════════════════════
#  المخرج (OUT) - يقرأ من الـ FIFO ولا يغلق أبداً
# ═══════════════════════════════════════════════════
start_output() {
    echo "🔗 الاتصال بـ Restream (مستحيل ينقطع)..."
    ffmpeg -y -hide_banner -loglevel warning -nostdin \
        -thread_queue_size 512 \
        -fflags +genpts+igndts+discardcorrupt \
        -err_detect ignore_err \
        -f mpegts -i "$FIFO" \
        -map 0:v:0 -map 0:a:0? -c:v copy \
        -c:a aac -b:a 160k -ar 44100 -ac 2 \
        -max_muxing_queue_size 4096 -flvflags no_duration_filesize \
        -f flv "$RESTREAM_URL" >/tmp/out.log 2>&1 &
    OUT=$!
    sleep 6
    if ! kill -0 "$OUT" 2>/dev/null; then
        echo "❌ فشل المخرج:"; tail -n 5 /tmp/out.log
        return 1
    fi
    echo "✅ المخرج شغال"
    return 0
}

# ═══════════════════════════════════════════════════
#  منتج البث (PROD - Live)
# ═══════════════════════════════════════════════════
start_producer_live() {
    local NAME="$1"
    echo "🔴 بث مباشر: $NAME (Pure Copy 0% CPU)"
    
    streamlink --http-header "User-Agent=$UA" "https://kick.com/$NAME" best --stdout 2>/dev/null | \
    ffmpeg -y -hide_banner -loglevel warning -nostdin \
        -thread_queue_size 512 \
        -fflags +genpts+igndts+discardcorrupt \
        -err_detect ignore_err \
        -i pipe:0 \
        -c:v copy -c:a aac -b:a 128k -ar 44100 -ac 2 -af aresample=async=1 \
        -max_muxing_queue_size 4096 -muxdelay 0.1 -muxpreload 0.1 \
        -f mpegts "$FIFO" >/tmp/prod.log 2>&1 &
    PROD=$!
}

# ═══════════════════════════════════════════════════
#  منتج الانتظار (PROD - Standby) - يغذي الـ FIFO فوراً
# ═══════════════════════════════════════════════════
start_producer_standby() {
    echo "⏳ شاشة الانتظار..."
    ffmpeg -y -hide_banner -loglevel warning -nostdin \
        -loop 1 -framerate 60 -i "$WORKDIR/bg.png" \
        -f lavfi -i "anullsrc=r=44100:cl=stereo" \
        -c:v libx264 -preset ultrafast -tune zerolatency -pix_fmt yuv420p -r 60 -g 120 \
        -c:a aac -b:a 128k -ar 44100 -ac 2 \
        -max_muxing_queue_size 4096 \
        -f mpegts "$FIFO" >/tmp/prod.log 2>&1 &
    PROD=$!
}

kill_producer() {
    if [ -n "$PROD" ]; then 
        kill -TERM "$PROD" 2>/dev/null; sleep 0.5; kill -9 "$PROD" 2>/dev/null; 
        wait "$PROD" 2>/dev/null; 
    fi
    PROD=""
}

# ═══════════════════════════════════════════════════
#  التشغيل الرئيسي 
# ═══════════════════════════════════════════════════
echo "🚀 بدء التشغيل..."
start_producer_standby
sleep 5
kill -0 "$PROD" 2>/dev/null || { echo "❌ المنتج مات"; cat /tmp/prod.log; exit 1; }

if [ -n "$GH_TOKEN" ] && [ -n "$GITHUB_RUN_ID" ]; then
    OLD=$(timeout 10 gh run list --workflow="main.yml" --status=in_progress --json databaseId -q ".[].databaseId" 2>/dev/null | awk -v m="$GITHUB_RUN_ID" '$1 < m')
    for R in $OLD; do timeout 8 gh run cancel "$R" 2>/dev/null; done
    sleep 2
fi

start_output || exit 1

MODE="STANDBY"
ACTIVE=""
TICK=0

while true; do
    # 1. التأكد من أن المخرج حي (أهم شيء)
    if ! kill -0 "$OUT" 2>/dev/null; then
        echo "⚠️ المخرج مات — إعادة فورية..."
        kill_producer; sleep 1; start_output || exit 1; sleep 1; continue
    fi

    # 2. إذا مات المنتج، نشغل شاشة الانتظار فوراً
    if ! kill -0 "$PROD" 2>/dev/null; then
        echo "⚠️ المنتج مات — إعادة تشغيل شاشة الانتظار..."
        start_producer_standby
        MODE="STANDBY"
        ACTIVE=""
        sleep 2; continue
    fi

    # 3. إذا كنا في وضع الانتظار، نبحث عن ستريمر
    if [ "$MODE" = "STANDBY" ]; then
        echo "🔍 البحث عن ستريمر بينما شاشة الانتظار تعمل..."
        FOUND=""
        for ((i=0; i<${#STREAMERS[@]}; i++)); do
            S=$(echo "${STREAMERS[$i]}" | xargs); [ -z "$S" ] && continue
            URL=$(timeout 3 streamlink --http-header "User-Agent=$UA" "https://kick.com/$S" best --stream-url 2>/dev/null | grep -m1 "^http")
            if [ -n "$URL" ]; then 
                FOUND="$S"
                break
            fi
        done

        if [ -n "$FOUND" ]; then
            echo "🎯 تم العثور على بث لـ: $FOUND (تحويل فوري)"
            kill_producer; sleep 0.2
            start_producer_live "$FOUND"
            sleep 2
            if kill -0 "$PROD" 2>/dev/null; then 
                MODE="LIVE"; ACTIVE="$FOUND"; echo "✅ مباشر: $FOUND"
            else 
                echo "⚠️ فشل التحويل، العودة للانتظار"
                start_producer_standby
                MODE="STANDBY"; ACTIVE=""
            fi
        fi
    fi

    # 4. إذا كنا في وضع البث المباشر، نتحقق من أن الستريمر لا يزال يبث
    if [ "$MODE" = "LIVE" ] && [ -n "$ACTIVE" ]; then
        URL=$(timeout 3 streamlink --http-header "User-Agent=$UA" "https://kick.com/$ACTIVE" best --stream-url 2>/dev/null | grep -m1 "^http")
        if [ -z "$URL" ]; then
            echo "⏳ توقف بث $ACTIVE — تحويل فوري لشاشة الانتظار..."
            kill_producer; sleep 0.2
            start_producer_standby
            MODE="STANDBY"; ACTIVE=""
        fi
    fi

    TICK=$((TICK + 1))
    if [ $((TICK % 10)) -eq 0 ]; then
        OS=$(kill -0 "$OUT" 2>/dev/null && echo "حي" || echo "ميت")
        PS=$(kill -0 "$PROD" 2>/dev/null && echo "حي" || echo "ميت")
        echo "── [$(date -u +%H:%M:%S)] $MODE | OUT=$OS | PROD=$PS ──"
    fi
    sleep 1
done

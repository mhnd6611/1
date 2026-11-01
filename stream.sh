#!/bin/bash
set +m

# ═══════════════════════════════════════════════════
#  Respect Broadcast — Legendary Architecture
# ═══════════════════════════════════════════════════

STREAMERS_LIST="${STREAMERS_LIST:-drb7h,S5B,ABO8ALYY,ID7O,F1AISAL,xmusabrt,TAF86,abo_khrbaa,Peerless,Seagull,iMonkey_D,FHLWY,Hook,okb8,wolf,NASSER,Aymnalsatam,BoQamar,NEFOXD,RAYN,xya7ya,W1pey,AL_Hashidi,moustache,ALRND,klash,OGxHusni,Sayko_911,ZAiKRx}"
LOGO_URL="https://i.top4top.io/p_39264fv5g0.png"
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
#  1. توليد وترميز شاشة الانتظار (مرة واحدة فقط)
# ═══════════════════════════════════════════════════
if [ ! -f "$WORKDIR/standby.ts" ]; then
    echo "🎨 توليد شاشة الانتظار وتشفيرها (مرة واحدة)..."
    
    # أ) توليد الصورة بـ Python
    cat > /tmp/make_ui.py <<'PYEOF'
from PIL import Image, ImageDraw, ImageFilter, ImageFont
import urllib.request, io, os

W, H = 1920, 1080
WORKDIR = os.environ["WORKDIR"]
FONT_AR = os.path.expanduser("~/.fonts/Cairo-var.ttf")
FONT_EN = os.path.expanduser("~/.fonts/Orbitron-var.ttf")
SUBTITLE = os.environ.get("SUBTITLE_AR", "جاري انتظار انضمام الستريمرز...")
LOGO_URL = os.environ.get("LOGO_URL")
STREAMERS = [s.strip() for s in os.environ.get("STREAMERS_LIST", "").split(',') if s.strip()]

def load_font(path, size, weight=700):
    try:
        font = ImageFont.truetype(path, size)
        axes = font.get_variation_axes()
        if len(axes) == 1: font.set_variation_by_axes([weight])
        elif len(axes) == 2: font.set_variation_by_axes([0, weight])
        return font
    except: return ImageFont.load_default()

bg = Image.new("RGB", (W, H))
d = ImageDraw.Draw(bg)
for y in range(H):
    t = y / H
    d.line([(0, y), (W, y)], fill=(int(10+20*t), int(2+8*t), int(20+30*t)))
bg = bg.convert("RGBA")

grid = Image.new("RGBA", (W, H), (0,0,0,0))
gd = ImageDraw.Draw(grid)
for x in range(0, W, 100): gd.line([(x,0),(x,H)], fill=(166,77,255,15), width=1)
for y in range(0, H, 100): gd.line([(0,y),(W,y)], fill=(166,77,255,15), width=1)
bg = Image.alpha_composite(bg, grid)

font_title = load_font(FONT_EN, 120, 900)
t_img = Image.new("RGBA", (800, 200), (0,0,0,0))
ImageDraw.Draw(t_img).text((50,50), "RESPECT", font=font_title, fill=(212,179,255,255))
bg.alpha_composite(t_img.filter(ImageFilter.GaussianBlur(20)), ((W-800)//2, 120))
bg.alpha_composite(t_img, ((W-800)//2, 120))

font_sub = load_font(FONT_AR, 45, 700)
s_img = Image.new("RGBA", (1000, 100), (0,0,0,0))
ImageDraw.Draw(s_img).text((100,20), SUBTITLE, font=font_sub, fill=(255,255,255))
bg.alpha_composite(s_img, ((W-1000)//2, 300))

font_list = load_font(FONT_EN, 22, 700)
COLS, CARD_W, CARD_H, GAP_X, GAP_Y = 5, 300, 55, 25, 25
ROWS = (len(STREAMERS) + COLS - 1) // COLS
GRID_W = COLS * CARD_W + (COLS - 1) * GAP_X
GRID_H = ROWS * CARD_H + (ROWS - 1) * GAP_Y
grid_img = Image.new("RGBA", (GRID_W, GRID_H), (0,0,0,0))

for i, item in enumerate(STREAMERS):
    row, col = i // COLS, i % COLS
    x, y = col * (CARD_W + GAP_X), row * (CARD_H + GAP_Y)
    card = Image.new("RGBA", (CARD_W, CARD_H), (0,0,0,0))
    cd = ImageDraw.Draw(card)
    cd.rounded_rectangle([(0,0), (CARD_W, CARD_H)], radius=8, fill=(255,255,255,10), outline=(166,77,255,120), width=2)
    cd.text((20, 15), item.upper(), font=font_list, fill=(255,255,255))
    grid_img.alpha_composite(card, (x, y))

bg.alpha_composite(grid_img, ((W-GRID_W)//2, 440))

try:
    req = urllib.request.Request(LOGO_URL, headers={"User-Agent": "Mozilla/5.0"})
    logo = Image.open(io.BytesIO(urllib.request.urlopen(req, timeout=10).read())).convert("RGBA")
    logo = logo.resize((100, int(logo.height * (100 / logo.width))), Image.LANCZOS)
    bg.alpha_composite(logo, ((W-100)//2, 40))
except: pass

bg.convert("RGB").save(f"{WORKDIR}/bg.png", "PNG")
PYEOF
    WORKDIR="$WORKDIR" SUBTITLE_AR="جاري انتظار انضمام الستريمرز..." LOGO_URL="$LOGO_URL" STREAMERS_LIST="$STREAMERS_LIST" python3 /tmp/make_ui.py

    # ب) ترميز الصورة كفيديو 4 ثواني (مرة واحدة فقط)
    if [ -s "$WORKDIR/bg.png" ]; then
        echo "🎬 تشفير شاشة الانتظار (مرة واحدة)..."
        ffmpeg -y -hide_banner -loglevel warning -loop 1 -framerate 30 -i "$WORKDIR/bg.png" \
            -f lavfi -i "anullsrc=r=44100:cl=stereo" -t 4 \
            -c:v libx264 -preset veryfast -pix_fmt yuv420p -g 30 -c:a aac -b:a 128k -ar 44100 -ac 2 -shortest \
            -f mpegts "$WORKDIR/standby.ts"
    fi
fi

# التحقق من وجود الفيديو
[ ! -s "$WORKDIR/standby.ts" ] && { echo "❌ فشل توليد standby.ts"; exit 1; }

# ═══════════════════════════════════════════════════
#  إعداد FIFO والتنظيف
# ═══════════════════════════════════════════════════
rm -f "$FIFO"
mkfifo "$FIFO"
exec 3<>"$FIFO"

cleanup() {
    echo "🧹 تنظيف..."
    kill -TERM "$OUT" 2>/dev/null
    kill -TERM -- -"$PROD" 2>/dev/null # قتل مجموعة العمليات كاملة
    pkill -f streamlink 2>/dev/null
    sleep 1
    kill -9 "$OUT" 2>/dev/null
    kill -9 -- -"$PROD" 2>/dev/null
    exit 0
}
trap cleanup SIGTERM SIGINT

# ═══════════════════════════════════════════════════
#  المخرج (OUT) - البوابة لريستريم
# ═══════════════════════════════════════════════════
start_output() {
    echo "🔗 الاتصال بـ Restream..."
    ffmpeg -y -hide_banner -loglevel warning -nostdin \
        -thread_queue_size 1024 \
        -fflags +genpts+igndts+discardcorrupt \
        -err_detect ignore_err \
        -f mpegts -i "$FIFO" \
        -map 0:v:0 -map 0:a:0? -c:v copy \
        -c:a copy \
        -max_muxing_queue_size 4096 -flvflags no_duration_filesize \
        -f flv "$RESTREAM_URL" >/tmp/out.log 2>&1 &
    OUT=$!
    sleep 5
    kill -0 "$OUT" 2>/dev/null || { echo "❌ فشل المخرج"; return 1; }
    echo "✅ المخرج شغال"
    return 0
}

# ═══════════════════════════════════════════════════
#  منتج الانتظار (Standby) - نسخ مباشر (0% CPU)
# ═══════════════════════════════════════════════════
start_producer_standby() {
    echo "⏳ شاشة الانتظار..."
    setsid ffmpeg -y -hide_banner -loglevel warning -nostdin \
        -re -stream_loop -1 -i "$WORKDIR/standby.ts" \
        -c copy -f mpegts "$FIFO" >/tmp/prod.log 2>&1 &
    PROD=$!
}

# ═══════════════════════════════════════════════════
#  منتج البث المباشر (Live) - معالج بأمان
# ═══════════════════════════════════════════════════
start_producer_live() {
    local NAME="$1"
    echo "🔴 بث مباشر: $NAME"
    
    setsid bash -c "streamlink --http-header 'User-Agent=$UA' 'https://kick.com/$NAME' best --stdout 2>/dev/null | ffmpeg -y -hide_banner -loglevel warning -nostdin -thread_queue_size 1024 -fflags +genpts+igndts+discardcorrupt -err_detect ignore_err -i pipe:0 -c:v copy -c:a aac -b:a 128k -ar 44100 -ac 2 -max_muxing_queue_size 4096 -muxdelay 0.1 -muxpreload 0.1 -f mpegts '$FIFO' >/tmp/prod.log 2>&1" &
    PROD=$!
}

kill_producer() {
    if [ -n "$PROD" ]; then 
        kill -TERM -- -"$PROD" 2>/dev/null
        sleep 0.5
        kill -9 -- -"$PROD" 2>/dev/null
        wait "$PROD" 2>/dev/null
    fi
    PROD=""
}

# ═══════════════════════════════════════════════════
#  التشغيل الرئيسي
# ═══════════════════════════════════════════════════
echo "🚀 بدء التشغيل..."
start_producer_standby
sleep 3
kill -0 "$PROD" 2>/dev/null || { echo "❌ فشل تشغيل الانتظار"; cat /tmp/prod.log; exit 1; }

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
    # 1. التحقق من المخرج
    if ! kill -0 "$OUT" 2>/dev/null; then
        echo "⚠️ المخرج مات — إعادة..."
        kill_producer; sleep 1; start_output || exit 1; sleep 1; continue
    fi

    # 2. التحقق من المنتج
    if ! kill -0 "$PROD" 2>/dev/null; then
        echo "⚠️ المنتج مات — تشغيل الانتظار..."
        start_producer_standby
        MODE="STANDBY"; ACTIVE=""
        sleep 2; continue
    fi

    # 3. البحث عن ستريمر (بالتسلسل السريع 3 ثواني)
    if [ "$MODE" = "STANDBY" ]; then
        FOUND=""
        for ((i=0; i<${#STREAMERS[@]}; i++)); do
            S=$(echo "${STREAMERS[$i]}" | xargs); [ -z "$S" ] && continue
            URL=$(timeout 3 streamlink --http-header "User-Agent=$UA" "https://kick.com/$S" best --stream-url 2>/dev/null | grep -m1 "^http")
            if [ -n "$URL" ]; then FOUND="$S"; break; fi
        done

        if [ -n "$FOUND" ]; then
            echo "🎯 وجدنا: $FOUND (تحويل...)"
            kill_producer; sleep 0.2
            start_producer_live "$FOUND"
            sleep 3
            if kill -0 "$PROD" 2>/dev/null; then 
                MODE="LIVE"; ACTIVE="$FOUND"; echo "✅ مباشر: $FOUND"
            else 
                echo "⚠️ فشل البث، عودة للانتظار"
                start_producer_standby; MODE="STANDBY"; ACTIVE=""
            fi
        fi
    fi

    # 4. التحقق من استمرار البث
    if [ "$MODE" = "LIVE" ] && [ -n "$ACTIVE" ]; then
        URL=$(timeout 3 streamlink --http-header "User-Agent=$UA" "https://kick.com/$ACTIVE" best --stream-url 2>/dev/null | grep -m1 "^http")
        if [ -z "$URL" ]; then
            echo "⏳ توقف $ACTIVE — عودة للانتظار..."
            kill_producer; sleep 0.2
            start_producer_standby
            MODE="STANDBY"; ACTIVE=""
        fi
    fi

    TICK=$((TICK + 1))
    if [ $((TICK % 10)) -eq 0 ]; then
        OS=$(kill -0 "$OUT" 2>/dev/null && echo "حي" || echo "ميت")
        PS=$(kill -0 "$PROD" 2>/dev/null && echo "حي" || echo "ميت")
        echo "── [$(date -u +%H:%M:%S)] $MODE | $ACTIVE | OUT=$OS | PROD=$PS ──"
    fi
    sleep 2
done

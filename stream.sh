#!/bin/bash
set +m

# ═══════════════════════════════════════════════════
#  Respect Broadcast — Kick → Restream (Cyberpunk Tech UI)
# ═══════════════════════════════════════════════════

# ─── الإعدادات ───
TITLE_AR="RESPECT"
SUBTITLE_AR="جاري انتظار ستريمرز ريسبكت ..."
LABEL_AR="ACTIVE ROSTER"

COLOR_TITLE="#d4b3ff"
COLOR_SUB="#a64dff"
COLOR_NEON="#a64dff"
COLOR_TEXT="#ffffff"

BG_TOP_R=5; BG_TOP_G=2;  BG_TOP_B=10
BG_BOT_R=15; BG_BOT_G=5; BG_BOT_B=30

FONT_SIZE_TITLE=130
FONT_SIZE_SUB=40
FONT_SIZE_LIST=22

Y_TITLE=200
Y_SUB=340
Y_GRID_START=430

# القائمة الجديدة (26 ستريمر)
STREAMERS_LIST="${STREAMERS_LIST:-drb7h,S5B,ABO8ALYY,ID7O,F1AISAL,xmusabrt,TAF86,abo_khrbaa,Peerless,Seagull,iMonkey_D,FHLWY,Hook,okb8,wolf,NASSER,Aymnalsatam,BoQamar,NEFOXD,RAYN,xya7ya,W1pey,ALRND,klash,Sayko_911,ZAiKRx}"

LOGO_URL="https://i.top4top.io/p_39264fv5g0.png"
LOGO_W=140
Y_LOGO=40

FPS=60
GOP=120

UA="Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"
# ═══════════════════════════════════════════════════

RESTREAM_KEY="${RESTREAM_KEY:-}"
[ -z "$RESTREAM_KEY" ] && { echo "❌ مفتاح Restream فارغ"; exit 1; }
[ -z "$STREAMERS_LIST" ] && { echo "❌ قائمة الستريمرز فارغة"; exit 1; }

RESTREAM_URL="rtmp://live.restream.io/live/$RESTREAM_KEY"
FIFO="/tmp/relay.ts"
WORKDIR="/tmp/respect_cyber_ui"

# ─── الخطوط ───
FONT_AR=""
for C in "$HOME/.fonts/Cairo-var.ttf" "$HOME/.fonts/NotoSansArabic-Bold.ttf"; do
    [ -s "$C" ] && { FONT_AR="$C"; break; }
done
[ -z "$FONT_AR" ] && { echo "❌ لا يوجد خط عربي"; exit 1; }

FONT_EN="$HOME/.fonts/Orbitron-var.ttf"
[ ! -s "$FONT_EN" ] && { echo "❌ لا يوجد Orbitron"; exit 1; }

IFS=',' read -r -a STREAMERS <<< "$STREAMERS_LIST"
echo "🔢 عدد الستريمرز: ${#STREAMERS[@]}"

mkdir -p "$WORKDIR"

# ═══════════════════════════════════════════════════
#  توليد الصور (Cyberpunk Style)
# ═══════════════════════════════════════════════════
cat > /tmp/make_respect.py <<PYEOF
from PIL import Image, ImageDraw, ImageFilter, ImageFont
import urllib.request, io, os

W, H = 1920, 1080
WORKDIR = "$WORKDIR"
FONT_AR = "$FONT_AR"
FONT_EN = "$FONT_EN"
TITLE = "$TITLE_AR"
SUBTITLE = "$SUBTITLE_AR"
LABEL = "$LABEL_AR"
C_TITLE = "$COLOR_TITLE"
C_SUB = "$COLOR_SUB"
C_NEON = "$COLOR_NEON"
C_TEXT = "$COLOR_TEXT"
FS_TITLE = $FONT_SIZE_TITLE
FS_SUB = $FONT_SIZE_SUB
FS_LIST = $FONT_SIZE_LIST
Y_TITLE = $Y_TITLE
Y_SUB = $Y_SUB
Y_GRID_START = $Y_GRID_START
BG_TOP = ($BG_TOP_R, $BG_TOP_G, $BG_TOP_B)
BG_BOT = ($BG_BOT_R, $BG_BOT_G, $BG_BOT_B)
LOGO_URL = "$LOGO_URL"
LOGO_W = $LOGO_W
STREAMERS_STR = "$STREAMERS_LIST"

def load_font(path, size, weight=700):
    font = ImageFont.truetype(path, size)
    try:
        axes = font.get_variation_axes()
        if len(axes) == 1: font.set_variation_by_axes([weight])
        elif len(axes) == 2: font.set_variation_by_axes([0, weight])
        elif len(axes) == 3: font.set_variation_by_axes([0, weight, 0])
    except Exception: pass
    return font

# 1) الخلفية (شبكة تكنولوجية)
bg = Image.new("RGB", (W, H))
d = ImageDraw.Draw(bg)
for y in range(H):
    t = y / H
    r = int(BG_TOP[0] + (BG_BOT[0] - BG_TOP[0]) * t)
    g = int(BG_TOP[1] + (BG_BOT[1] - BG_TOP[1]) * t)
    b = int(BG_TOP[2] + (BG_BOT[2] - BG_TOP[2]) * t)
    d.line([(0, y), (W, y)], fill=(r, g, b))
bg = bg.convert("RGBA")

# خطوط الشبكة
grid_bg = Image.new("RGBA", (W, H), (0, 0, 0, 0))
gd = ImageDraw.Draw(grid_bg)
for x in range(0, W, 80): gd.line([(x, 0), (x, H)], fill=(166, 77, 255, 20), width=1)
for y in range(0, H, 80): gd.line([(0, y), (W, y)], fill=(166, 77, 255, 20), width=1)
bg = Image.alpha_composite(bg, grid_bg)

# ✅ إصلاح الخطأ: حفظ صورة الخلفية
bg.convert("RGB").save(f"{WORKDIR}/bg.png", "PNG")

# 2) نص العنوان (RESPECT)
font_title = load_font(FONT_EN, FS_TITLE, 900)
tmp_t = Image.new("RGBA", (10, 10), (0,0,0,0))
bbox_t = ImageDraw.Draw(tmp_t).textbbox((0,0), TITLE, font=font_title)
tw, th = bbox_t[2]-bbox_t[0], bbox_t[3]-bbox_t[1]

title_img = Image.new("RGBA", (tw + 100, th + 100), (0,0,0,0))
td = ImageDraw.Draw(title_img)
# توهج
td.text(((title_img.width - tw)//2, (title_img.height - th)//2), TITLE, font=font_title, fill=(212, 179, 255, 255))
glow = title_img.filter(ImageFilter.GaussianBlur(20))
title_img = Image.alpha_composite(glow, title_img)
title_img.save(f"{WORKDIR}/title.png", "PNG")

# 3) النص الفرعي
font_sub = load_font(FONT_AR, FS_SUB, 700)
sub_img = Image.new("RGBA", (1000, 100), (0,0,0,0))
sd = ImageDraw.Draw(sub_img)
bbox_s = sd.textbbox((0,0), SUBTITLE, font=font_sub, direction="rtl")
sw = bbox_s[2] - bbox_s[0]
sd.text(((sub_img.width - sw)//2, 20), SUBTITLE, font=font_sub, fill=C_SUB, direction="rtl")
sub_img.save(f"{WORKDIR}/sub.png", "PNG")

# 4) قائمة الستريمرز (شبكة 6 أعمدة)
items = [s.strip() for s in STREAMERS_STR.split(',') if s.strip()]
font_list = load_font(FONT_EN, FS_LIST, 700)

COLS = 6
ROWS = (len(items) + COLS - 1) // COLS
CARD_W = 260
CARD_H = 60
GAP_X = 20
GAP_Y = 25
GRID_W = COLS * CARD_W + (COLS - 1) * GAP_X
GRID_H = ROWS * CARD_H + (ROWS - 1) * GAP_Y

grid_img = Image.new("RGBA", (GRID_W, GRID_H), (0,0,0,0))

for i, item in enumerate(items):
    row = i // COLS
    col = i % COLS
    x = col * (CARD_W + GAP_X)
    y = row * (CARD_H + GAP_Y)
    
    card = Image.new("RGBA", (CARD_W, CARD_H), (0,0,0,0))
    cd = ImageDraw.Draw(card)
    
    # تصميم الأقواس التكنولوجية (Neon Brackets)
    cd.line([(0, 15), (0, 0), (15, 0)], fill=C_NEON, width=3) # أعلى يسار
    cd.line([(CARD_W-15, CARD_H), (CARD_W, CARD_H), (CARD_W, CARD_H-15)], fill=C_NEON, width=3) # أسفل يمين
    cd.line([(0, CARD_H-15), (0, CARD_H), (15, CARD_H)], fill=(255,255,255,50), width=2) # أسفل يسار (خفيف)
    cd.line([(CARD_W-15, 0), (CARD_W, 0), (CARD_W, 15)], fill=(255,255,255,50), width=2) # أعلى يمين (خفيف)
    
    bbox = cd.textbbox((0,0), item.upper(), font=font_list)
    tw = bbox[2] - bbox[0]
    tx = (CARD_W - tw) // 2
    ty = (CARD_H - (bbox[3]-bbox[1])) // 2 - bbox[1]
    
    cd.text((tx, ty), item.upper(), font=font_list, fill=C_TEXT)
    grid_img.alpha_composite(card, (x, y))

grid_img.save(f"{WORKDIR}/grid.png", "PNG")

# 5) الشعار
try:
    req = urllib.request.Request(LOGO_URL, headers={"User-Agent": "Mozilla/5.0"})
    logo_data = urllib.request.urlopen(req, timeout=25).read()
    logo = Image.open(io.BytesIO(logo_data)).convert("RGBA")
    ratio = LOGO_W / logo.width
    logo = logo.resize((LOGO_W, int(logo.height * ratio)), Image.LANCZOS)
    logo.save(f"{WORKDIR}/logo.png", "PNG")
except Exception as e:
    print(f"⚠️ logo fail: {e}")
    Image.new("RGBA", (LOGO_W, LOGO_W), (0,0,0,0)).save(f"{WORKDIR}/logo.png", "PNG")

# 6) تجميع المحتوى الثابت
content = Image.new("RGBA", (W, H), (0,0,0,0))
title_img = Image.open(f"{WORKDIR}/title.png").convert("RGBA")
sub_img = Image.open(f"{WORKDIR}/sub.png").convert("RGBA")

content.alpha_composite(title_img, ((W - title_img.width)//2, Y_TITLE - title_img.height//2))
content.alpha_composite(sub_img, ((W - sub_img.width)//2, Y_SUB - sub_img.height//2))
content.alpha_composite(grid_img, ((W - GRID_W)//2, Y_GRID_START))
content.save(f"{WORKDIR}/content.png", "PNG")

print("✅ اكتمل التوليد")
PYEOF

echo "🎨 توليد صور الشاشة..."
python3 /tmp/make_respect.py
[ ! -s "$WORKDIR/bg.png" ] && { echo "❌ فشل التوليد"; exit 1; }

# ═══════════════════════════════════════════════════
#  FIFO & Shutdown
# ═══════════════════════════════════════════════════
rm -f "$FIFO"
mkfifo "$FIFO"
exec 3<>"$FIFO"

cleanup() {
    echo "🛑 إغلاق آمن..."
    kill -TERM "$OUT" 2>/dev/null
    kill -TERM "$PROD" 2>/dev/null
    sleep 1
    kill -9 "$OUT" 2>/dev/null
    kill -9 "$PROD" 2>/dev/null
    exit 0
}
trap cleanup SIGTERM SIGINT

# ═══════════════════════════════════════════════════
#  منتج شاشة الانتظار (Cyberpunk Animations)
# ═══════════════════════════════════════════════════
start_producer_standby() {
    echo "⏳ تشغيل الشاشة (Cyberpunk Mode)..."
    ffmpeg -y -hide_banner -loglevel warning -nostdin \
        -loop 1 -framerate $FPS -i "$WORKDIR/bg.png" \
        -loop 1 -framerate $FPS -i "$WORKDIR/content.png" \
        -loop 1 -framerate $FPS -i "$WORKDIR/logo.png" \
        -f lavfi -i "color=c=#a64dff@0.15:s=1920x4,format=rgba" \
        -f lavfi -i "anullsrc=r=44100:cl=stereo" \
        -filter_complex "\
[0:v]scale=iw*1.05:ih*1.05,crop=1920:1080[bg];\
[1:v]format=rgba[content];\
[bg][content]overlay=x=(W-w)/2:y='(H-h)/2 + 10*sin(2*PI*t/8)':eval=frame[v1];\
[3:v]format=rgba[scanner];\
[v1][scanner]overlay=x=0:y='mod(t*300\,H+100)-50'[v2];\
[2:v]format=rgba,scale='iw*(1+0.05*sin(2*PI*t/3))':-1:eval=frame[logo];\
[v2][logo]overlay=x=(W-w)/2:y=$Y_LOGO[vout]" \
        -map "[vout]" -map 4:a:0 \
        -c:v libx264 -preset ultrafast -tune zerolatency \
        -pix_fmt yuv420p -r $FPS -g $GOP \
        -c:a aac -b:a 128k -ar 44100 -ac 2 \
        -max_muxing_queue_size 4096 \
        -f mpegts "$FIFO" >/tmp/prod.log 2>&1 &
    PROD=$!
}

# ═══════════════════════════════════════════════════
#  منتج البث المباشر
# ═══════════════════════════════════════════════════
start_producer_live() {
    local M3U8="$1"
    local NAME="$2"
    echo "🔴 منتج مباشر: $NAME"
    ffmpeg -y -hide_banner -loglevel warning -nostdin \
        -headers "User-Agent: $UA" \
        -reconnect 1 -reconnect_at_eof 1 -reconnect_streamed 1 \
        -reconnect_delay_max 5 \
        -rw_timeout 10000000 \
        -analyzeduration 1000000 -probesize 1000000 \
        -fflags +genpts+igndts \
        -i "$M3U8" \
        -c:v copy -c:a aac -b:a 128k -ar 44100 -ac 2 \
        -max_muxing_queue_size 4096 \
        -muxdelay 0.1 -muxpreload 0.1 \
        -f mpegts "$FIFO" >/tmp/prod.log 2>&1 &
    PROD=$!
}

# ═══════════════════════════════════════════════════
#  المخرج (Zero Downtime)
# ═══════════════════════════════════════════════════
start_output() {
    echo "🔗 الاتصال بـ Restream..."
    ffmpeg -y -hide_banner -loglevel warning -nostdin \
        -thread_queue_size 512 \
        -f mpegts -i "$FIFO" \
        -map 0:v:0 -map 0:a:0? \
        -c:v libx264 -preset ultrafast -tune zerolatency \
        -pix_fmt yuv420p -g $GOP -r $FPS \
        -b:v 6500k -maxrate 7000k -bufsize 14000k \
        -c:a aac -b:a 160k -ar 44100 -ac 2 \
        -max_muxing_queue_size 4096 \
        -flvflags no_duration_filesize \
        -rw_timeout 5000000 \
        -f flv "$RESTREAM_URL" >/tmp/out.log 2>&1 &
    OUT=$!
    sleep 6
    if ! kill -0 "$OUT" 2>/dev/null; then
        echo "❌ فشل المخرج:"; tail -n 10 /tmp/out.log
        return 1
    fi
    echo "✅ المخرج شغال (PID: $OUT)"
    return 0
}

kill_producer() {
    if [ -n "$PROD" ]; then
        kill -TERM "$PROD" 2>/dev/null
        sleep 1
        kill -9 "$PROD" 2>/dev/null
        wait "$PROD" 2>/dev/null
    fi
    PROD=""
}

# ═══════════════════════════════════════════════════
#  التشغيل
# ═══════════════════════════════════════════════════
echo "🚀 بدء التشغيل..."

start_producer_standby
sleep 5
kill -0 "$PROD" 2>/dev/null || { echo "❌ المنتج مات"; cat /tmp/prod.log; exit 1; }

if [ -n "$GH_TOKEN" ] && [ -n "$GITHUB_RUN_ID" ]; then
    echo "🔍 البحث عن الرنات القديمة لإلغائها..."
    OLD=$(timeout 10 gh run list --workflow="main.yml" --status=in_progress \
          --json databaseId -q ".[].databaseId" 2>/dev/null | \
          awk -v m="$GITHUB_RUN_ID" '$1 < m')
    for R in $OLD; do
        timeout 8 gh run cancel "$R" 2>/dev/null
    done
    sleep 2
fi

start_output || exit 1

MODE="STANDBY"
ACTIVE=""
ACTIVE_IDX=-1
TICK=0

while true; do
    if ! kill -0 "$OUT" 2>/dev/null; then
        echo "⚠️ المخرج مات — إعادة..."
        kill_producer; sleep 2; start_output || exit 1; sleep 2; continue
    fi

    if ! kill -0 "$PROD" 2>/dev/null; then
        echo "⚠️ المنتج مات — إعادة..."
        if [ "$MODE" = "LIVE" ] && [ -n "$ACTIVE" ]; then
            URL=$(timeout 20 streamlink --http-header "User-Agent=$UA" \
                  --stream-timeout 15 "https://kick.com/$ACTIVE" best \
                  --stream-url 2>/dev/null | grep -m1 "^http")
            if [ -n "$URL" ]; then start_producer_live "$URL" "$ACTIVE"
            else start_producer_standby; MODE="STANDBY"; ACTIVE=""; ACTIVE_IDX=-1; fi
        else
            start_producer_standby; MODE="STANDBY"
        fi
        sleep 3; continue
    fi

    FOUND=""; FOUND_URL=""; FOUND_IDX=-1
    LIMIT=${#STREAMERS[@]}
    if [ "$MODE" = "LIVE" ] && [ "$ACTIVE_IDX" -ge 0 ]; then LIMIT=$((ACTIVE_IDX + 1)); fi

    for ((i=0; i<LIMIT; i++)); do
        S=$(echo "${STREAMERS[$i]}" | xargs)
        [ -z "$S" ] && continue
        URL=$(timeout 20 streamlink --http-header "User-Agent=$UA" \
              --stream-timeout 15 "https://kick.com/$S" best \
              --stream-url 2>/dev/null | grep -m1 "^http")
        if [ -n "$URL" ]; then FOUND="$S"; FOUND_URL="$URL"; FOUND_IDX=$i; break; fi
    done

    if [ -n "$FOUND" ]; then
        if [ "$MODE" != "LIVE" ] || [ "$ACTIVE" != "$FOUND" ]; then
            echo "🎯 التحويل إلى: $FOUND"
            kill_producer; sleep 1
            start_producer_live "$FOUND_URL" "$FOUND"
            sleep 6
            if kill -0 "$PROD" 2>/dev/null; then
                MODE="LIVE"; ACTIVE="$FOUND"; ACTIVE_IDX=$FOUND_IDX
                echo "✅ مباشر: $FOUND"
            else
                MODE="NONE"
            fi
        fi
    else
        if [ "$MODE" != "STANDBY" ]; then
            echo "⏳ لا يوجد بث — عودة للانتظار"
            kill_producer; sleep 1; start_producer_standby; sleep 3
            MODE="STANDBY"; ACTIVE=""; ACTIVE_IDX=-1
        fi
    fi

    TICK=$((TICK + 1))
    if [ $((TICK % 4)) -eq 0 ]; then
        OS=$(kill -0 "$OUT" 2>/dev/null && echo "حي" || echo "ميت")
        PS=$(kill -0 "$PROD" 2>/dev/null && echo "حي" || echo "ميت")
        echo "── [$(date -u +%H:%M:%S)] $MODE | OUT=$OS | PROD=$PS ──"
    fi
    sleep 15
done

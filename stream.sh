#!/bin/bash
set +m

# ═══════════════════════════════════════════════════
#  Respect Broadcast — 24/7 Zero-Downtime (1080p Fixed)
# ═══════════════════════════════════════════════════

TITLE_AR="RESPECT"
SUBTITLE_AR="جاري انتظار انضمام الستريمرز..."
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

STREAMERS_LIST="${STREAMERS_LIST:-drb7h,S5B,ABO8ALYY,ID7O,F1AISAL,xmusabrt,TAF86,abo_khrbaa,Peerless,Seagull,iMonkey_D,FHLWY,Hook,okb8,wolf,NASSER,Aymnalsatam,BoQamar,NEFOXD,RAYN,xya7ya,W1pey,ALRND,klash,Sayko_911,ZAiKRx}"

LOGO_URL="https://i.top4top.io/p_39264fv5g0.png"
LOGO_W=140
Y_LOGO=40

FPS=60
GOP=120
UA="Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"

RESTREAM_KEY="${RESTREAM_KEY:-}"
[ -z "$RESTREAM_KEY" ] && { echo "❌ مفتاح Restream فارغ"; exit 1; }

RESTREAM_URL="rtmp://live.restream.io/live/$RESTREAM_KEY"
FIFO="/tmp/relay.ts"
WORKDIR="/tmp/respect_cyber_ui"

FONT_AR=""
for C in "$HOME/.fonts/Cairo-var.ttf" "$HOME/.fonts/NotoSansArabic-Bold.ttf"; do
    [ -s "$C" ] && { FONT_AR="$C"; break; }
done
FONT_EN="$HOME/.fonts/Orbitron-var.ttf"

IFS=',' read -r -a STREAMERS <<< "$STREAMERS_LIST"
echo "🔢 عدد الستريمرز: ${#STREAMERS[@]}"
mkdir -p "$WORKDIR"

# ═══════════════════════════════════════════════════
#  توليد الصور
# ═══════════════════════════════════════════════════
cat > /tmp/make_respect.py <<PYEOF
from PIL import Image, ImageDraw, ImageFilter, ImageFont
import urllib.request, io

W, H = 1920, 1080
WORKDIR = "$WORKDIR"
FONT_AR = "$FONT_AR"
FONT_EN = "$FONT_EN"
TITLE = "$TITLE_AR"
SUBTITLE = "$SUBTITLE_AR"
C_TITLE = "$COLOR_TITLE"
C_SUB = "$COLOR_SUB"
C_NEON = "$COLOR_NEON"
C_TEXT = "$COLOR_TEXT"

# ✅ إصلاح الخطأ: إضافة تعريف الألوان المفقودة
BG_TOP = ($BG_TOP_R, $BG_TOP_G, $BG_TOP_B)
BG_BOT = ($BG_BOT_R, $BG_BOT_G, $BG_BOT_B)

def load_font(path, size, weight=700):
    font = ImageFont.truetype(path, size)
    try:
        axes = font.get_variation_axes()
        if len(axes) == 1: font.set_variation_by_axes([weight])
        elif len(axes) == 2: font.set_variation_by_axes([0, weight])
        elif len(axes) == 3: font.set_variation_by_axes([0, weight, 0])
    except Exception: pass
    return font

# 1. الخلفية
bg = Image.new("RGB", (W, H))
d = ImageDraw.Draw(bg)
for y in range(H):
    t = y / H
    r = int(BG_TOP[0] + (BG_BOT[0] - BG_TOP[0]) * t)
    g = int(BG_TOP[1] + (BG_BOT[1] - BG_TOP[1]) * t)
    b = int(BG_TOP[2] + (BG_BOT[2] - BG_TOP[2]) * t)
    d.line([(0, y), (W, y)], fill=(r, g, b))
bg = bg.convert("RGBA")

grid_bg = Image.new("RGBA", (W, H), (0, 0, 0, 0))
gd = ImageDraw.Draw(grid_bg)
for x in range(0, W, 80): gd.line([(x, 0), (x, H)], fill=(166, 77, 255, 20), width=1)
for y in range(0, H, 80): gd.line([(0, y), (W, y)], fill=(166, 77, 255, 20), width=1)
bg = Image.alpha_composite(bg, grid_bg)
bg.convert("RGB").save(f"{WORKDIR}/bg.png", "PNG")

# 2. العنوان
font_title = load_font(FONT_EN, 130, 900)
tmp_t = Image.new("RGBA", (10, 10), (0,0,0,0))
bbox_t = ImageDraw.Draw(tmp_t).textbbox((0,0), TITLE, font=font_title)
tw, th = bbox_t[2]-bbox_t[0], bbox_t[3]-bbox_t[1]
title_img = Image.new("RGBA", (tw + 100, th + 100), (0,0,0,0))
td = ImageDraw.Draw(title_img)
td.text(((title_img.width - tw)//2, (title_img.height - th)//2), TITLE, font=font_title, fill=(212, 179, 255, 255))
glow = title_img.filter(ImageFilter.GaussianBlur(20))
title_img = Image.alpha_composite(glow, title_img)
title_img.save(f"{WORKDIR}/title.png", "PNG")

# 3. النص الفرعي
font_sub = load_font(FONT_AR, 40, 700)
sub_img = Image.new("RGBA", (1000, 100), (0,0,0,0))
sd = ImageDraw.Draw(sub_img)
bbox_s = sd.textbbox((0,0), SUBTITLE, font=font_sub, direction="rtl")
sw = bbox_s[2] - bbox_s[0]
sd.text(((sub_img.width - sw)//2, 20), SUBTITLE, font=font_sub, fill=C_SUB, direction="rtl")
sub_img.save(f"{WORKDIR}/sub.png", "PNG")

# 4. القائمة
items = [s.strip() for s in "$STREAMERS_LIST".split(',') if s.strip()]
font_list = load_font(FONT_EN, 22, 700)
COLS = 6
ROWS = (len(items) + COLS - 1) // COLS
CARD_W, CARD_H, GAP_X, GAP_Y = 260, 60, 20, 25
GRID_W = COLS * CARD_W + (COLS - 1) * GAP_X
GRID_H = ROWS * CARD_H + (ROWS - 1) * GAP_Y
grid_img = Image.new("RGBA", (GRID_W, GRID_H), (0,0,0,0))

for i, item in enumerate(items):
    row, col = i // COLS, i % COLS
    x, y = col * (CARD_W + GAP_X), row * (CARD_H + GAP_Y)
    card = Image.new("RGBA", (CARD_W, CARD_H), (0,0,0,0))
    cd = ImageDraw.Draw(card)
    cd.line([(0, 15), (0, 0), (15, 0)], fill=C_NEON, width=3)
    cd.line([(CARD_W-15, CARD_H), (CARD_W, CARD_H), (CARD_W, CARD_H-15)], fill=C_NEON, width=3)
    cd.line([(0, CARD_H-15), (0, CARD_H), (15, CARD_H)], fill=(255,255,255,50), width=2)
    cd.line([(CARD_W-15, 0), (CARD_W, 0), (CARD_W, 15)], fill=(255,255,255,50), width=2)
    bbox = cd.textbbox((0,0), item.upper(), font=font_list)
    cd.text(((CARD_W - (bbox[2]-bbox[0]))//2, (CARD_H - (bbox[3]-bbox[1]))//2 - bbox[1]), item.upper(), font=font_list, fill=C_TEXT)
    grid_img.alpha_composite(card, (x, y))
grid_img.save(f"{WORKDIR}/grid.png", "PNG")

# 5. الشعار
try:
    req = urllib.request.Request("$LOGO_URL", headers={"User-Agent": "Mozilla/5.0"})
    logo = Image.open(io.BytesIO(urllib.request.urlopen(req, timeout=25).read())).convert("RGBA")
    logo = logo.resize((140, int(logo.height * (140 / logo.width))), Image.LANCZOS)
    logo.save(f"{WORKDIR}/logo.png", "PNG")
except Exception:
    Image.new("RGBA", (140, 140), (0,0,0,0)).save(f"{WORKDIR}/logo.png", "PNG")

# 6. تجميع المحتوى
content = Image.new("RGBA", (W, H), (0,0,0,0))
content.alpha_composite(Image.open(f"{WORKDIR}/title.png"), ((W - tw - 100)//2, 200 - (th+100)//2))
content.alpha_composite(Image.open(f"{WORKDIR}/sub.png"), ((W - 1000)//2, 340 - 50))
content.alpha_composite(grid_img, ((W - GRID_W)//2, 430))
content.save(f"{WORKDIR}/content.png", "PNG")

# 7. توليد Overlays
font_live = load_font(FONT_EN, 42, 700)
for item in items:
    text = item.upper() + " :"
    tmp = Image.new("RGBA", (10, 10), (0,0,0,0))
    bbox = ImageDraw.Draw(tmp).textbbox((0,0), text, font=font_live)
    tw, th = bbox[2]-bbox[0], bbox[3]-bbox[1]
    img = Image.new("RGBA", (tw + 80, th + 40), (0,0,0,0))
    draw = ImageDraw.Draw(img)
    tx, ty = 10, (img.height - th)//2 - bbox[1]
    
    for dx in [-2, 2]:
        for dy in [-2, 2]:
            draw.text((tx+dx, ty+dy), text, font=font_live, fill=(0,0,0,255))
    glow_txt = Image.new("RGBA", img.size, (0,0,0,0))
    ImageDraw.Draw(glow_txt).text((tx, ty), text, font=font_live, fill=(0,255,0,255))
    img = Image.alpha_composite(img, glow_txt.filter(ImageFilter.GaussianBlur(8)))
    ImageDraw.Draw(img).text((tx, ty), text, font=font_live, fill=(0,255,0,255))
    
    ix, iy = tx + tw + 20, img.height // 2
    draw = ImageDraw.Draw(img)
    draw.ellipse([ix-4, iy-4, ix+4, iy+4], fill=(0,255,0,255))
    for r in [12, 20, 28]:
        draw.arc([ix-r, iy-r, ix+r, iy+r], start=135, end=225, fill=(0,255,0,255), width=3)
        draw.arc([ix-r, iy-r, ix+r, iy+r], start=-45, end=45, fill=(0,255,0,255), width=3)
    img.save(f"{WORKDIR}/live_{item}.png", "PNG")

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
    kill -TERM "$OUT" 2>/dev/null
    kill -TERM "$PROD" 2>/dev/null
    sleep 1
    kill -9 "$OUT" 2>/dev/null
    kill -9 "$PROD" 2>/dev/null
    exit 0
}
trap cleanup SIGTERM SIGINT

# ═══════════════════════════════════════════════════
#  المنتجات (1080p)
# ═══════════════════════════════════════════════════
start_producer_standby() {
    echo "⏳ تشغيل الشاشة (Standby Mode)..."
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
[v2][logo]overlay=x=(W-w)/2:y=40[vout]" \
        -map "[vout]" -map 4:a:0 \
        -c:v libx264 -preset ultrafast -tune zerolatency \
        -pix_fmt yuv420p -r $FPS -g $GOP \
        -c:a aac -b:a 128k -ar 44100 -ac 2 \
        -max_muxing_queue_size 4096 \
        -f mpegts "$FIFO" >/tmp/prod.log 2>&1 &
    PROD=$!
}

start_producer_live() {
    local M3U8="$1"
    local NAME="$2"
    local OVERLAY="$WORKDIR/live_${NAME}.png"
    echo "🔴 منتج مباشر: $NAME (1080p Overlay)"
    
    if [ ! -s "$OVERLAY" ]; then
        ffmpeg -y -hide_banner -loglevel warning -nostdin \
            -headers "User-Agent: $UA" \
            -reconnect 1 -reconnect_at_eof 1 -reconnect_streamed 1 \
            -reconnect_delay_max 5 -rw_timeout 15000000 \
            -analyzeduration 1000000 -probesize 1000000 \
            -fflags +genpts+igndts -i "$M3U8" \
            -c:v copy -c:a aac -b:a 128k -ar 44100 -ac 2 \
            -max_muxing_queue_size 4096 -muxdelay 0.1 -muxpreload 0.1 \
            -f mpegts "$FIFO" >/tmp/prod.log 2>&1 &
    else
        ffmpeg -y -hide_banner -loglevel warning -nostdin \
            -headers "User-Agent: $UA" \
            -reconnect 1 -reconnect_at_eof 1 -reconnect_streamed 1 \
            -reconnect_delay_max 5 -rw_timeout 15000000 \
            -analyzeduration 1000000 -probesize 1000000 \
            -fflags +genpts+igndts -i "$M3U8" \
            -loop 1 -framerate 1 -i "$OVERLAY" \
            -filter_complex "[0:v]scale=1920:1080:force_original_aspect_ratio=decrease,pad=1920:1080:(ow-iw)/2:(oh-ih)/2,fps=60[bg];[bg][1:v]overlay=x=(W-w)/2:y=20[vout]" \
            -map "[vout]" -map 0:a:0? \
            -c:v libx264 -preset ultrafast -tune zerolatency \
            -pix_fmt yuv420p -r $FPS -g $GOP \
            -b:v 6000k -maxrate 6500k -bufsize 12000k \
            -c:a aac -b:a 128k -ar 44100 -ac 2 \
            -max_muxing_queue_size 4096 \
            -f mpegts "$FIFO" >/tmp/prod.log 2>&1 &
    fi
    PROD=$!
}

start_output() {
    echo "🔗 الاتصال بـ Restream..."
    ffmpeg -y -hide_banner -loglevel warning -nostdin \
        -thread_queue_size 512 -f mpegts -i "$FIFO" \
        -map 0:v:0 -map 0:a:0? -c:v copy \
        -c:a aac -b:a 160k -ar 44100 -ac 2 \
        -max_muxing_queue_size 4096 -flvflags no_duration_filesize \
        -rw_timeout 15000000 -f flv "$RESTREAM_URL" >/tmp/out.log 2>&1 &
    OUT=$!
    sleep 6
    if ! kill -0 "$OUT" 2>/dev/null; then
        echo "❌ فشل المخرج:"; tail -n 5 /tmp/out.log
        return 1
    fi
    echo "✅ المخرج شغال (PID: $OUT)"
    return 0
}

kill_producer() {
    if [ -n "$PROD" ]; then kill -TERM "$PROD" 2>/dev/null; sleep 1; kill -9 "$PROD" 2>/dev/null; wait "$PROD" 2>/dev/null; fi
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
    OLD=$(timeout 10 gh run list --workflow="main.yml" --status=in_progress --json databaseId -q ".[].databaseId" 2>/dev/null | awk -v m="$GITHUB_RUN_ID" '$1 < m')
    for R in $OLD; do timeout 8 gh run cancel "$R" 2>/dev/null; done
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
            URL=$(timeout 20 streamlink --http-header "User-Agent=$UA" --stream-timeout 15 "https://kick.com/$ACTIVE" best --stream-url 2>/dev/null | grep -m1 "^http")
            if [ -n "$URL" ]; then start_producer_live "$URL" "$ACTIVE"; else start_producer_standby; MODE="STANDBY"; ACTIVE=""; ACTIVE_IDX=-1; fi
        else
            start_producer_standby; MODE="STANDBY"
        fi
        sleep 3; continue
    fi

    FOUND=""; FOUND_URL=""; FOUND_IDX=-1
    LIMIT=${#STREAMERS[@]}
    if [ "$MODE" = "LIVE" ] && [ "$ACTIVE_IDX" -ge 0 ]; then LIMIT=$((ACTIVE_IDX + 1)); fi

    for ((i=0; i<LIMIT; i++)); do
        S=$(echo "${STREAMERS[$i]}" | xargs); [ -z "$S" ] && continue
        URL=$(timeout 20 streamlink --http-header "User-Agent=$UA" --stream-timeout 15 "https://kick.com/$S" best --stream-url 2>/dev/null | grep -m1 "^http")
        if [ -n "$URL" ]; then FOUND="$S"; FOUND_URL="$URL"; FOUND_IDX=$i; break; fi
    done

    if [ -n "$FOUND" ]; then
        if [ "$MODE" != "LIVE" ] || [ "$ACTIVE" != "$FOUND" ]; then
            echo "🎯 التحويل إلى: $FOUND"
            kill_producer; sleep 1
            start_producer_live "$FOUND_URL" "$FOUND"
            sleep 6
            if kill -0 "$PROD" 2>/dev/null; then MODE="LIVE"; ACTIVE="$FOUND"; ACTIVE_IDX=$FOUND_IDX; echo "✅ مباشر: $FOUND"; else MODE="NONE"; fi
        fi
    else
        if [ "$MODE" != "STANDBY" ]; then
            echo "⏳ لا يوجد بث — عودة للانتظار"
            kill_producer; sleep 1; start_producer_standby; sleep 3; MODE="STANDBY"; ACTIVE=""; ACTIVE_IDX=-1
        fi
    fi

    TICK=$((TICK + 1))
    if [ $((TICK % 4)) -eq 0 ]; then
        OS=$(kill -0 "$OUT" 2>/dev/null && echo "حي" || echo "ميت")
        PS=$(kill -0 "$PROD" 2>/dev/null && echo "حي" || echo "ميت")
        echo "── [$(date -u +%H:%M:%S)] $MODE | OUT=$OS | PROD=$PS ──"
    fi
    sleep 3
done

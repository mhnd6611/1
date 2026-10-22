#!/bin/bash
set +m

# ═══════════════════════════════════════════════════
#  Respect Broadcast — Kick → Restream
#  Luxury Glassmorphism UI + Floating Animations
# ═══════════════════════════════════════════════════

# ─── الإعدادات ───
TITLE_AR="لم يبدأ ستريمرز ريسبكت"
SUBTITLE_AR="جاري انتظار ستريمرز ريسبكت المذكورين ادناه"
LABEL_AR="قائمة الستريمرز:"

# ⚠️ النص السفلي (الأخضر)
BOTTOM_TEXT="بث دربحه الساعة 10 أو 11" 
# مفتاح التشغيل: 1 = يظهر (عدا دربحه)، 2 = مخفي تماماً
TEXT_SWITCH="${TEXT_SWITCH:-1}" 

COLOR_TITLE="#d4b3ff"
COLOR_SUB="#ffffff"
COLOR_LABEL="#e6ccff"
COLOR_CARD_TEXT="#ffffff"
COLOR_CARD_BORDER="#a64dff"

BG_TOP_R=13; BG_TOP_G=5;  BG_TOP_B=24
BG_BOT_R=26; BG_BOT_G=10; BG_BOT_B=48
GLOW_R=150;  GLOW_G=80;   GLOW_B=220

FONT_SIZE_TITLE=95
FONT_SIZE_SUB=45
FONT_SIZE_LIST=26

Y_TITLE=160
Y_SUB=280
Y_GRID_START=390

STREAMERS_LIST="${STREAMERS_LIST:-drb7h,S5B,ABO8ALYY,ID7O,F1AISAL,xmusabrt,TAF86,abo_khrbaa,Peerless,Seagull,iMonkey_D,FHLWY,Hook,okb8,wolf,NASSER,Aymnalsatam,BoQamar,xya7ya,klash}"

LOGO_URL="https://i.top4top.io/p_39264fv5g0.png"
LOGO_W=160
Y_LOGO=50
LOGO_SHOW=6
LOGO_CYCLE=8

FPS=60
GOP=120

UA="Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"
# ═══════════════════════════════════════════════════

RESTREAM_KEY="${RESTREAM_KEY:-}"
[ -z "$RESTREAM_KEY" ] && { echo "❌ مفتاح Restream فارغ"; exit 1; }
[ -z "$STREAMERS_LIST" ] && { echo "❌ قائمة الستريمرز فارغة"; exit 1; }

RESTREAM_URL="rtmp://live.restream.io/live/$RESTREAM_KEY"
FIFO="/tmp/relay.ts"
WORKDIR="/tmp/respect_ui"

# ─── الخطوط ───
FONT_AR=""
for C in "$HOME/.fonts/Cairo-var.ttf" "$HOME/.fonts/NotoSansArabic-Bold.ttf"; do
    [ -s "$C" ] && { FONT_AR="$C"; break; }
done
[ -z "$FONT_AR" ] && { echo "❌ لا يوجد خط عربي"; exit 1; }

FONT_EN="$HOME/.fonts/Orbitron-var.ttf"
[ ! -s "$FONT_EN" ] && { echo "❌ لا يوجد Orbitron"; exit 1; }

echo "🔤 الخطوط: عربي=$FONT_AR | إنجليزي=$FONT_EN"

IFS=',' read -r -a STREAMERS <<< "$STREAMERS_LIST"
echo "🔢 عدد الستريمرز: ${#STREAMERS[@]}"

mkdir -p "$WORKDIR"

# ═══════════════════════════════════════════════════
#  توليد الصور (Glassmorphism)
# ═══════════════════════════════════════════════════
cat > /tmp/make_respect.py <<PYEOF
from PIL import Image, ImageDraw, ImageFilter, ImageFont
import urllib.request, io, os, math

W, H = 1920, 1080
WORKDIR = "$WORKDIR"
FONT_AR = "$FONT_AR"
FONT_EN = "$FONT_EN"
TITLE = "$TITLE_AR"
SUBTITLE = "$SUBTITLE_AR"
BOTTOM_TEXT = "$BOTTOM_TEXT"
C_TITLE = "$COLOR_TITLE"
C_SUB = "$COLOR_SUB"
C_CARD_TEXT = "$COLOR_CARD_TEXT"
FS_TITLE = $FONT_SIZE_TITLE
FS_SUB = $FONT_SIZE_SUB
FS_LIST = $FONT_SIZE_LIST
Y_TITLE = $Y_TITLE
Y_SUB = $Y_SUB
Y_GRID_START = $Y_GRID_START
BG_TOP = ($BG_TOP_R, $BG_TOP_G, $BG_TOP_B)
BG_BOT = ($BG_BOT_R, $BG_BOT_G, $BG_BOT_B)
GLOW = ($GLOW_R, $GLOW_G, $GLOW_B, 60)
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

# ═══ 1) الخلفية ═══
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
gd.ellipse([W//2 - 900, H//2 - 600, W//2 + 900, H//2 + 600], fill=GLOW)
glow = glow.filter(ImageFilter.GaussianBlur(350))
bg = Image.alpha_composite(bg, glow)

pattern = Image.new("RGBA", (W, H), (0, 0, 0, 0))
pd = ImageDraw.Draw(pattern)
size = 120
for y in range(-size, H + size, int(size * 0.866)):
    for x in range(-size, W + size, int(size * 1.5)):
        pts = [(x, y - size//2), (x + size//2, y), (x, y + size//2), (x - size//2, y)]
        pd.polygon(pts, outline=(255, 255, 255, 10), width=2)
bg = Image.alpha_composite(bg, pattern)
bg.convert("RGB").save(f"{WORKDIR}/bg.png", "PNG")

# ═══ 2) دالة رسم نص ═══
def make_text_png(text, font, color, out, direction="rtl"):
    c = color.lstrip("#")
    r, g, b = tuple(int(c[i:i+2], 16) for i in (0, 2, 4))
    tmp = Image.new("RGBA", (10, 10), (0, 0, 0, 0))
    td = ImageDraw.Draw(tmp)
    bbox = td.textbbox((0, 0), text, font=font, direction=direction)
    pad = 80
    Wn = bbox[2] - bbox[0] + pad * 2
    Hn = bbox[3] - bbox[1] + pad * 2
    gx, gy = pad - bbox[0], pad - bbox[1]
    
    glow_layer = Image.new("RGBA", (Wn, Hn), (0, 0, 0, 0))
    for radius, alpha in [(40, 90), (20, 150), (8, 220)]:
        t = Image.new("RGBA", (Wn, Hn), (0, 0, 0, 0))
        ImageDraw.Draw(t).text((gx, gy), text, font=font, fill=(r, g, b, alpha), direction=direction)
        glow_layer = Image.alpha_composite(glow_layer, t.filter(ImageFilter.GaussianBlur(radius)))
    
    txt = Image.new("RGBA", (Wn, Hn), (0, 0, 0, 0))
    ImageDraw.Draw(txt).text((gx, gy), text, font=font, fill=(r, g, b, 255), direction=direction)
    final = Image.alpha_composite(glow_layer, txt)
    final.save(out, "PNG")

font_title = load_font(FONT_AR, FS_TITLE, 900)
font_sub = load_font(FONT_AR, FS_SUB, 700)
make_text_png(TITLE, font_title, C_TITLE, f"{WORKDIR}/title.png", "rtl")
make_text_png(SUBTITLE, font_sub, C_SUB, f"{WORKDIR}/sub.png", "rtl")

# ═══ 3) بطاقات الستريمرز ═══
items = [s.strip() for s in STREAMERS_STR.split(',') if s.strip()]
font_list = load_font(FONT_EN, FS_LIST, 700)

COLS = 4
ROWS = (len(items) + COLS - 1) // COLS
CARD_W = 320
CARD_H = 85
GAP_X = 35
GAP_Y = 30
GRID_W = COLS * CARD_W + (COLS - 1) * GAP_X
GRID_H = ROWS * CARD_H + (ROWS - 1) * GAP_Y

grid_img = Image.new("RGBA", (GRID_W, GRID_H), (0, 0, 0, 0))

for i, item in enumerate(items):
    row = i // COLS
    col = i % COLS
    x = col * (CARD_W + GAP_X)
    y = row * (CARD_H + GAP_Y)
    
    card = Image.new("RGBA", (CARD_W, CARD_H), (0, 0, 0, 0))
    cd = ImageDraw.Draw(card)
    cd.rounded_rectangle([(0,0), (CARD_W, CARD_H)], radius=15, fill=(255, 255, 255, 15), outline=(166, 77, 255, 120), width=2)
    cd.rounded_rectangle([(2,2), (CARD_W-2, CARD_H-2)], radius=13, outline=(255, 255, 255, 40), width=1)
    
    bbox = cd.textbbox((0, 0), item.upper(), font=font_list)
    tw, th = bbox[2] - bbox[0], bbox[3] - bbox[1]
    tx = (CARD_W - tw) // 2 - bbox[0]
    ty = (CARD_H - th) // 2 - bbox[1]
    
    cd.text((tx, ty), item.upper(), font=font_list, fill=C_CARD_TEXT)
    
    glow_txt = Image.new("RGBA", (CARD_W, CARD_H), (0, 0, 0, 0))
    ImageDraw.Draw(glow_txt).text((tx, ty), item.upper(), font=font_list, fill=(255, 255, 255, 150))
    glow_txt = glow_txt.filter(ImageFilter.GaussianBlur(8))
    
    card = Image.alpha_composite(card, glow_txt)
    grid_img.alpha_composite(card, (x, y))

grid_img.save(f"{WORKDIR}/grid.png", "PNG")

# ═══ 4) تجميع المحتوى ═══
content = Image.new("RGBA", (W, H), (0, 0, 0, 0))
title_img = Image.open(f"{WORKDIR}/title.png").convert("RGBA")
sub_img = Image.open(f"{WORKDIR}/sub.png").convert("RGBA")

content.alpha_composite(title_img, ((W - title_img.width)//2, Y_TITLE))
content.alpha_composite(sub_img, ((W - sub_img.width)//2, Y_SUB))
content.alpha_composite(grid_img, ((W - GRID_W)//2, Y_GRID_START))
content.save(f"{WORKDIR}/content.png", "PNG")

# ═══ 5) الشعار ═══
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

# ═══ 6) النص السفلي الأخضر ═══
if BOTTOM_TEXT.strip():
    font_bottom = load_font(FONT_AR, 42, 900)
    tmp_b = Image.new("RGBA", (10, 10), (0, 0, 0, 0))
    bbox_b = ImageDraw.Draw(tmp_b).textbbox((0, 0), BOTTOM_TEXT, font=font_bottom, direction="rtl")
    tw = bbox_b[2] - bbox_b[0]
    th = bbox_b[3] - bbox_b[1]
    
    pad_x = 60
    pad_y = 15
    banner_w = tw + pad_x * 2
    banner_h = th + pad_y * 2
    radius = banner_h // 2
    
    banner = Image.new("RGBA", (banner_w, banner_h), (0, 0, 0, 0))
    bd = ImageDraw.Draw(banner)
    bd.rounded_rectangle([(0, 0), (banner_w, banner_h)], radius=radius, fill=(10, 30, 10, 150), outline=(57, 255, 20, 150), width=2)
    bd.rounded_rectangle([(2, 2), (banner_w-2, banner_h-2)], radius=radius-2, outline=(255, 255, 255, 40), width=1)
    
    tx = pad_x - bbox_b[0]
    ty = pad_y - bbox_b[1]
    
    glow_b = Image.new("RGBA", (banner_w, banner_h), (0, 0, 0, 0))
    ImageDraw.Draw(glow_b).text((tx, ty), BOTTOM_TEXT, font=font_bottom, fill=(57, 255, 20, 255), direction="rtl")
    glow_b = glow_b.filter(ImageFilter.GaussianBlur(10))
    banner = Image.alpha_composite(banner, glow_b)
    
    bd = ImageDraw.Draw(banner) 
    bd.text((tx, ty), BOTTOM_TEXT, font=font_bottom, fill=(57, 255, 20, 255), direction="rtl")
    
    banner.save(f"{WORKDIR}/bottom.png", "PNG")
else:
    if os.path.exists(f"{WORKDIR}/bottom.png"):
        os.remove(f"{WORKDIR}/bottom.png")

print("✅ اكتمل التوليد")
PYEOF

echo "🎨 توليد صور الشاشة..."
python3 /tmp/make_respect.py
[ ! -s "$WORKDIR/bg.png" ] && { echo "❌ فشل التوليد"; exit 1; }

# ═══════════════════════════════════════════════════
#  FIFO
# ═══════════════════════════════════════════════════
rm -f "$FIFO"
mkfifo "$FIFO"
exec 3<>"$FIFO"

# ═══════════════════════════════════════════════════
#  منتج شاشة الانتظار
# ═══════════════════════════════════════════════════
start_producer_standby() {
    echo "⏳ تشغيل الشاشة المتحركة..."
    ffmpeg -y -hide_banner -loglevel warning -nostdin \
        -loop 1 -framerate $FPS -i "$WORKDIR/bg.png" \
        -loop 1 -framerate $FPS -i "$WORKDIR/content.png" \
        -loop 1 -framerate $FPS -i "$WORKDIR/logo.png" \
        -f lavfi -i "anullsrc=r=44100:cl=stereo" \
        -filter_complex "\
[0:v]format=rgba,eq=brightness='0.02*sin(2*PI*t/6)':eval=frame[bg];\
[1:v]format=rgba[content];\
[bg][content]overlay=x=(W-w)/2:y='(H-h)/2 + 12*sin(2*PI*t/5)':eval=frame[v1];\
[2:v]format=rgba,scale='iw*(1+0.04*sin(2*PI*t/3))':-1:eval=frame[logo_anim];\
[v1][logo_anim]overlay=x=(W-w)/2:y=$Y_LOGO:enable='between(mod(t\,$LOGO_CYCLE)\,0.5\,$LOGO_SHOW)'[vout]" \
        -map "[vout]" -map 3:a:0 \
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
#  المخرج
# ═══════════════════════════════════════════════════
start_output() {
    local show_text="$1"
    echo "🔗 الاتصال بـ Restream... (Text: $show_text)"
    
    if [ "$show_text" = "1" ] && [ -s "$WORKDIR/bottom.png" ]; then
        ffmpeg -y -hide_banner -loglevel warning -nostdin \
            -thread_queue_size 512 \
            -f mpegts -i "$FIFO" \
            -loop 1 -framerate $FPS -i "$WORKDIR/bottom.png" \
            -filter_complex "[0:v][1:v]overlay=x=(W-w)/2:y=H-h-35:enable='lt(mod(t\,300)\,10)'[vout]" \
            -map "[vout]" -map 0:a:0? \
            -c:v libx264 -preset ultrafast -tune zerolatency \
            -pix_fmt yuv420p -g $GOP -r $FPS \
            -b:v 6500k -maxrate 7000k -bufsize 14000k \
            -c:a aac -b:a 160k -ar 44100 -ac 2 \
            -max_muxing_queue_size 4096 \
            -flvflags no_duration_filesize \
            -f flv "$RESTREAM_URL" >/tmp/out.log 2>&1 &
    else
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
            -f flv "$RESTREAM_URL" >/tmp/out.log 2>&1 &
    fi
    
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
    [ -n "$PROD" ] && kill -9 "$PROD" 2>/dev/null
    [ -n "$PROD" ] && wait "$PROD" 2>/dev/null
    PROD=""
}

# ═══════════════════════════════════════════════════
#  التشغيل
# ═══════════════════════════════════════════════════
echo "🚀 بدء التشغيل..."

start_producer_standby
sleep 5
kill -0 "$PROD" 2>/dev/null || { echo "❌ المنتج مات"; cat /tmp/prod.log; exit 1; }
echo "✅ شاشة الانتظار شغالة (PID: $PROD)"

# إلغاء الرنات القديمة
if [ -n "$GH_TOKEN" ] && [ -n "$GITHUB_RUN_ID" ]; then
    echo "🔍 البحث عن الرنات القديمة لإلغائها..."
    OLD=$(timeout 10 gh run list --workflow="main.yml" --status=in_progress \
          --json databaseId -q ".[].databaseId" 2>/dev/null | \
          awk -v m="$GITHUB_RUN_ID" '$1 < m')
    for R in $OLD; do
        echo "🛑 إلغاء الرن القديم: $R"
        timeout 8 gh run cancel "$R" 2>/dev/null
    done
    echo "⏳ انتظار 5 ثوانٍ لتحرير اتصال Restream..."
    sleep 5
fi

# تحديد حالة النص الابتدائية بناءً على TEXT_SWITCH
SHOW_TEXT=1
if [ "$TEXT_SWITCH" = "2" ]; then
    SHOW_TEXT=0
    echo "🔕 تم إخفاء النص السفلي (بناءً على الإعداد TEXT_SWITCH=2)"
fi

start_output "$SHOW_TEXT" || exit 1

MODE="STANDBY"
ACTIVE=""
ACTIVE_IDX=-1
TICK=0

while true; do
    if ! kill -0 "$OUT" 2>/dev/null; then
        echo "⚠️ المخرج مات — إعادة..."
        kill_producer
        sleep 2
        start_output "$SHOW_TEXT" || exit 1
        sleep 2
        continue
    fi

    if ! kill -0 "$PROD" 2>/dev/null; then
        echo "⚠️ المنتج مات — إعادة..."
        if [ "$MODE" = "LIVE" ] && [ -n "$ACTIVE" ]; then
            URL=$(timeout 20 streamlink --http-header "User-Agent=$UA" \
                  --stream-timeout 15 "https://kick.com/$ACTIVE" best \
                  --stream-url 2>/dev/null | grep -m1 "^http")
            if [ -n "$URL" ]; then
                start_producer_live "$URL" "$ACTIVE"
            else
                start_producer_standby
                MODE="STANDBY"; ACTIVE=""; ACTIVE_IDX=-1
                # تحديث حالة النص عند العودة للانتظار
                NEW_SHOW_TEXT=1
                if [ "$TEXT_SWITCH" = "2" ]; then NEW_SHOW_TEXT=0; fi
                if [ "$SHOW_TEXT" != "$NEW_SHOW_TEXT" ]; then
                    kill -9 "$OUT" 2>/dev/null; sleep 1
                    start_output "$NEW_SHOW_TEXT"; SHOW_TEXT="$NEW_SHOW_TEXT"
                fi
            fi
        else
            start_producer_standby
            MODE="STANDBY"
            NEW_SHOW_TEXT=1
            if [ "$TEXT_SWITCH" = "2" ]; then NEW_SHOW_TEXT=0; fi
            if [ "$SHOW_TEXT" != "$NEW_SHOW_TEXT" ]; then
                kill -9 "$OUT" 2>/dev/null; sleep 1
                start_output "$NEW_SHOW_TEXT"; SHOW_TEXT="$NEW_SHOW_TEXT"
            fi
        fi
        sleep 3
        continue
    fi

    FOUND=""; FOUND_URL=""; FOUND_IDX=-1
    LIMIT=${#STREAMERS[@]}
    if [ "$MODE" = "LIVE" ] && [ "$ACTIVE_IDX" -ge 0 ]; then
        LIMIT=$((ACTIVE_IDX + 1))
    fi

    for ((i=0; i<LIMIT; i++)); do
        S=$(echo "${STREAMERS[$i]}" | xargs)
        [ -z "$S" ] && continue
        URL=$(timeout 20 streamlink --http-header "User-Agent=$UA" \
              --stream-timeout 15 "https://kick.com/$S" best \
              --stream-url 2>/dev/null | grep -m1 "^http")
        if [ -n "$URL" ]; then
            FOUND="$S"; FOUND_URL="$URL"; FOUND_IDX=$i; break
        fi
    done

    if [ -n "$FOUND" ]; then
        if [ "$MODE" != "LIVE" ] || [ "$ACTIVE" != "$FOUND" ]; then
            echo "🎯 التحويل إلى: $FOUND"
            kill_producer
            sleep 1
            
            # تحديد حالة النص للبث المباشر
            NEW_SHOW_TEXT=1
            if [ "$TEXT_SWITCH" = "2" ]; then
                NEW_SHOW_TEXT=0
            elif [ "$(echo "$FOUND" | tr '[:upper:]' '[:lower:]')" = "drb7h" ]; then
                NEW_SHOW_TEXT=0
            fi
            
            if [ "$NEW_SHOW_TEXT" != "$SHOW_TEXT" ]; then
                echo "🔄 تغيير حالة النص — إعادة تشغيل المخرج..."
                kill -9 "$OUT" 2>/dev/null
                sleep 1
                start_output "$NEW_SHOW_TEXT"
                SHOW_TEXT="$NEW_SHOW_TEXT"
            fi

            start_producer_live "$FOUND_URL" "$FOUND"
            sleep 6
            if kill -0 "$PROD" 2>/dev/null; then
                MODE="LIVE"; ACTIVE="$FOUND"; ACTIVE_IDX=$FOUND_IDX
                echo "✅ مباشر: $FOUND"
            else
                echo "⚠️ فشل $FOUND"
                MODE="NONE"
            fi
        fi
    else
        if [ "$MODE" != "STANDBY" ]; then
            echo "⏳ لا يوجد بث — عودة للانتظار"
            kill_producer
            sleep 1
            
            # تحديد حالة النص عند العودة للانتظار
            NEW_SHOW_TEXT=1
            if [ "$TEXT_SWITCH" = "2" ]; then NEW_SHOW_TEXT=0; fi
            
            if [ "$NEW_SHOW_TEXT" != "$SHOW_TEXT" ]; then
                echo "🔄 تغيير حالة النص — إعادة تشغيل المخرج..."
                kill -9 "$OUT" 2>/dev/null
                sleep 1
                start_output "$NEW_SHOW_TEXT"
                SHOW_TEXT="$NEW_SHOW_TEXT"
            fi

            start_producer_standby
            sleep 3
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

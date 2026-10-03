#!/bin/bash
set +m

# ═════════════════════════════════════════════
#  إعدادات البث — Respect
# ═════════════════════════════════════════════

TITLE="لم يبدأ ستريمرز ريسبكت"
SUBTITLE="جاري انتضار ستريمرز ريسبكت المذكورين اعلاه"
LABEL="قائمة الستريمرز:"

# ألوان
COLOR_T="#b266ff"
COLOR_S="#ffffff"
COLOR_L="#b266ff"
COLOR_NAME="#d9b3ff"
BG_TOP="#0d0518"
BG_BOT="#1a0a30"
GLOW_RGB="150,80,220"

# أحجام الخطوط
FS_T=100
FS_S=58
FS_L=22
FS_NAME=22

# مواضع
Y_LIST=60
Y_TITLE=200
Y_SUB=370

# الشعار
LOGO_URL="https://i.top4top.io/p_39264fv5g0.png"
LOGO_W=150
LOGO_BOTTOM=40
LOGO_SHOW=5
LOGO_CYCLE=7

# ═════════════════════════════════════════════

RESTREAM_KEY="${RESTREAM_KEY:-}"
[ -z "$RESTREAM_KEY" ] && { echo "❌ مفتاح فارغ"; exit 1; }
[ -z "$STREAMERS_LIST" ] && { echo "❌ قائمة فارغة"; exit 1; }

UA="Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"
RESTREAM_URL="rtmp://live.restream.io/live/$RESTREAM_KEY"
FIFO="/tmp/relay.ts"

# ─── الخطوط ───
FONT_AR=""
for C in "$HOME/.fonts/Cairo-var.ttf" "$HOME/.fonts/NotoSansArabic-Bold.ttf"; do
    [ -s "$C" ] && { FONT_AR="$C"; break; }
done
[ -z "$FONT_AR" ] && { echo "❌ لا يوجد خط عربي"; exit 1; }

FONT_EN="$HOME/.fonts/Orbitron-var.ttf"
[ ! -s "$FONT_EN" ] && { echo "❌ لا يوجد Orbitron"; exit 1; }

echo "🔤 عربي: $FONT_AR"
echo "🔤 إنجليزي: $FONT_EN"

IFS=',' read -r -a STREAMERS <<< "$STREAMERS_LIST"
echo "🔢 عدد الستريمرز: ${#STREAMERS[@]}"

# ═════════ توليد الخلفية ═════════
cat > /tmp/make_bg.py <<PYEOF
from PIL import Image, ImageDraw, ImageFilter
import sys

W, H = 1920, 1080
out = sys.argv[1]

BG_TOP = (13, 5, 24)
BG_BOT = (26, 10, 48)

img = Image.new("RGB", (W, H))
d = ImageDraw.Draw(img)
for y in range(H):
    t = y / H
    r = int(BG_TOP[0] + (BG_BOT[0] - BG_TOP[0]) * t)
    g = int(BG_TOP[1] + (BG_BOT[1] - BG_TOP[1]) * t)
    b = int(BG_TOP[2] + (BG_BOT[2] - BG_TOP[2]) * t)
    d.line([(0, y), (W, y)], fill=(r, g, b))

img = img.convert("RGBA")

glow = Image.new("RGBA", (W, H), (0, 0, 0, 0))
gd = ImageDraw.Draw(glow)
gd.ellipse([W//2 - 700, H//2 - 500, W//2 + 700, H//2 + 500], fill=(150, 80, 220, 65))
glow = glow.filter(ImageFilter.GaussianBlur(250))
img = Image.alpha_composite(img, glow)

pattern = Image.new("RGBA", (W, H), (0, 0, 0, 0))
pd = ImageDraw.Draw(pattern)
size = 90
start_y = H - 320
row = 0
y = start_y
while y < H + size:
    col = 0
    x = (size // 2) if row % 2 else 0
    while x < W + size:
        pts = [(x, y - size//2), (x + size//2, y), (x, y + size//2), (x - size//2, y)]
        pd.polygon(pts, outline=(0, 0, 0, 220), width=2)
        x += size
        col += 1
    y += size // 2
    row += 1

mask = Image.new("L", (W, H), 0)
md = ImageDraw.Draw(mask)
for yy in range(start_y, H):
    a = min(255, int((yy - start_y) / 0.7))
    md.line([(0, yy), (W, yy)], fill=a)
pattern.putalpha(mask)

img = Image.alpha_composite(img, pattern)
img.convert("RGB").save(out, "PNG")
print(f"OK: {out}")
PYEOF

# ═════════ دالة تحميل خط ═════════
FONT_LOADER='
def load_font(path, size, weight=700):
    from PIL import ImageFont
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
'

# ═════════ سكربت رسم النص ═════════
cat > /tmp/render.py <<PYEOF
import sys
from PIL import Image, ImageDraw
$FONT_LOADER

text = sys.argv[1]
color = sys.argv[2]
pointsize = int(sys.argv[3])
output = sys.argv[4]
font_path = sys.argv[5]
outline_color = sys.argv[6] if len(sys.argv) > 6 else None
outline_w = int(sys.argv[7]) if len(sys.argv) > 7 else 0
direction = sys.argv[8] if len(sys.argv) > 8 else "rtl"

font = load_font(font_path, pointsize, 700)

tmp = Image.new("RGBA", (10, 10), (0, 0, 0, 0))
d = ImageDraw.Draw(tmp)
bbox = d.textbbox((0, 0), text, font=font, direction=direction)
tw = bbox[2] - bbox[0]
th = bbox[3] - bbox[1]

pad = max(outline_w, 8) + 15
W = tw + pad * 2
H = th + pad * 2
img = Image.new("RGBA", (W, H), (0, 0, 0, 0))
d = ImageDraw.Draw(img)
x = pad - bbox[0]
y = pad - bbox[1]

if outline_color and outline_w > 0:
    for dx in range(-outline_w, outline_w + 1):
        for dy in range(-outline_w, outline_w + 1):
            if dx*dx + dy*dy <= outline_w*outline_w:
                d.text((x+dx, y+dy), text, font=font, fill=outline_color, direction=direction)

d.text((x, y), text, font=font, fill=color, direction=direction)
img.save(output, "PNG")
PYEOF

render_ar() {
    python3 /tmp/render.py "$1" "$2" "$3" "$4" "$FONT_AR" "$5" "$6" "rtl"
}
render_en() {
    python3 /tmp/render.py "$1" "$2" "$3" "$4" "$FONT_EN" "$5" "$6" "ltr"
}

# ═════════ قائمة الستريمرز (3 أسطر) ═════════
build_list_lines() {
    local total=${#STREAMERS[@]}
    local per_line=$(( (total + 2) / 3 ))
    [ $per_line -lt 4 ] && per_line=4
    local line1="" line2="" line3="" i=0
    for S in "${STREAMERS[@]}"; do
        S=$(echo "$S" | xargs)
        [ -z "$S" ] && continue
        if [ $i -lt $per_line ]; then
            [ -z "$line1" ] && line1="$S" || line1="$line1 ◆ $S"
        elif [ $i -lt $((per_line * 2)) ]; then
            [ -z "$line2" ] && line2="$S" || line2="$line2 ◆ $S"
        else
            [ -z "$line3" ] && line3="$S" || line3="$line3 ◆ $S"
        fi
        i=$((i+1))
    done
    echo "$line1"
    echo "$line2"
    echo "$line3"
}

mapfile -t LIST_LINES < <(build_list_lines)
LIST_LINE1="${LIST_LINES[0]}"
LIST_LINE2="${LIST_LINES[1]}"
LIST_LINE3="${LIST_LINES[2]}"

# ═════════ الشعار ═════════
LOGO=""
echo "⬇️ الشعار..."
if curl -sL --max-time 25 -A "Mozilla/5.0" "$LOGO_URL" -o /tmp/logo_src.png 2>/dev/null; then
    if [ -s /tmp/logo_src.png ] && file /tmp/logo_src.png 2>/dev/null | grep -qiE "PNG|JPEG|image"; then
        LOGO="/tmp/logo_src.png"
        echo "✅ الشعار"
    fi
fi
[ -z "$LOGO" ] && echo "⚠️ بلا شعار"

# ═════════ توليد الخلفية ═════════
echo "🎨 توليد الخلفية..."
python3 /tmp/make_bg.py /tmp/bg.png
BG_IMG="/tmp/bg.png"
[ ! -s "$BG_IMG" ] && { echo "❌ فشل الخلفية"; exit 1; }

# ═════════ رسم النصوص ═════════
echo "🖌️ رسم النصوص..."
mkdir -p /tmp/txt && rm -f /tmp/txt/*.png

render_ar "$LABEL" "$COLOR_L" $FS_L /tmp/txt/label.png "black" 2

if [ -n "$LIST_LINE1" ]; then
    L1_UPPER=$(echo "$LIST_LINE1" | tr '[:lower:]' '[:upper:]')
    render_en "$L1_UPPER" "$COLOR_NAME" $FS_NAME /tmp/txt/l1.png "black" 1
fi
if [ -n "$LIST_LINE2" ]; then
    L2_UPPER=$(echo "$LIST_LINE2" | tr '[:lower:]' '[:upper:]')
    render_en "$L2_UPPER" "$COLOR_NAME" $FS_NAME /tmp/txt/l2.png "black" 1
fi
if [ -n "$LIST_LINE3" ]; then
    L3_UPPER=$(echo "$LIST_LINE3" | tr '[:lower:]' '[:upper:]')
    render_en "$L3_UPPER" "$COLOR_NAME" $FS_NAME /tmp/txt/l3.png "black" 1
fi

render_ar "$TITLE" "$COLOR_T" $FS_T /tmp/txt/title.png "black" 4
render_ar "$SUBTITLE" "$COLOR_S" $FS_S /tmp/txt/sub.png "black" 3

[ ! -s /tmp/txt/title.png ] && { echo "❌ فشل الرسم"; exit 1; }
echo "✅ اكتمل الرسم"

# ═════════ FIFO ═════════
rm -f "$FIFO"; mkfifo "$FIFO"; exec 3<>"$FIFO"

# ═════════ فلتر الانتظار (3 أسطر) ═════════
standby_filter() {
    local logo_idx=$1
    local n2=$2
    local n3=$3
    local f=""
    local next="0:v"
    local idx=1

    # label (يمين علوي)
    f="[0:v][${idx}:v]overlay=x=W-w-40:y=$Y_LIST[a]"
    next="a"; idx=$((idx+1))

    # l1
    f="$f;[${next}][${idx}:v]overlay=x=W-w-40:y=$((Y_LIST + 50))[b]"
    next="b"; idx=$((idx+1))

    # l2 (اختياري)
    if [ "$n2" = "1" ]; then
        f="$f;[${next}][${idx}:v]overlay=x=W-w-40:y=$((Y_LIST + 50 + FS_NAME + 20))[c]"
        next="c"; idx=$((idx+1))
    fi

    # l3 (اختياري)
    if [ "$n3" = "1" ]; then
        f="$f;[${next}][${idx}:v]overlay=x=W-w-40:y=$((Y_LIST + 50 + (FS_NAME + 20) * 2))[d]"
        next="d"; idx=$((idx+1))
    fi

    # title (وسط)
    f="$f;[${next}][${idx}:v]overlay=x=(W-w)/2:y=$Y_TITLE[e]"
    next="e"; idx=$((idx+1))

    # subtitle (وسط)
    f="$f;[${next}][${idx}:v]overlay=x=(W-w)/2:y=$Y_SUB[f]"
    next="f"; idx=$((idx+1))

    # logo (وسط أسفل، مصغّر)
    if [ "$logo_idx" -ge 0 ]; then
        f="$f;[${logo_idx}:v]scale=${LOGO_W}:-1[logosc];[${next}][logosc]overlay=x=(W-w)/2:y=H-h-$LOGO_BOTTOM:enable='lt(mod(t\,$LOGO_CYCLE)\,$LOGO_SHOW)'[v]"
    else
        f="$f;[${next}]null[v]"
    fi
    echo "$f"
}

run() {
    local inputs=()
    inputs+=(-loop 1 -framerate 30 -i /tmp/bg.png)
    inputs+=(-loop 1 -framerate 30 -i /tmp/txt/label.png)
    inputs+=(-loop 1 -framerate 30 -i /tmp/txt/l1.png)
    local next_idx=3
    local n2=0; local n3=0
    if [ -s /tmp/txt/l2.png ]; then
        inputs+=(-loop 1 -framerate 30 -i /tmp/txt/l2.png)
        n2=1; next_idx=$((next_idx + 1))
    fi
    if [ -s /tmp/txt/l3.png ]; then
        inputs+=(-loop 1 -framerate 30 -i /tmp/txt/l3.png)
        n3=1; next_idx=$((next_idx + 1))
    fi
    inputs+=(-loop 1 -framerate 30 -i /tmp/txt/title.png)
    next_idx=$((next_idx + 1))
    inputs+=(-loop 1 -framerate 30 -i /tmp/txt/sub.png)
    next_idx=$((next_idx + 1))
    local logo_idx=-1
    if [ -n "$LOGO" ]; then
        inputs+=(-loop 1 -framerate 30 -i "$LOGO")
        logo_idx=$next_idx; next_idx=$((next_idx + 1))
    fi
    inputs+=(-f lavfi -i "anullsrc=r=44100:cl=stereo")
    local audio_idx=$next_idx

    local filter
    filter=$(standby_filter "$logo_idx" "$n2" "$n3")

    ffmpeg -y -hide_banner -loglevel warning -nostdin \
        "${inputs[@]}" -filter_complex "$filter" \
        -map "[v]" -map ${audio_idx}:a:0 \
        -c:v libx264 -preset ultrafast -tune zerolatency -pix_fmt yuv420p -g 60 \
        -c:a aac -b:a 128k -ar 44100 -ac 2 \
        -max_muxing_queue_size 4096 \
        -f mpegts "$FIFO" >/tmp/prod.log 2>&1 &
    PROD=$!
    sleep 6
    if ! kill -0 $PROD 2>/dev/null; then
        echo "❌ منتج الانتظار:"; cat /tmp/prod.log; return 1
    fi
    echo "✅ منتج الانتظار (PID: $PROD)"

    ffmpeg -y -hide_banner -loglevel warning -nostdin \
        -thread_queue_size 512 \
        -fflags +genpts+igndts+discardcorrupt \
        -analyzeduration 5000000 -probesize 2000000 \
        -f mpegts -i "$FIFO" \
        -c copy -max_muxing_queue_size 4096 \
        -flvflags no_duration_filesize \
        -f flv "$RESTREAM_URL" >/tmp/out.log 2>&1 &
    OUT=$!
    sleep 5
    if ! kill -0 $OUT 2>/dev/null; then
        echo "❌ المخرج:"; cat /tmp/out.log
        kill -9 $PROD 2>/dev/null; return 1
    fi
    echo "✅ البث مباشر — منتج=$PROD مخرج=$OUT"

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
            echo "⚠️ المخرج مات"; kill -9 $PROD 2>/dev/null; return 1
        fi

        if ! kill -0 $PROD 2>/dev/null; then
            if [ "$MODE" = "مباشر" ]; then
                MODE="فارغ"; ACTIVE=""; ACTIVE_IDX=-1
            else
                local f2
                f2=$(standby_filter "$logo_idx" "$n2" "$n3")
                ffmpeg -y -hide_banner -loglevel warning -nostdin \
                    "${inputs[@]}" -filter_complex "$f2" \
                    -map "[v]" -map ${audio_idx}:a:0 \
                    -c:v libx264 -preset ultrafast -tune zerolatency -pix_fmt yuv420p -g 60 \
                    -c:a aac -b:a 128k -ar 44100 -ac 2 \
                    -max_muxing_queue_size 4096 \
                    -f mpegts "$FIFO" >/tmp/prod.log 2>&1 &
                PROD=$!
                sleep 3
            fi
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
                kill -9 $PROD 2>/dev/null
                wait $PROD 2>/dev/null
                sleep 1

                ffmpeg -y -hide_banner -loglevel warning -nostdin \
                    -headers "User-Agent: $UA" \
                    -reconnect 1 -reconnect_at_eof 1 -reconnect_streamed 1 \
                    -reconnect_delay_max 5 \
                    -analyzeduration 2000000 -probesize 2000000 \
                    -fflags +genpts+igndts \
                    -i "$FOUND_URL" \
                    -c:v copy -c:a aac -b:a 128k -ar 44100 -ac 2 \
                    -max_muxing_queue_size 4096 \
                    -muxdelay 0.1 -muxpreload 0.1 \
                    -f mpegts "$FIFO" >/tmp/prod.log 2>&1 &
                PROD=$!
                sleep 6

                if kill -0 $PROD 2>/dev/null; then
                    MODE="مباشر"; ACTIVE="$FOUND"; ACTIVE_IDX=$FOUND_IDX
                    echo "✅ مباشر: $FOUND"
                else
                    echo "⚠️ فشل $FOUND"; tail -n 5 /tmp/prod.log; MODE="فارغ"
                fi
            fi
        else
            if [ "$MODE" != "انتظار" ]; then
                echo "⏳ انتظار"
                kill -9 $PROD 2>/dev/null
                wait $PROD 2>/dev/null
                sleep 1
                local f3
                f3=$(standby_filter "$logo_idx" "$n2" "$n3")
                ffmpeg -y -hide_banner -loglevel warning -nostdin \
                    "${inputs[@]}" -filter_complex "$f3" \
                    -map "[v]" -map ${audio_idx}:a:0 \
                    -c:v libx264 -preset ultrafast -tune zerolatency -pix_fmt yuv420p -g 60 \
                    -c:a aac -b:a 128k -ar 44100 -ac 2 \
                    -max_muxing_queue_size 4096 \
                    -f mpegts "$FIFO" >/tmp/prod.log 2>&1 &
                PROD=$!
                sleep 3
                MODE="انتظار"; ACTIVE=""; ACTIVE_IDX=-1
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
}

echo "🚀 بدء..."
while true; do
    run
    echo "⚠️ إعادة بعد 5 ثوان..."
    sleep 5
done

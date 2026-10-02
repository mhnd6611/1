#!/bin/bash
set +m

# ═════════════════════════════════════════════
#  إعدادات البث — ريسبكت
# ═════════════════════════════════════════════

TITLE="لم يبدأ ستريمرز ريسبكت البث بعد"
SUBTITLE="جاري انتضار ستريمرز ريسبكت بدأ البث."
LABEL="قائمة الستريمرز:"

COLOR_T="white"
COLOR_S="white"
COLOR_L="#DDDDDD"
COLOR_OUTLINE="black"
BG="0x140024"

FS_T=82
FS_S=56
FS_L=28

Y_LIST=60
Y_TITLE=200
Y_SUB=370
OUTLINE_W=4

LOGO_URL="https://i.top4top.io/p_39264fv5g0.png"
LOGO_W=280
LOGO_BOTTOM=60
LOGO_SHOW=5
LOGO_CYCLE=7
# ═════════════════════════════════════════════

RESTREAM_KEY="${RESTREAM_KEY:-}"
[ -z "$RESTREAM_KEY" ] && { echo "❌ مفتاح فارغ"; exit 1; }
[ -z "$STREAMERS_LIST" ] && { echo "❌ قائمة فارغة"; exit 1; }

UA="Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"
RESTREAM_URL="rtmp://live.restream.io/live/$RESTREAM_KEY"
FIFO="/tmp/relay.ts"

# اكتشاف الخط
FONT_FILE=""
for CANDIDATE in \
    "$HOME/.fonts/NotoSansArabic-Bold.ttf" \
    "$HOME/.fonts/NotoNaskhArabic-Regular.ttf"; do
    if [ -s "$CANDIDATE" ]; then
        FONT_FILE="$CANDIDATE"
        break
    fi
done
[ -z "$FONT_FILE" ] && { echo "❌ لا يوجد خط"; exit 1; }
echo "🔤 الخط: $FONT_FILE"

IFS=',' read -r -a STREAMERS <<< "$STREAMERS_LIST"

# ═════════ سكربت رسم النص ═════════
cat > /tmp/render.py <<'PYEOF'
import sys
from PIL import Image, ImageDraw, ImageFont

text = sys.argv[1]
color = sys.argv[2]
pointsize = int(sys.argv[3])
output = sys.argv[4]
font_path = sys.argv[5]
outline_color = sys.argv[6] if len(sys.argv) > 6 else None
outline_w = int(sys.argv[7]) if len(sys.argv) > 7 else 0

font = ImageFont.truetype(font_path, pointsize)
tmp = Image.new("RGBA", (10, 10), (0, 0, 0, 0))
d = ImageDraw.Draw(tmp)
bbox = d.textbbox((0, 0), text, font=font, direction="rtl")
tw = bbox[2] - bbox[0]
th = bbox[3] - bbox[1]

pad = max(outline_w, 5) + 10
W = tw + pad * 2
H = th + pad * 2
img = Image.new("RGBA", (W, H), (0, 0, 0, 0))
d = ImageDraw.Draw(img)
x = pad - bbox[0]
y = pad - bbox[1]

if outline_color and outline_w > 0:
    for dx in range(-outline_w, outline_w + 1):
        for dy in range(-outline_w, outline_w + 1):
            if dx * dx + dy * dy <= outline_w * outline_w:
                d.text((x + dx, y + dy), text, font=font, fill=outline_color, direction="rtl")

d.text((x, y), text, font=font, fill=color, direction="rtl")
img.save(output, "PNG")
PYEOF

render_text() {
    python3 /tmp/render.py "$1" "$2" "$3" "$4" "$FONT_FILE" "$5" "$6"
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
            [ -z "$line1" ] && line1="$S" || line1="$line1 · $S"
        elif [ $i -lt $((per_line * 2)) ]; then
            [ -z "$line2" ] && line2="$S" || line2="$line2 · $S"
        else
            [ -z "$line3" ] && line3="$S" || line3="$line3 · $S"
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
if curl -sL --max-time 25 -A "Mozilla/5.0" "$LOGO_URL" -o /tmp/logo_src.png 2>/dev/null; then
    if [ -s /tmp/logo_src.png ] && file /tmp/logo_src.png 2>/dev/null | grep -qiE "PNG|JPEG|image"; then
        LOGO="/tmp/logo_src.png"
        echo "✅ الشعار"
    fi
fi
[ -z "$LOGO" ] && echo "⚠️ بلا شعار"

# ═════════ رسم النصوص الثابتة ═════════
echo "🖌️ رسم النصوص..."
mkdir -p /tmp/txt && rm -f /tmp/txt/*.png

render_text "$LABEL $LIST_LINE1" "#DDDDDD" $FS_L /tmp/txt/l1.png "black" 1
[ -n "$LIST_LINE2" ] && render_text "$LIST_LINE2" "#DDDDDD" $FS_L /tmp/txt/l2.png "black" 1
[ -n "$LIST_LINE3" ] && render_text "$LIST_LINE3" "#DDDDDD" $FS_L /tmp/txt/l3.png "black" 1
render_text "$TITLE" "white" $FS_T /tmp/txt/title.png "black" $OUTLINE_W
render_text "$SUBTITLE" "white" $FS_S /tmp/txt/sub.png "black" $OUTLINE_W

[ ! -s /tmp/txt/title.png ] && { echo "❌ فشل الرسم"; exit 1; }
echo "✅ اكتمل الرسم"

# ═════════ FIFO ═════════
rm -f "$FIFO"; mkfifo "$FIFO"; exec 3<>"$FIFO"

# ═════════ فلتر شاشة الانتظار ═════════
standby_filter() {
    local logo_idx=$1
    local n2=$2
    local n3=$3
    local f=""
    f="[0:v][3:v]overlay=x=(W-w)/2:y=$Y_LIST[a]"
    local next="a"
    local idx=4
    if [ "$n2" = "1" ]; then
        f="$f;[${next}][${idx}:v]overlay=x=(W-w)/2:y=$((Y_LIST + FS_L + 15))[b]"
        next="b"
        idx=$((idx + 1))
    fi
    if [ "$n3" = "1" ]; then
        f="$f;[${next}][${idx}:v]overlay=x=(W-w)/2:y=$((Y_LIST + (FS_L + 15) * 2))[c]"
        next="c"
        idx=$((idx + 1))
    fi
    f="$f;[${next}][1:v]overlay=x=(W-w)/2:y=$Y_TITLE[d]"
    f="$f;[d][2:v]overlay=x=(W-w)/2:y=$Y_SUB[e]"
    if [ "$logo_idx" -ge 0 ]; then
        f="$f;[e][${logo_idx}:v]overlay=x=(W-w)/2:y=H-h-$LOGO_BOTTOM:enable='lt(mod(t\,$LOGO_CYCLE)\,$LOGO_SHOW)'[v]"
    else
        f="$f;[e]null[v]"
    fi
    echo "$f"
}

run() {
    local inputs=()
    inputs+=(-re -f lavfi -i "color=c=$BG:s=1920x1080:r=30")
    inputs+=(-loop 1 -framerate 30 -i /tmp/txt/title.png)
    inputs+=(-loop 1 -framerate 30 -i /tmp/txt/sub.png)
    inputs+=(-loop 1 -framerate 30 -i /tmp/txt/l1.png)
    local next_idx=4
    local n2=0; local n3=0
    if [ -s /tmp/txt/l2.png ]; then
        inputs+=(-loop 1 -framerate 30 -i /tmp/txt/l2.png)
        n2=1; next_idx=$((next_idx + 1))
    fi
    if [ -s /tmp/txt/l3.png ]; then
        inputs+=(-loop 1 -framerate 30 -i /tmp/txt/l3.png)
        n3=1; next_idx=$((next_idx + 1))
    fi
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

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
FS_L=30

Y_LIST=60
Y_TITLE=200
Y_SUB=370
OUTLINE_W=4

LOGO_URL="https://i.top4top.io/p_39264fv5g0.png"
LOGO_W=280
LOGO_BOTTOM=60
LOGO_SHOW=5
LOGO_CYCLE=7

# ─── إعلان الستريمر (يظهر فقط أثناء البث المباشر) ───
ANN_TEXT_1="سابثون بثوث ريسبكت"
ANN_TEXT_2="البث مستمر"
ANN_TEXT_3="بثوث شباب ريسبكت"
# ═════════════════════════════════════════════

RESTREAM_KEY="${RESTREAM_KEY:-}"
[ -z "$RESTREAM_KEY" ] && { echo "❌ مفتاح فارغ"; exit 1; }
[ -z "$STREAMERS_LIST" ] && { echo "❌ قائمة فارغة"; exit 1; }

UA="Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"
RESTREAM_URL="rtmp://live.restream.io/live/$RESTREAM_KEY"
FIFO="/tmp/relay.ts"

# ─── خط يدعم العربية + الإنجليزية معاً ───
FONT_FILE=""
for CANDIDATE in \
    "$HOME/.fonts/NotoSansArabic-Bold.ttf" \
    "$HOME/.fonts/Cairo-Bold.ttf" \
    "/usr/share/fonts/truetype/noto/NotoSansArabic-Bold.ttf" ; do
    if [ -s "$CANDIDATE" ]; then
        FONT_FILE="$CANDIDATE"
        break
    fi
done
if [ -z "$FONT_FILE" ]; then
    echo "⬇️ تحميل خط Noto Sans Arabic Bold..."
    mkdir -p ~/.fonts
    curl -sL --max-time 30 \
      "https://github.com/notofonts/arabic/raw/main/fonts/NotoSansArabic/hinted/ttf/NotoSansArabic-Bold.ttf" \
      -o "$HOME/.fonts/NotoSansArabic-Bold.ttf" 2>/dev/null
    [ -s "$HOME/.fonts/NotoSansArabic-Bold.ttf" ] && FONT_FILE="$HOME/.fonts/NotoSansArabic-Bold.ttf"
fi
[ -z "$FONT_FILE" ] && { echo "❌ فشل تحميل الخط"; exit 1; }
echo "🔤 الخط: $FONT_FILE"

IFS=',' read -r -a STREAMERS <<< "$STREAMERS_LIST"

# ═════════ سكربت بايثون: رسم النصوص الثابتة ═════════
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
            if dx*dx + dy*dy <= outline_w*outline_w:
                d.text((x+dx, y+dy), text, font=font, fill=outline_color, direction="rtl")

d.text((x, y), text, font=font, fill=color, direction="rtl")
img.save(output, "PNG")
PYEOF

render_text() {
    python3 /tmp/render.py "$1" "$2" "$3" "$4" "$FONT_FILE" "$5" "$6"
}

# ═════════ سكربت بايثون: فيديو الإعلان ═════════
cat > /tmp/make_announcement.py <<'PYEOF'
import sys, os, subprocess
from PIL import Image, ImageDraw, ImageFont

streamer = sys.argv[1] if len(sys.argv) > 1 and sys.argv[1] else "streamer"
font_path = sys.argv[2]
output = sys.argv[3]
t1, t2, t3 = sys.argv[4], sys.argv[5], sys.argv[6]

fps = 30
duration_per = 5
cycle = 4
W, H = 1920, 260
font_size = 42
font = ImageFont.truetype(font_path, font_size)

color = (0, 255, 136, 255)
outline = (0, 51, 24, 255)
ow = 3

texts = [t1, t2, t3, f"بث {streamer}"]

def render_one(text):
    tmp = Image.new("RGBA", (10, 10), (0, 0, 0, 0))
    d = ImageDraw.Draw(tmp)
    bbox = d.textbbox((0, 0), text, font=font, direction="rtl")
    tw = bbox[2] - bbox[0]; th = bbox[3] - bbox[1]
    pad = ow + 8
    W_img = tw + pad*2; H_img = th + pad*2
    img = Image.new("RGBA", (W_img, H_img), (0,0,0,0))
    d = ImageDraw.Draw(img)
    x = pad - bbox[0]; y = pad - bbox[1]
    for dx in range(-ow, ow+1):
        for dy in range(-ow, ow+1):
            if dx*dx + dy*dy <= ow*ow:
                d.text((x+dx, y+dy), text, font=font, fill=outline, direction="rtl")
    d.text((x, y), text, font=font, fill=color, direction="rtl")
    return img

text_imgs = [render_one(t) for t in texts]
total_frames = fps * duration_per * cycle
os.makedirs("/tmp/ann_frames", exist_ok=True)

for i in range(total_frames):
    t = i / fps
    idx = int(t / duration_per) % cycle
    lt = t % duration_per

    if lt < 0.5:
        p = lt / 0.5
        alpha = int(255*p); y_off = int(30*(1-p)); scale = 0.7 + 0.3*p
    elif lt < 4.5:
        alpha = 255; y_off = 0; scale = 1.0
    else:
        p = (lt-4.5)/0.5
        alpha = int(255*(1-p)); y_off = int(-25*p); scale = 1.0 - 0.15*p

    canvas = Image.new("RGBA", (W, H), (0,0,0,0))
    txt = text_imgs[idx]
    tw, th = txt.size
    if scale != 1.0:
        nw, nh = max(1, int(tw*scale)), max(1, int(th*scale))
        txt = txt.resize((nw, nh), Image.LANCZOS)
    else:
        nw, nh = tw, th
    if alpha < 255:
        a = txt.split()[3].point(lambda x: int(x*alpha/255))
        txt.putalpha(a)
    x = (W-nw)//2; y = H-nh-20+y_off
    canvas.paste(txt, (x,y), txt)
    canvas.save(f"/tmp/ann_frames/f_{i:04d}.png")

subprocess.run([
    "ffmpeg", "-y", "-loglevel", "error",
    "-framerate", str(fps),
    "-i", "/tmp/ann_frames/f_%04d.png",
    "-c:v", "qtrle", "-pix_fmt", "argb",
    output
], check=True)
print(f"OK: {output}")
for f in os.listdir("/tmp/ann_frames"):
    os.remove(f"/tmp/ann_frames/{f}")
PYEOF

# ═════════ قائمة الستريمرز ═════════
build_list_lines() {
    local total=${#STREAMERS[@]}
    local per_line=$(( (total + 1) / 2 ))
    [ $per_line -lt 4 ] && per_line=4
    local line1="" line2="" i=0
    for S in "${STREAMERS[@]}"; do
        S=$(echo "$S" | xargs); [ -z "$S" ] && continue
        if [ $i -lt $per_line ]; then
            [ -z "$line1" ] && line1="$S" || line1="$line1 · $S"
        else
            [ -z "$line2" ] && line2="$S" || line2="$line2 · $S"
        fi
        i=$((i+1))
    done
    echo "$line1"; echo "$line2"
}
mapfile -t LIST_LINES < <(build_list_lines)
LIST_LINE1="${LIST_LINES[0]}"
LIST_LINE2="${LIST_LINES[1]}"

# ═════════ الشعار ═════════
LOGO=""
if curl -sL --max-time 25 -A "Mozilla/5.0" "$LOGO_URL" -o /tmp/logo_src.png 2>/dev/null; then
    if [ -s /tmp/logo_src.png ] && file /tmp/logo_src.png 2>/dev/null | grep -qiE "PNG|JPEG|image"; then
        LOGO="/tmp/logo_src.png"
        echo "✅ الشعار"
    fi
fi
[ -z "$LOGO" ] && echo "⚠️ بلا شعار"

# ═════════ رسم نصوص الشاشة ═════════
echo "🖌️ رسم النصوص..."
mkdir -p /tmp/txt && rm -f /tmp/txt/*.png
render_text "$LABEL $LIST_LINE1" "#DDDDDD" $FS_L /tmp/txt/l1.png "black" 1
[ -n "$LIST_LINE2" ] && render_text "$LIST_LINE2" "#DDDDDD" $FS_L /tmp/txt/l2.png "black" 1
render_text "$TITLE" "white" $FS_T /tmp/txt/title.png "black" $OUTLINE_W
render_text "$SUBTITLE" "white" $FS_S /tmp/txt/sub.png "black" $OUTLINE_W
[ ! -s /tmp/txt/title.png ] && { echo "❌ فشل الرسم"; exit 1; }
echo "✅ اكتمل الرسم"

# ═════════ إنشاء إعلان لستريمر ═════════
make_announcement() {
    local NAME="$1"
    local OUT_FILE="$2"
    python3 /tmp/make_announcement.py "$NAME" "$FONT_FILE" "$OUT_FILE" \
        "$ANN_TEXT_1" "$ANN_TEXT_2" "$ANN_TEXT_3" 2>/dev/null
}

# ═════════ FIFO ═════════
rm -f "$FIFO"; mkfifo "$FIFO"; exec 3<>"$FIFO"

# ═════════ فلتر شاشة الانتظار (بدون إعلان) ═════════
standby_filter() {
    local logo_idx=$1
    local list2_exists=$2
    local f=""
    f="[0:v][3:v]overlay=x=(W-w)/2:y=$Y_LIST[a]"
    if [ "$list2_exists" = "1" ]; then
        f="$f;[a][4:v]overlay=x=(W-w)/2:y=$((Y_LIST + FS_L + 15))[b]"
        local n="b"
    else
        local n="a"
    fi
    f="$f;[${n}][1:v]overlay=x=(W-w)/2:y=$Y_TITLE[c]"
    f="$f;[c][2:v]overlay=x=(W-w)/2:y=$Y_SUB[d]"
    if [ "$logo_idx" -ge 0 ]; then
        f="$f;[d][${logo_idx}:v]overlay=x=(W-w)/2:y=H-h-$LOGO_BOTTOM:enable='lt(mod(t\,$LOGO_CYCLE)\,$LOGO_SHOW)'[v]"
    else
        f="$f;[d]null[v]"
    fi
    echo "$f"
}

run() {
    # منتج الانتظار
    local inputs=()
    inputs+=(-re -f lavfi -i "color=c=$BG:s=1920x1080:r=30")
    inputs+=(-loop 1 -framerate 30 -i /tmp/txt/title.png)
    inputs+=(-loop 1 -framerate 30 -i /tmp/txt/sub.png)
    inputs+=(-loop 1 -framerate 30 -i /tmp/txt/l1.png)
    local next_idx=4
    local list2_exists=0
    if [ -s /tmp/txt/l2.png ]; then
        inputs+=(-loop 1 -framerate 30 -i /tmp/txt/l2.png)
        list2_exists=1; next_idx=5
    fi
    local logo_idx=-1
    if [ -n "$LOGO" ]; then
        inputs+=(-loop 1 -framerate 30 -i "$LOGO")
        logo_idx=$next_idx; next_idx=$((next_idx+1))
    fi
    inputs+=(-f lavfi -i "anullsrc=r=44100:cl=stereo")
    local audio_idx=$next_idx

    local filter
    filter=$(standby_filter "$logo_idx" "$list2_exists")

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
                f2=$(standby_filter "$logo_idx" "$list2_exists")
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
                # ─── إنشاء إعلان خاص بهذا الستريمر ───
                ANN_VIDEO="/tmp/ann_${FOUND}.mov"
                if [ ! -s "$ANN_VIDEO" ]; then
                    echo "🎬 إنتاج إعلان $FOUND..."
                    make_announcement "$FOUND" "$ANN_VIDEO"
                fi

                kill -9 $PROD 2>/dev/null
                wait $PROD 2>/dev/null
                sleep 1

                if [ -s "$ANN_VIDEO" ]; then
                    ffmpeg -y -hide_banner -loglevel warning -nostdin \
                        -headers "User-Agent: $UA" \
                        -reconnect 1 -reconnect_at_eof 1 -reconnect_streamed 1 \
                        -reconnect_delay_max 5 \
                        -analyzeduration 2000000 -probesize 2000000 \
                        -fflags +genpts+igndts \
                        -i "$FOUND_URL" \
                        -stream_loop -1 -i "$ANN_VIDEO" \
                        -filter_complex "[0:v][1:v]overlay=x=0:y=H-260[v]" \
                        -map "[v]" -map 0:a:0 \
                        -c:v libx264 -preset ultrafast -tune zerolatency -pix_fmt yuv420p -g 60 \
                        -c:a aac -b:a 128k -ar 44100 -ac 2 \
                        -max_muxing_queue_size 4096 \
                        -f mpegts "$FIFO" >/tmp/prod.log 2>&1 &
                else
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
                fi
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
                f3=$(standby_filter "$logo_idx" "$list2_exists")
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

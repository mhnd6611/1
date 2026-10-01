#!/bin/bash
set +m

# ═════════════════════════════════════════════
#  إعدادات البث — ريسبكت
# ═════════════════════════════════════════════

# النصوص
TITLE="لم يبدأ ستريمرز ريسبكت البث بعد"
SUBTITLE="جاري انتضار ستريمرز ريسبكت بدأ البث."
LABEL="قائمة الستريمرز:"

# الألوان
COLOR_T="white"
COLOR_S="white"
COLOR_L="#DDDDDD"
COLOR_OUTLINE="black"
BG="0x140024"

# أحجام الخطوط
FS_T=82
FS_S=56
FS_L=30

# المواضع
Y_LIST=60
Y_TITLE=200
Y_SUB=370
OUTLINE_W=4

# الشعار
LOGO_URL="https://i.top4top.io/p_39264fv5g0.png"
LOGO_W=280
LOGO_BOTTOM=60
LOGO_SHOW=5
LOGO_CYCLE=7

# الخط
FONT_NAME="Noto Naskh Arabic"

# ═════════════════════════════════════════════

RESTREAM_KEY="${RESTREAM_KEY:-}"
[ -z "$RESTREAM_KEY" ] && { echo "❌ خطأ: مفتاح ريستريم فارغ"; exit 1; }
[ -z "$STREAMERS_LIST" ] && { echo "❌ خطأ: قائمة الستريمرز فارغة"; exit 1; }

UA="Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"
RESTREAM_URL="rtmp://live.restream.io/live/$RESTREAM_KEY"
FIFO="/tmp/relay.ts"

IFS=',' read -r -a STREAMERS <<< "$STREAMERS_LIST"

# ═════════ قائمة الستريمرز على سطرين ═════════
build_list_lines() {
    local total=${#STREAMERS[@]}
    local per_line=$(( (total + 1) / 2 ))
    [ $per_line -lt 4 ] && per_line=4
    local line1="" line2="" i=0
    for S in "${STREAMERS[@]}"; do
        S=$(echo "$S" | xargs)
        [ -z "$S" ] && continue
        if [ $i -lt $per_line ]; then
            [ -z "$line1" ] && line1="$S" || line1="$line1 · $S"
        else
            [ -z "$line2" ] && line2="$S" || line2="$line2 · $S"
        fi
        i=$((i+1))
    done
    echo "$line1"
    echo "$line2"
}

mapfile -t LIST_LINES < <(build_list_lines)
LIST_LINE1="${LIST_LINES[0]}"
LIST_LINE2="${LIST_LINES[1]}"
echo "📋 السطر 1: $LIST_LINE1"
echo "📋 السطر 2: $LIST_LINE2"

# ═════════ تحميل الشعار ═════════
LOGO=""
echo "⬇️ تحميل الشعار..."
if curl -sL --max-time 25 -A "Mozilla/5.0" "$LOGO_URL" -o /tmp/logo_src.png 2>/dev/null; then
    if [ -s /tmp/logo_src.png ] && file /tmp/logo_src.png 2>/dev/null | grep -qiE "PNG|JPEG|image"; then
        convert /tmp/logo_src.png -resize ${LOGO_W}x /tmp/logo.png 2>/dev/null
        [ -s /tmp/logo.png ] && { LOGO="/tmp/logo.png"; echo "✅ الشعار جاهز"; }
    fi
fi
[ -z "$LOGO" ] && echo "⚠️ لا يوجد شعار — سيستمر البث بدونه"

# ═════════ رسم النصوص (يدعم العربية 100%) ═════════
echo "🖌️ رسم النصوص..."
mkdir -p /tmp/txt && rm -f /tmp/txt/*.png

convert -background none -fill "$COLOR_L" -stroke "$COLOR_OUTLINE" -strokewidth 1 \
    -font "$FONT_NAME" -pointsize $FS_L \
    pango:"$LABEL $LIST_LINE1" /tmp/txt/l1.png 2>/dev/null

if [ -n "$LIST_LINE2" ]; then
    convert -background none -fill "$COLOR_L" -stroke "$COLOR_OUTLINE" -strokewidth 1 \
        -font "$FONT_NAME" -pointsize $FS_L \
        pango:"$LIST_LINE2" /tmp/txt/l2.png 2>/dev/null
fi

convert -background none -fill "$COLOR_T" -stroke "$COLOR_OUTLINE" -strokewidth $OUTLINE_W \
    -font "$FONT_NAME" -pointsize $FS_T \
    pango:"$TITLE" /tmp/txt/title.png 2>/dev/null

convert -background none -fill "$COLOR_S" -stroke "$COLOR_OUTLINE" -strokewidth $OUTLINE_W \
    -font "$FONT_NAME" -pointsize $FS_S \
    pango:"$SUBTITLE" /tmp/txt/sub.png 2>/dev/null

if [ ! -s /tmp/txt/title.png ]; then
    echo "❌ فشل رسم النص"
    exit 1
fi
echo "✅ تم رسم النصوص"

# ═════════ FIFO ═════════
rm -f "$FIFO"
mkfifo "$FIFO"
exec 3<>"$FIFO"

# ═════════ دالة بناء فلتر الانتظار ═════════
standby_filter() {
    local logo_idx=$1
    local list2_exists=$2

    local f=""
    f="[0:v][3:v]overlay=x=(W-w)/2:y=$Y_LIST[a]"
    if [ "$list2_exists" = "1" ]; then
        f="$f;[a][4:v]overlay=x=(W-w)/2:y=$((Y_LIST + FS_L + 15))[b]"
        local next="b"
    else
        local next="a"
    fi
    f="$f;[${next}][1:v]overlay=x=(W-w)/2:y=$Y_TITLE[c]"
    f="$f;[c][2:v]overlay=x=(W-w)/2:y=$Y_SUB[d]"
    if [ "$logo_idx" -ge 0 ]; then
        f="$f;[d][${logo_idx}:v]overlay=x=(W-w)/2:y=H-h-$LOGO_BOTTOM:enable='lt(mod(t\,$LOGO_CYCLE)\,$LOGO_SHOW)'[v]"
    else
        f="$f;[d]null[v]"
    fi
    echo "$f"
}

# ═════════ تشغيل ═════════
run() {
    local inputs=()
    inputs+=(-re -f lavfi -i "color=c=$BG:s=1920x1080:r=30")
    inputs+=(-loop 1 -framerate 30 -i /tmp/txt/title.png)
    inputs+=(-loop 1 -framerate 30 -i /tmp/txt/sub.png)
    inputs+=(-loop 1 -framerate 30 -i /tmp/txt/l1.png)
    local next_idx=4
    local list2_exists=0
    if [ -s /tmp/txt/l2.png ]; then
        inputs+=(-loop 1 -framerate 30 -i /tmp/txt/l2.png)
        list2_exists=1
        next_idx=5
    fi
    local logo_idx=-1
    if [ -n "$LOGO" ]; then
        inputs+=(-loop 1 -framerate 30 -i "$LOGO")
        logo_idx=$next_idx
        next_idx=$((next_idx + 1))
    fi
    inputs+=(-f lavfi -i "anullsrc=r=44100:cl=stereo")
    local audio_idx=$next_idx

    local filter
    filter=$(standby_filter "$logo_idx" "$list2_exists")

    echo "▶️ تشغيل منتج شاشة الانتظار..."
    ffmpeg -y -hide_banner -loglevel warning -nostdin \
        "${inputs[@]}" \
        -filter_complex "$filter" \
        -map "[v]" -map ${audio_idx}:a:0 \
        -c:v libx264 -preset ultrafast -tune zerolatency -pix_fmt yuv420p -g 60 \
        -c:a aac -b:a 128k -ar 44100 -ac 2 \
        -max_muxing_queue_size 4096 \
        -f mpegts "$FIFO" >/tmp/prod.log 2>&1 &
    PROD=$!
    sleep 6
    if ! kill -0 $PROD 2>/dev/null; then
        echo "❌ فشل منتج الانتظار:"
        cat /tmp/prod.log
        return 1
    fi
    echo "✅ منتج الانتظار شغال (PID: $PROD)"

    echo "🔗 فتح اتصال مع ريستريم..."
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
        echo "❌ فشل الاتصال مع ريستريم:"
        cat /tmp/out.log
        kill -9 $PROD 2>/dev/null
        return 1
    fi
    echo "✅ البث مباشر — منتج=$PROD مخرج=$OUT"

    MODE="انتظار"; ACTIVE=""; ACTIVE_IDX=-1; TICK=0

    while true; do
        if ! kill -0 $OUT 2>/dev/null; then
            echo "⚠️ المخرج مات — إعادة التشغيل"
            kill -9 $PROD 2>/dev/null
            return 1
        fi

        if ! kill -0 $PROD 2>/dev/null; then
            if [ "$MODE" = "مباشر" ]; then
                MODE="فارغ"; ACTIVE=""; ACTIVE_IDX=-1
            else
                echo "🔄 إعادة تشغيل منتج الانتظار..."
                local f2
                f2=$(standby_filter "$logo_idx" "$list2_exists")
                ffmpeg -y -hide_banner -loglevel warning -nostdin \
                    "${inputs[@]}" \
                    -filter_complex "$f2" \
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
            S=$(echo "${STREAMERS[$i]}" | xargs)
            [ -z "$S" ] && continue
            URL=$(timeout 20 streamlink --http-header "User-Agent=$UA" \
                  --stream-timeout 15 "https://kick.com/$S" best \
                  --stream-url 2>/dev/null | grep -m1 "^http")
            if [ -n "$URL" ]; then
                FOUND="$S"; FOUND_URL="$URL"; FOUND_IDX=$i
                break
            fi
        done

        if [ -n "$FOUND" ]; then
            if [ "$MODE" != "مباشر" ] || [ "$ACTIVE" != "$FOUND" ]; then
                echo "🎯 التحويل إلى: $FOUND"
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
                    echo "✅ بث مباشر: $FOUND"
                else
                    echo "⚠️ فشل الاتصال بـ $FOUND:"
                    tail -n 5 /tmp/prod.log
                    MODE="فارغ"
                fi
            fi
        else
            if [ "$MODE" != "انتظار" ]; then
                echo "⏳ لا يوجد بث — العودة لشاشة الانتظار"
                kill -9 $PROD 2>/dev/null
                wait $PROD 2>/dev/null
                sleep 1

                local f3
                f3=$(standby_filter "$logo_idx" "$list2_exists")
                ffmpeg -y -hide_banner -loglevel warning -nostdin \
                    "${inputs[@]}" \
                    -filter_complex "$f3" \
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
            OUT_STATE=$(kill -0 $OUT 2>/dev/null && echo "حي" || echo "ميت")
            PROD_STATE=$(kill -0 $PROD 2>/dev/null && echo "حي" || echo "ميت")
            echo "── [$(date -u +%H:%M:%S)] الوضع=$MODE | المخرج=$OUT_STATE | المنتج=$PROD_STATE ──"
        fi
        sleep 15
    done
}

# ═════════ الحلقة الخارجية — لا تنتهي ═════════
echo "🚀 بدء التشغيل..."
while true; do
    run
    echo "⚠️ توقف الجلسة — إعادة بعد 5 ثوان..."
    sleep 5
done

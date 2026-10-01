#!/bin/bash
set +m

# ═════════ إعدادات ريسبكت ═════════
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
FONT_NAME="Noto Naskh Arabic"
# ══════════════════════════════════

RESTREAM_KEY="${RESTREAM_KEY:-}"
[ -z "$RESTREAM_KEY" ] && { echo "ERR: no key"; exit 1; }
[ -z "$STREAMERS_LIST" ] && { echo "ERR: no streamers"; exit 1; }

UA="Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"
RESTREAM_URL="rtmp://live.restream.io/live/$RESTREAM_KEY"
FIFO="/tmp/relay.ts"

IFS=',' read -r -a STREAMERS <<< "$STREAMERS_LIST"

# قائمة الستريمرز بترتيب عمودي (2-3 صفوف)
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
echo "List L1: $LIST_LINE1"
echo "List L2: $LIST_LINE2"

# تحميل الشعار
LOGO=""
if curl -sL --max-time 25 -A "Mozilla/5.0" "$LOGO_URL" -o /tmp/logo_src.png 2>/dev/null; then
    if [ -s /tmp/logo_src.png ] && file /tmp/logo_src.png 2>/dev/null | grep -qiE "PNG|JPEG|image"; then
        convert /tmp/logo_src.png -resize ${LOGO_W}x /tmp/logo.png 2>/dev/null
        [ -s /tmp/logo.png ] && { LOGO="/tmp/logo.png"; echo "✅ logo OK"; }
    fi
fi
[ -z "$LOGO" ] && echo "⚠️ no logo"

# ═════════ رسم النصوص بـ ImageMagick+Pango (يدعم العربية 100%) ═════════
echo "🖌️ rendering text..."
mkdir -p /tmp/txt && rm -f /tmp/txt/*.png

# السطر الأول: LABEL + قائمة الستريمرز (سطر 1)
convert -background none -fill "$COLOR_L" -stroke "$COLOR_OUTLINE" -strokewidth 1 \
    -font "$FONT_NAME" -pointsize $FS_L \
    pango:"$LABEL $LIST_LINE1" /tmp/txt/l1.png 2>/dev/null

# السطر الثاني: تكملة القائمة
if [ -n "$LIST_LINE2" ]; then
    convert -background none -fill "$COLOR_L" -stroke "$COLOR_OUTLINE" -strokewidth 1 \
        -font "$FONT_NAME" -pointsize $FS_L \
        pango:"$LIST_LINE2" /tmp/txt/l2.png 2>/dev/null
fi

# العنوان الرئيسي
convert -background none -fill "$COLOR_T" -stroke "$COLOR_OUTLINE" -strokewidth $OUTLINE_W \
    -font "$FONT_NAME" -pointsize $FS_T \
    pango:"$TITLE" /tmp/txt/title.png 2>/dev/null

# السطر الثاني
convert -background none -fill "$COLOR_S" -stroke "$COLOR_OUTLINE" -strokewidth $OUTLINE_W \
    -font "$FONT_NAME" -pointsize $FS_S \
    pango:"$SUBTITLE" /tmp/txt/sub.png 2>/dev/null

if [ ! -s /tmp/txt/title.png ]; then
    echo "❌ text render failed"
    cat /tmp/txt/title.png 2>/dev/null
    exit 1
fi
echo "✅ text OK"

# FIFO
rm -f "$FIFO"
mkfifo "$FIFO"
exec 3<>"$FIFO"

# ═════════ دالة بناء فلتر الانتظار ═════════
standby_filter() {
    # المدخلات: 0=color, 1=title.png, 2=sub.png, 3=list1.png, 4=list2.png (إن وجد), 5=logo (إن وجد), ثم anullsrc
    local logo_idx=$1  # فهرس مدخل الشعار أو -1
    local audio_idx=$2 # فهرس مدخل الصوت
    local list2_exists=$3  # 1 أو 0

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
    # بناء مدخلات ffmpeg ديناميكياً
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
    filter=$(standby_filter "$logo_idx" "$audio_idx" "$list2_exists")

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
        echo "❌ standby failed:"; cat /tmp/prod.log; return 1
    fi

    # المخرج
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
        echo "❌ output failed:"; cat /tmp/out.log
        kill -9 $PROD 2>/dev/null
        return 1
    fi
    echo "✅ Live — PROD=$PROD OUT=$OUT"

    ( if [ -n "$GH_TOKEN" ] && [ -n "$GITHUB_RUN_ID" ]; then
        OLD=$(timeout 10 gh run list --workflow="main.yml" --status=in_progress \
              --json databaseId -q ".[].databaseId" 2>/dev/null | \
              awk -v m="$GITHUB_RUN_ID" '$1 < m')
        for R in $OLD; do timeout 8 gh run cancel "$R" 2>/dev/null; done
      fi ) >/tmp/cancel.log 2>&1 &

    MODE="STANDBY"; ACTIVE=""; ACTIVE_IDX=-1; TICK=0

    while true; do
        if ! kill -0 $OUT 2>/dev/null; then
            echo "⚠️ output died"; kill -9 $PROD 2>/dev/null; return 1
        fi
        if ! kill -0 $PROD 2>/dev/null; then
            if [ "$MODE" = "LIVE" ]; then
                MODE="NONE"; ACTIVE=""; ACTIVE_IDX=-1
            else
                # إعادة إطلاق standby
                local f2
                f2=$(standby_filter "$logo_idx" "$audio_idx" "$list2_exists")
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
                FOUND="$S"; FOUND_URL="$URL"; FOUND_IDX=$i
                break
            fi
        done

        if [ -n "$FOUND" ]; then
            if [ "$MODE" != "LIVE" ] || [ "$ACTIVE" != "$FOUND" ]; then
                echo "🎯 -> $FOUND"
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
                    MODE="LIVE"; ACTIVE="$FOUND"; ACTIVE_IDX=$FOUND_IDX
                    echo "✅ $FOUND"
                else
                    echo "⚠️ $FOUND failed"; tail -n 5 /tmp/prod.log; MODE="NONE"
                fi
            fi
        else
            if [ "$MODE" != "STANDBY" ]; then
                echo "⏳ standby"
                kill -9 $PROD 2>/dev/null
                wait $PROD 2>/dev/null
                sleep 1

                local f3
                f3=$(standby_filter "$logo_idx" "$audio_idx" "$list2_exists")
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
                MODE="STANDBY"; ACTIVE=""; ACTIVE_IDX=-1
            fi
        fi

        TICK=$((TICK+1))
        if [ $((TICK % 4)) -eq 0 ]; then
            echo "[$(date -u +%H:%M:%S)] mode=$MODE OUT=$(kill -0 $OUT 2>/dev/null && echo UP || echo DOWN) PROD=$(kill -0 $PROD 2>/dev/null && echo UP || echo DOWN)"
        fi
        sleep 15
    done
}

echo "▶️ starting"
while true; do
    run
    echo "⚠️ restart in 5s"
    sleep 5
done

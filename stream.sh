#!/bin/bash
set +m

# ==============================================================================
# ⚙️⚙️⚙️  إعدادات شاشة الانتظار — ريسبكت  ⚙️⚙️⚙️
# ==============================================================================

STANDBY_TITLE="لم يبدأ ستريمرز ريسبكت البث بعد"
STANDBY_SUBTITLE="جاري انتضار ستريمرز ريسبكت بدأ البث."

STANDBY_EXTRA_ENABLED="no"
STANDBY_EXTRA=""

COLOR_TITLE="&H00FEB4D8"
COLOR_SUBTITLE="&H00F755A8"
COLOR_EXTRA="&H00F755A8"

COLOR_OUTLINE="&H00000000"
COLOR_SHADOW="&H00000000"
OUTLINE_SIZE=2
SHADOW_SIZE=1

BG_COLOR="0x140024"

FONT_SIZE_TITLE=78
FONT_SIZE_SUBTITLE=54
FONT_SIZE_EXTRA=54

POS_TITLE=420
POS_SUBTITLE=520
POS_EXTRA=580

LOGO_URL="https://i.top4top.io/p_39264fv5g0.png"
LOGO_FILE="/tmp/logo.png"
LOGO_WIDTH=380
LOGO_BOTTOM_MARGIN=80

LOGO_SHOW_DURATION=5
LOGO_CYCLE=7

# ==============================================================================

RESTREAM_KEY="${RESTREAM_KEY:-}"
QUALITY="${STREAM_QUALITY:-best}"
[[ "$RESTREAM_KEY" == "X" || "$RESTREAM_KEY" == "x" ]] && RESTREAM_KEY=""

if [ -z "$STREAMERS_LIST" ]; then echo "❌ قائمة الستريمرز فارغة"; exit 1; fi
if [ -z "$RESTREAM_KEY" ]; then echo "❌ مفتاح ريستريم فارغ"; exit 1; fi

echo "🔑 مفتاح ريستريم يبدأ بـ: ${RESTREAM_KEY:0:10}..."
echo "🔧 ffmpeg: $(which ffmpeg) — $(ffmpeg -version 2>&1 | head -1 | awk '{print $3}')"
echo "🔧 streamlink: $(which streamlink) — $(streamlink --version 2>&1)"

echo "⬇️ تحميل شعار..."
curl -sL --max-time 20 -A "Mozilla/5.0" "$LOGO_URL" -o "$LOGO_FILE" || true
if [ ! -s "$LOGO_FILE" ]; then
    echo "⚠️ فشل تحميل الشعار — سيعمل البث بدونه."
    LOGO_FILE=""
else
    if file "$LOGO_FILE" | grep -qiE "PNG|JPEG|JPG|image"; then
        echo "✅ الشعار صالح: $(file -b "$LOGO_FILE")"
    else
        echo "⚠️ الملف ليس صورة (ربما HTML) — تجاهل الشعار."
        head -c 200 "$LOGO_FILE"; echo ""
        LOGO_FILE=""
    fi
fi

IFS=',' read -r -a STREAMERS_RANK <<< "$STREAMERS_LIST"

if fc-list : family | grep -qi "Noto Naskh Arabic"; then
    FONT_NAME="Noto Naskh Arabic"
elif fc-list : family | grep -qi "Scheherazade"; then
    FONT_NAME="Scheherazade New"
else
    FONT_NAME="Sans"
fi
echo "🔤 الخط: $FONT_NAME"

RESTREAM_URL="rtmp://live.restream.io/live/$RESTREAM_KEY"
FIFO="/tmp/relay.ts"
UA="Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"

OUTPUT_PID=""
PRODUCER_PID=""
CURRENT_MODE="NONE"
CURRENT_ACTIVE_STREAMER=""
CURRENT_ACTIVE_INDEX=-1

cleanup() {
    echo "🧹 إيقاف العمليات..."
    trap - EXIT INT TERM
    for P in "$PRODUCER_PID" "$OUTPUT_PID"; do
        [ -n "$P" ] && kill -9 "$P" 2>/dev/null
        [ -n "$P" ] && wait "$P" 2>/dev/null
    done
    exit 0
}
trap cleanup EXIT INT TERM

setup_fifo() {
    rm -f "$FIFO"
    mkfifo "$FIFO"
    exec 3<>"$FIFO"
}

start_output() {
    local attempt=1
    while [ $attempt -le 3 ]; do
        echo "🔗 فتح اتصال ثابت مع ريستريم (محاولة $attempt/3)..."
        ffmpeg -y -hide_banner -loglevel warning -nostdin \
          -thread_queue_size 512 \
          -probesize 32 -analyzeduration 0 \
          -f mpegts -i "$FIFO" \
          -c copy \
          -max_muxing_queue_size 4096 \
          -flvflags no_duration_filesize \
          -f flv "$RESTREAM_URL" >/tmp/ffmpeg_out.log 2>&1 &
        OUTPUT_PID=$!
        sleep 4
        if kill -0 "$OUTPUT_PID" 2>/dev/null; then
            echo "✅ المخرج شغال (PID: $OUTPUT_PID)"
            return 0
        fi
        echo "⚠️ محاولة $attempt فشلت:"
        tail -n 5 /tmp/ffmpeg_out.log
        attempt=$((attempt + 1))
        sleep 2
    done
    echo "❌ فشل تشغيل المخرج بعد 3 محاولات."
    exit 1
}

cancel_old_runs() {
    if [ -z "$GH_TOKEN" ] || [ -z "$GITHUB_RUN_ID" ]; then
        echo "ℹ️ بدون GH_TOKEN — تخطي."
        return 0
    fi
    echo "🛑 إلغاء الرنات القديمة..."
    OLD_RUNS=$(timeout 15 gh run list --workflow="main.yml" --status=in_progress \
      --json databaseId -q ".[].databaseId" 2>/dev/null | grep -v "$GITHUB_RUN_ID" || true)
    for RUN_ID in $OLD_RUNS; do
        echo "   إلغاء: $RUN_ID"
        timeout 10 gh run cancel "$RUN_ID" 2>/dev/null || true
    done
    echo "✅ انتهى إلغاء الرنات."
}

generate_ass() {
    EXTRA_STYLE_LINE=""
    EXTRA_EVENT_LINE=""
    if [ "$STANDBY_EXTRA_ENABLED" == "yes" ]; then
        EXTRA_STYLE_LINE="Style: Extra,$FONT_NAME,$FONT_SIZE_EXTRA,$COLOR_EXTRA,&H00000000,$COLOR_OUTLINE,$COLOR_SHADOW,-1,0,0,0,100,100,0,0,1,$OUTLINE_SIZE,$SHADOW_SIZE,8,10,10,$POS_EXTRA,1"
        EXTRA_EVENT_LINE="Dialogue: 0,0:00:00.00,9:59:59.99,Extra,,0,0,0,,{\\fad(600,600)}$STANDBY_EXTRA"
    fi

    cat > /tmp/standby.ass <<EOF
[Script Info]
ScriptType: v4.00+
PlayResX: 1920
PlayResY: 1080
ScaledBorderAndShadow: yes

[V4+ Styles]
Format: Name, Fontname, Fontsize, PrimaryColour, SecondaryColour, OutlineColour, BackColour, Bold, Italic, Underline, StrikeOut, ScaleX, ScaleY, Spacing, Angle, BorderStyle, Outline, Shadow, Alignment, MarginL, MarginR, MarginV, Encoding
Style: Title,$FONT_NAME,$FONT_SIZE_TITLE,$COLOR_TITLE,&H00000000,$COLOR_OUTLINE,$COLOR_SHADOW,-1,0,0,0,100,100,0,0,1,$OUTLINE_SIZE,$SHADOW_SIZE,8,10,10,$POS_TITLE,1
Style: Subtitle,$FONT_NAME,$FONT_SIZE_SUBTITLE,$COLOR_SUBTITLE,&H00000000,$COLOR_OUTLINE,$COLOR_SHADOW,-1,0,0,0,100,100,0,0,1,$OUTLINE_SIZE,$SHADOW_SIZE,8,10,10,$POS_SUBTITLE,1
$EXTRA_STYLE_LINE

[Events]
Format: Layer, Start, End, Style, Name, MarginL, MarginR, MarginV, Effect, Text
Dialogue: 0,0:00:00.00,9:59:59.99,Title,,0,0,0,,{\\fad(600,600)}$STANDBY_TITLE
Dialogue: 0,0:00:00.00,9:59:59.99,Subtitle,,0,0,0,,{\\fad(600,600)}$STANDBY_SUBTITLE
$EXTRA_EVENT_LINE
EOF
}

stop_producer() {
    if [ -n "$PRODUCER_PID" ]; then
        kill -9 "$PRODUCER_PID" 2>/dev/null
        wait "$PRODUCER_PID" 2>/dev/null
        PRODUCER_PID=""
    fi
    sleep 1
}

start_producer_standby() {
    stop_producer
    generate_ass
    echo "⏳ منتج شاشة الانتظار..."

    if [ -n "$LOGO_FILE" ]; then
        ffmpeg -y -hide_banner -loglevel warning -nostdin \
          -re -f lavfi -i color=c=${BG_COLOR}:s=1920x1080:r=30 \
          -loop 1 -i "$LOGO_FILE" \
          -f lavfi -i anullsrc=r=44100:cl=stereo \
          -filter_complex "[0:v]ass=/tmp/standby.ass[base];[1:v]scale=${LOGO_WIDTH}:-2[logo];[base][logo]overlay=x=(W-w)/2:y=H-h-${LOGO_BOTTOM_MARGIN}:enable='lt(mod(t\,${LOGO_CYCLE})\,${LOGO_SHOW_DURATION})'[vout]" \
          -map "[vout]" -map 2:a:0 \
          -c:v libx264 -preset ultrafast -tune zerolatency -pix_fmt yuv420p -r 30 -g 60 \
          -c:a aac -b:a 128k -ar 44100 -ac 2 \
          -max_muxing_queue_size 4096 \
          -f mpegts "$FIFO" >/tmp/ffmpeg_in.log 2>&1 &
        PRODUCER_PID=$!
    else
        ffmpeg -y -hide_banner -loglevel warning -nostdin \
          -re -f lavfi -i color=c=${BG_COLOR}:s=1920x1080:r=30 \
          -f lavfi -i anullsrc=r=44100:cl=stereo \
          -map 0:v:0 -map 1:a:0 \
          -vf "ass=/tmp/standby.ass" \
          -c:v libx264 -preset ultrafast -tune zerolatency -pix_fmt yuv420p -r 30 -g 60 \
          -c:a aac -b:a 128k -ar 44100 -ac 2 \
          -max_muxing_queue_size 4096 \
          -f mpegts "$FIFO" >/tmp/ffmpeg_in.log 2>&1 &
        PRODUCER_PID=$!
    fi

    sleep 3
    if ! kill -0 "$PRODUCER_PID" 2>/dev/null; then
        echo "❌ منتج الانتظار مات فوراً! التفاصيل:"
        cat /tmp/ffmpeg_in.log
        PRODUCER_PID=""
        return 1
    fi
    return 0
}

start_producer_live() {
    local M3U8="$1"
    local NAME="$2"
    stop_producer
    echo "🔴 منتج مباشر: [$NAME] — video copy + audio AAC..."
    ffmpeg -y -hide_banner -loglevel warning -nostdin \
      -headers "User-Agent: $UA" \
      -reconnect 1 -reconnect_at_eof 1 -reconnect_streamed 1 -reconnect_delay_max 5 \
      -analyzeduration 2000000 -probesize 2000000 \
      -fflags +genpts+igndts \
      -i "$M3U8" \
      -c:v copy \
      -c:a aac -b:a 128k -ar 44100 -ac 2 \
      -max_muxing_queue_size 4096 \
      -muxdelay 0.1 -muxpreload 0.1 \
      -f mpegts "$FIFO" >/tmp/ffmpeg_in.log 2>&1 &
    PRODUCER_PID=$!

    sleep 6
    if ! kill -0 "$PRODUCER_PID" 2>/dev/null; then
        echo "⚠️ فشل [$NAME]."
        tail -n 5 /tmp/ffmpeg_in.log
        return 1
    fi
    return 0
}

setup_fifo
start_output
start_producer_standby
CURRENT_MODE="STANDBY"

( cancel_old_runs ) >/tmp/cancel_old.log 2>&1 &

sleep 2

DIAG_TICK=0

while true; do
    if ! kill -0 "$OUTPUT_PID" 2>/dev/null; then
        echo "⚠️ المخرج توقف — إعادة تشغيل..."
        start_output || exit 1
    fi

    FOUND_LIVE=false
    SELECTED_STREAMER=""
    SELECTED_M3U8=""
    SELECTED_INDEX=-1

    CHECK_LIMIT=${#STREAMERS_RANK[@]}
    if [ "$CURRENT_MODE" == "LIVE" ] && [ "$CURRENT_ACTIVE_INDEX" -ge 0 ]; then
        CHECK_LIMIT=$((CURRENT_ACTIVE_INDEX + 1))
    fi

    for ((i=0; i<CHECK_LIMIT; i++)); do
        STREAMER=$(echo "${STREAMERS_RANK[$i]}" | xargs)
        [ -z "$STREAMER" ] && continue
        M3U8=$(streamlink --http-header "User-Agent=$UA" --hls-live-edge 3 \
               --stream-timeout 15 "https://kick.com/$STREAMER" "$QUALITY" \
               --stream-url 2>/dev/null | grep -m1 "^http")
        if [ -n "$M3U8" ]; then
            FOUND_LIVE=true
            SELECTED_STREAMER="$STREAMER"
            SELECTED_M3U8="$M3U8"
            SELECTED_INDEX=$i
            break
        fi
    done

    if [ "$FOUND_LIVE" = true ]; then
        NEED_SWITCH=false
        if [ "$CURRENT_MODE" != "LIVE" ]; then NEED_SWITCH=true
        elif [ "$CURRENT_ACTIVE_STREAMER" != "$SELECTED_STREAMER" ]; then NEED_SWITCH=true
        elif [ -n "$PRODUCER_PID" ] && ! kill -0 "$PRODUCER_PID" 2>/dev/null; then NEED_SWITCH=true
        fi

        if [ "$NEED_SWITCH" = true ]; then
            echo "🎯 التحويل إلى: $SELECTED_STREAMER"
            if start_producer_live "$SELECTED_M3U8" "$SELECTED_STREAMER"; then
                CURRENT_ACTIVE_STREAMER="$SELECTED_STREAMER"
                CURRENT_ACTIVE_INDEX=$SELECTED_INDEX
                CURRENT_MODE="LIVE"
            else
                if [ "$CURRENT_MODE" != "STANDBY" ]; then
                    start_producer_standby
                    CURRENT_MODE="STANDBY"
                    CURRENT_ACTIVE_STREAMER=""
                    CURRENT_ACTIVE_INDEX=-1
                fi
            fi
        fi
    else
        if [ "$CURRENT_MODE" != "STANDBY" ] || [ -z "$PRODUCER_PID" ] || \
           ! kill -0 "$PRODUCER_PID" 2>/dev/null; then
            echo "⏳ لا يوجد بث — شاشة الانتظار..."
            start_producer_standby
            CURRENT_MODE="STANDBY"
            CURRENT_ACTIVE_STREAMER=""
            CURRENT_ACTIVE_INDEX=-1
        fi
    fi

    DIAG_TICK=$((DIAG_TICK + 1))
    if [ $((DIAG_TICK % 4)) -eq 0 ]; then
        echo "── DIAG $(date -u +%H:%M:%S)Z ──"
        echo "OUT: $(kill -0 $OUTPUT_PID 2>/dev/null && echo حي || echo ميت) | PROD: $(kill -0 $PRODUCER_PID 2>/dev/null && echo حي || echo ميت)"
        echo "OUT log: $(tail -n 1 /tmp/ffmpeg_out.log 2>/dev/null || echo فارغ)"
        echo "IN  log: $(tail -n 1 /tmp/ffmpeg_in.log 2>/dev/null || echo فارغ)"
    fi

    sleep 15
done

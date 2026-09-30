#!/bin/bash
set -u

RESTREAM_KEY="${RESTREAM_KEY:-}"
YOUTUBE_KEY="${YOUTUBE_KEY:-}"
QUALITY="${STREAM_QUALITY:-best}"
DEST="${STREAM_DEST:-restream}"

[[ "$YOUTUBE_KEY" == "X" || "$YOUTUBE_KEY" == "x" ]] && YOUTUBE_KEY=""
[[ "$RESTREAM_KEY" == "X" || "$RESTREAM_KEY" == "x" ]] && RESTREAM_KEY=""

[ -z "$STREAMERS_LIST" ] && { echo "❌ STREAMERS_LIST فارغ"; exit 1; }
IFS=',' read -r -a STREAMERS_RANK <<< "$STREAMERS_LIST"

if fc-list : family 2>/dev/null | grep -qi "Noto Naskh Arabic"; then
    FONT_NAME="Noto Naskh Arabic"
else
    FONT_NAME="Sans"
fi

PIPE=/tmp/stream_pipe
OUTPUT_PID=""
PRODUCER_PID=""
CURRENT_MODE="NONE"
CURRENT_ACTIVE_STREAMER=""
CURRENT_ACTIVE_INDEX=-1

log() { echo "[$(date '+%H:%M:%S')] $*"; }

cleanup() {
    log "🧹 إغلاق..."
    [ -n "$PRODUCER_PID" ] && kill -9 "$PRODUCER_PID" 2>/dev/null
    [ -n "$OUTPUT_PID" ] && kill -9 "$OUTPUT_PID" 2>/dev/null
    exec 3>&- 2>/dev/null
    rm -f "$PIPE"
    exit 0
}
trap cleanup EXIT INT TERM

get_outputs() {
    if [ "$DEST" = "youtube" ]; then
        echo "-f flv rtmp://a.rtmp.youtube.com/live2/$YOUTUBE_KEY"
    elif [ "$DEST" = "restream" ]; then
        echo "-f flv rtmp://live.restream.io/live/$RESTREAM_KEY"
    else
        echo "-f flv rtmp://live.restream.io/live/$RESTREAM_KEY -f flv rtmp://a.rtmp.youtube.com/live2/$YOUTUBE_KEY"
    fi
}

stop_producer() {
    if [ -n "$PRODUCER_PID" ]; then
        kill -9 "$PRODUCER_PID" 2>/dev/null
        wait "$PRODUCER_PID" 2>/dev/null
        PRODUCER_PID=""
    fi
}

generate_ass() {
    cat <<EOF > /tmp/standby.ass
[Script Info]
ScriptType: v4.00+
PlayResX: 1920
PlayResY: 1080
ScaledBorderAndShadow: yes

[V4+ Styles]
Format: Name, Fontname, Fontsize, PrimaryColour, SecondaryColour, OutlineColour, BackColour, Bold, Italic, Underline, StrikeOut, ScaleX, ScaleY, Spacing, Angle, BorderStyle, Outline, Shadow, Alignment, MarginL, MarginR, MarginV, Encoding
Style: Title,$FONT_NAME,60,&H00FEB4D8,&H00000000,&H00000000,&H80000000,-1,0,0,0,100,100,0,0,1,2,1,8,10,10,420,1
Style: Subtitle,$FONT_NAME,40,&H00F755A8,&H00000000,&H00000000,&H80000000,-1,0,0,0,100,100,0,0,1,2,1,8,10,10,520,1

[Events]
Format: Layer, Start, End, Style, Name, MarginL, MarginR, MarginV, Effect, Text
Dialogue: 0,0:00:00.00,9:59:59.99,Title,,0,0,0,,{\fad(600,600)}لم يبدأ البث المباشر بعد...
Dialogue: 0,0:00:00.00,9:59:59.99,Subtitle,,0,0,0,,{\fad(600,600)}جاري انتظار قائمة ستريمرز ريسبكت
EOF
}

start_standby() {
    generate_ass
    stop_producer
    ffmpeg -hide_banner -loglevel error -nostdin \
      -re -f lavfi -i color=c=0x140024:s=1920x1080:r=60 \
      -f lavfi -i anullsrc=r=44100:cl=stereo \
      -map 0:v:0 -map 1:a:0 \
      -vf "ass=/tmp/standby.ass" \
      -c:v libx264 -preset ultrafast -tune zerolatency -pix_fmt yuv420p -r 60 -g 120 -b:v 2500k \
      -c:a aac -b:a 128k -ar 44100 \
      -f mpegts -mpegts_flags +resend_headers \
      -mpegts_start_pid 256 -mpegts_pmt_start_pid 4096 - >&3 2>/tmp/producer.log &
    PRODUCER_PID=$!
}

start_live() {
    local M3U8="$1"
    stop_producer
    ffmpeg -hide_banner -loglevel error -nostdin \
      -headers "User-Agent: Mozilla/5.0 (Windows NT 10.0; Win64; x64)" \
      -analyzeduration 2000000 -probesize 2000000 \
      -reconnect 1 -reconnect_at_eof 1 -reconnect_streamed 1 -reconnect_delay_max 5 \
      -i "$M3U8" \
      -c copy -f mpegts -mpegts_flags +resend_headers \
      -mpegts_start_pid 256 -mpegts_pmt_start_pid 4096 - >&3 2>/tmp/producer.log &
    PRODUCER_PID=$!
}

# بدء output ffmpeg مرة واحدة فقط (بدون حلقات retry معقدة)
start_output_pipeline() {
    rm -f "$PIPE"; mkfifo "$PIPE"
    exec 3<> "$PIPE"
    OUTPUTS=$(get_outputs)
    ffmpeg -hide_banner -loglevel warning -nostdin \
      -fflags +genpts+igndts+discardcorrupt \
      -f mpegts -i "$PIPE" \
      -c copy -bsf:a aac_adtstoasc \
      -flvflags no_duration_filesize -muxdelay 0.1 \
      $OUTPUTS > /tmp/output.log 2>&1 &
    OUTPUT_PID=$!
    log "✅ Output RTMP PID=$OUTPUT_PID"
}

UA="Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"

log "🚀 بدء التشغيل"
start_output_pipeline
# أعطِ output ffmpeg فرصة للاتصال قبل تغذية الأنبوب
sleep 2
start_standby
CURRENT_MODE="STANDBY"

while true; do
    # مراقبة Output RTMP
    if ! kill -0 "$OUTPUT_PID" 2>/dev/null; then
        log "⚠️ Output توقف — إعادة بناء"
        stop_producer
        exec 3>&- 2>/dev/null
        sleep 2
        start_output_pipeline
        sleep 2
        start_standby
        CURRENT_MODE="STANDBY"
        CURRENT_ACTIVE_STREAMER=""
        CURRENT_ACTIVE_INDEX=-1
        continue
    fi

    # مراقبة Producer
    if [ -n "$PRODUCER_PID" ] && ! kill -0 "$PRODUCER_PID" 2>/dev/null; then
        PRODUCER_PID=""
        if [ "$CURRENT_MODE" = "LIVE" ]; then
            CURRENT_ACTIVE_STREAMER=""
            CURRENT_ACTIVE_INDEX=-1
            CURRENT_MODE="NONE"
        fi
    fi

    FOUND_LIVE=false
    SELECTED_STREAMER=""; SELECTED_M3U8=""; SELECTED_INDEX=-1

    CHECK_LIMIT=${#STREAMERS_RANK[@]}
    if [ "$CURRENT_MODE" = "LIVE" ] && [ "$CURRENT_ACTIVE_INDEX" -ge 0 ]; then
        CHECK_LIMIT=$((CURRENT_ACTIVE_INDEX + 1))
    fi

    for ((i=0; i<CHECK_LIMIT; i++)); do
        STREAMER=$(echo "${STREAMERS_RANK[$i]}" | xargs)
        [ -z "$STREAMER" ] && continue
        M3U8=$(timeout 15 streamlink --http-header "User-Agent=$UA" \
               --hls-live-edge 3 --stream-timeout 8 \
               "https://kick.com/$STREAMER" "$QUALITY" --stream-url 2>/dev/null | grep -m1 "^http")
        if [ -n "$M3U8" ]; then
            VCODEC=$(timeout 10 ffprobe -v error -select_streams v:0 \
                     -show_entries stream=codec_name -of default=nw=1:nk=1 \
                     -headers "User-Agent: $UA" "$M3U8" 2>/dev/null)
            if [ "$VCODEC" = "h264" ]; then
                FOUND_LIVE=true
                SELECTED_STREAMER="$STREAMER"
                SELECTED_M3U8="$M3U8"
                SELECTED_INDEX=$i
                break
            else
                log "⏭️ [$STREAMER] كوديك غير مدعوم: $VCODEC"
            fi
        fi
    done

    if [ "$FOUND_LIVE" = true ]; then
        if [ "$CURRENT_MODE" != "LIVE" ] || [ "$CURRENT_ACTIVE_STREAMER" != "$SELECTED_STREAMER" ] || [ -z "$PRODUCER_PID" ]; then
            log "🎯 تبديل إلى: $SELECTED_STREAMER"
            start_live "$SELECTED_M3U8"
            sleep 4
            if kill -0 "$PRODUCER_PID" 2>/dev/null; then
                CURRENT_ACTIVE_STREAMER="$SELECTED_STREAMER"
                CURRENT_ACTIVE_INDEX=$SELECTED_INDEX
                CURRENT_MODE="LIVE"
                log "✅ بث حي: $SELECTED_STREAMER"
            else
                log "❌ فشل $SELECTED_STREAMER"
            fi
        fi
    else
        if [ "$CURRENT_MODE" != "STANDBY" ] || [ -z "$PRODUCER_PID" ]; then
            log "⏳ لا ستريمر — شاشة انتظار"
            start_standby
            CURRENT_ACTIVE_STREAMER=""
            CURRENT_ACTIVE_INDEX=-1
            CURRENT_MODE="STANDBY"
        fi
    fi

    sleep 10
done

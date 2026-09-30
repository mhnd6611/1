#!/bin/bash
# ==============================================================================
# نظام البث الذكي 24/7 - معمارية FIFO النهائية مع التحقق الفعال من تحرير RTMP
# ==============================================================================

RESTREAM_KEY="${RESTREAM_KEY:-}"
YOUTUBE_KEY="${YOUTUBE_KEY:-}"
QUALITY="${STREAM_QUALITY:-best}"
DEST="${STREAM_DEST:-restream}"

if [[ "$YOUTUBE_KEY" == "X" || "$YOUTUBE_KEY" == "x" ]]; then YOUTUBE_KEY=""; fi
if [[ "$RESTREAM_KEY" == "X" || "$RESTREAM_KEY" == "x" ]]; then RESTREAM_KEY=""; fi

[ -z "$STREAMERS_LIST" ] && { echo "❌ لا توجد قائمة ستريمرز"; exit 1; }
IFS=',' read -r -a STREAMERS_RANK <<< "$STREAMERS_LIST"

FONT_NAME="Noto Naskh Arabic"
PIPE=/tmp/stream_pipe
OUTPUT_PID=""
PRODUCER_PID=""
CURRENT_MODE="NONE"
CURRENT_ACTIVE_STREAMER=""
CURRENT_ACTIVE_INDEX=-1

cleanup() {
    echo "🧹 إيقاف العمليات..."
    trap - EXIT INT TERM
    [ -n "$PRODUCER_PID" ] && kill -9 "$PRODUCER_PID" 2>/dev/null
    [ -n "$OUTPUT_PID" ] && kill -9 "$OUTPUT_PID" 2>/dev/null
    exec 3>&- 2>/dev/null
    rm -f "$PIPE"
    exit 0
}
trap cleanup EXIT INT TERM

get_outputs() {
    if [ "$DEST" == "youtube" ]; then
        echo "-f flv rtmp://a.rtmp.youtube.com/live2/$YOUTUBE_KEY"
    elif [ "$DEST" == "restream" ]; then
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

# --- 1. عملية الإخراج الدائمة مع حلقة تحقق من تحرير RTMP ---
start_output_pipeline() {
    rm -f "$PIPE"; mkfifo "$PIPE"
    exec 3<> "$PIPE"
    OUTPUTS=$(get_outputs)
    
    local RETRY=0
    local MAX_RETRIES=10
    
    while [ $RETRY -lt $MAX_RETRIES ]; do
        echo "🔄 محاولة ربط اتصال RTMP (محاولة $((RETRY+1))/$MAX_RETRIES)..."
        
        ffmpeg -hide_banner -loglevel warning -nostdin \
          -fflags +genpts+igndts+discardcorrupt \
          -f mpegts -i "$PIPE" \
          -c copy -bsf:a aac_adtstoasc \
          -flvflags no_duration_filesize -muxdelay 0.1 \
          $OUTPUTS >/tmp/output.log 2>&1 &
        OUTPUT_PID=$!
        
        sleep 4
        if kill -0 "$OUTPUT_PID" 2>/dev/null; then
            echo "✅ تم الاتصال بسيرفر RTMP بنجاح! PID=$OUTPUT_PID"
            return 0
        fi
        
        echo "⏳ مفتاح RTMP ما زال مشغولاً من السيرفر. المحاولة مجدداً..."
        RETRY=$((RETRY + 1))
        sleep 3
    done
    
    echo "❌ فشل الاتصال بـ RTMP بعد عدة محاولات."
    exit 1
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

# --- 2. منتج شاشة الانتظار ---
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
      -f mpegts -mpegts_start_pid 256 -mpegts_pmt_start_pid 4096 -mpegts_flags +resend_headers - >&3 2>/tmp/producer.log &
    PRODUCER_PID=$!
}

# --- 3. منتج البث الحي (نقل مباشر مع توحيد PIDs) ---
start_live() {
    local M3U8="$1"
    local STREAMER="$2"
    stop_producer
    ffmpeg -hide_banner -loglevel error -nostdin \
      -headers "User-Agent: Mozilla/5.0 (Windows NT 10.0; Win64; x64)" \
      -analyzeduration 2000000 -probesize 2000000 \
      -reconnect 1 -reconnect_at_eof 1 -reconnect_streamed 1 -reconnect_delay_max 5 \
      -i "$M3U8" \
      -c copy \
      -f mpegts -mpegts_start_pid 256 -mpegts_pmt_start_pid 4096 -mpegts_flags +resend_headers - >&3 2>/tmp/producer.log &
    PRODUCER_PID=$!
}

UA="Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"

start_output_pipeline
start_standby
CURRENT_MODE="STANDBY"

sleep 2

while true; do
    # مراقبة الاتصال الرئيسي
    if ! kill -0 "$OUTPUT_PID" 2>/dev/null; then
        echo "⚠️ انقطع الاتصال الرئيسي - إعادة بناء Pipeline"
        stop_producer
        exec 3>&- 2>/dev/null
        start_output_pipeline
        CURRENT_MODE="NONE"
        CURRENT_ACTIVE_STREAMER=""
        CURRENT_ACTIVE_INDEX=-1
    fi

    # مراقبة المنتج
    if [ -n "$PRODUCER_PID" ] && ! kill -0 "$PRODUCER_PID" 2>/dev/null; then
        PRODUCER_PID=""
        if [ "$CURRENT_MODE" == "LIVE" ]; then
            CURRENT_ACTIVE_STREAMER=""
            CURRENT_ACTIVE_INDEX=-1
            CURRENT_MODE="NONE"
        fi
    fi

    FOUND_LIVE=false
    SELECTED_STREAMER=""; SELECTED_M3U8=""; SELECTED_INDEX=-1

    CHECK_LIMIT=${#STREAMERS_RANK[@]}
    if [ "$CURRENT_MODE" == "LIVE" ] && [ "$CURRENT_ACTIVE_INDEX" -ge 0 ]; then
        CHECK_LIMIT=$((CURRENT_ACTIVE_INDEX + 1))
    fi

    for ((i=0; i<CHECK_LIMIT; i++)); do
        STREAMER=$(echo "${STREAMERS_RANK[$i]}" | xargs)
        [ -z "$STREAMER" ] && continue
        
        M3U8=$(timeout 15 streamlink --http-header "User-Agent=$UA" \
               --stream-sorting-exclude "hevc,av1" \
               --hls-live-edge 3 --stream-timeout 8 \
               "https://kick.com/$STREAMER" "$QUALITY" --stream-url 2>/dev/null | grep -m1 "^http")
               
        if [ -n "$M3U8" ]; then
            # التحقق الفعلي من الكوديك بـ ffprobe (قبول H.264 فقط)
            CODEC=$(timeout 5 ffprobe -v error -select_streams v:0 -show_entries stream=codec_name -of default=noprintwrappers=1:nokey=1 "$M3U8" 2>/dev/null)
            if [ "$CODEC" == "h264" ]; then
                FOUND_LIVE=true
                SELECTED_STREAMER="$STREAMER"
                SELECTED_M3U8="$M3U8"
                SELECTED_INDEX=$i
                break
            fi
        fi
    done

    if [ "$FOUND_LIVE" = true ]; then
        NEED_SWITCH=false
        if [ "$CURRENT_MODE" != "LIVE" ] || [ "$CURRENT_ACTIVE_STREAMER" != "$SELECTED_STREAMER" ] || [ -z "$PRODUCER_PID" ]; then
            NEED_SWITCH=true
        fi

        if [ "$NEED_SWITCH" = true ]; then
            echo "🎯 تبديل إلى: $SELECTED_STREAMER"
            start_live "$SELECTED_M3U8" "$SELECTED_STREAMER"
            sleep 4
            if kill -0 "$PRODUCER_PID" 2>/dev/null; then
                CURRENT_ACTIVE_STREAMER="$SELECTED_STREAMER"
                CURRENT_ACTIVE_INDEX=$SELECTED_INDEX
                CURRENT_MODE="LIVE"
                echo "✅ تم البث بنجاح: $SELECTED_STREAMER"
            fi
        fi
    else
        if [ "$CURRENT_MODE" != "STANDBY" ] || [ -z "$PRODUCER_PID" ]; then
            echo "⏳ لا يوجد ستريمر متصل - شاشة الانتظار"
            start_standby
            CURRENT_ACTIVE_STREAMER=""
            CURRENT_ACTIVE_INDEX=-1
            CURRENT_MODE="STANDBY"
        fi
    fi

    sleep 15
done

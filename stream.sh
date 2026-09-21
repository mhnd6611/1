#!/bin/bash

# ==============================================================================
# نظام البث الذكي 24/7 - البث المتواصل (Seamless Stream - بدون فتح بث جديد)
# ==============================================================================

RESTREAM_KEY="${RESTREAM_KEY:-}"
YOUTUBE_KEY="${YOUTUBE_KEY:-}"
QUALITY="${STREAM_QUALITY:-best}"
DEST="${STREAM_DEST:-restream}"

# تنظيف المفاتيح
if [[ "$YOUTUBE_KEY" == "X" || "$YOUTUBE_KEY" == "x" ]]; then YOUTUBE_KEY=""; fi
if [[ "$RESTREAM_KEY" == "X" || "$RESTREAM_KEY" == "x" ]]; then RESTREAM_KEY=""; fi

if [ -z "$STREAMERS_LIST" ]; then
    echo "❌ خطأ: لم يتم جلب أي قائمة ستريمرز من ملف الـ YAML!"
    exit 1
fi

IFS=',' read -r -a STREAMERS_RANK <<< "$STREAMERS_LIST"

if fc-list : family | grep -qi "Noto Naskh Arabic"; then
    FONT_NAME="Noto Naskh Arabic"
elif fc-list : family | grep -qi "Scheherazade"; then
    FONT_NAME="Scheherazade New"
else
    FONT_NAME="Sans"
fi

PIPE_PATH="/tmp/live_stream_pipe"
rm -f "$PIPE_PATH"
mkfifo "$PIPE_PATH"

FFMPEG_PID=""
INPUT_PID=""
CURRENT_MODE="NONE"
CURRENT_ACTIVE_STREAMER=""
CURRENT_ACTIVE_INDEX=-1

cleanup() {
    echo "🧹 إيقاف جميع العمليات..."
    trap - EXIT INT TERM
    [ -n "$INPUT_PID" ] && kill -9 "$INPUT_PID" 2>/dev/null
    [ -n "$FFMPEG_PID" ] && kill -9 "$FFMPEG_PID" 2>/dev/null
    rm -f "$PIPE_PATH"
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

generate_initial_ass() {
    cat <<EOF > /tmp/initial_standby.ass
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
Dialogue: 0,0:00:00.00,9:59:59.99,Subtitle,,0,0,0,,{\fad(600,600)}جاري انتظار دخول أحد الستريمرز في القائمة
EOF
}

generate_initial_ass

# 1. إطلاق عملية FFmpeg الرئيسية الدائمة نحو الخادم (لا تتوقف إطلاقاً)
OUTPUTS=$(get_outputs)
ffmpeg -hide_banner -loglevel error -nostdin \
  -re -i "$PIPE_PATH" \
  -c:v libx264 -preset ultrafast -tune zerolatency -pix_fmt yuv420p -r 60 -g 120 -b:v 4000k \
  -c:a aac -b:a 128k -ar 44100 \
  -flvflags no_duration_filesize \
  $OUTPUTS >/tmp/ffmpeg_master.log 2>&1 &
FFMPEG_PID=$!

stop_current_input() {
    if [ -n "$INPUT_PID" ]; then
        kill -9 "$INPUT_PID" 2>/dev/null
        INPUT_PID=""
    fi
}

start_standby_feed() {
    stop_current_input
    echo "⏳ تحويل التغذية لشاشة الانتظار دون إغلاق البث..."
    
    ffmpeg -hide_banner -loglevel error -nostdin \
      -re -f lavfi -i color=c=0x140024:s=1920x1080:r=60 \
      -f lavfi -i anullsrc=r=44100:cl=stereo \
      -map 0:v:0 -map 1:a:0 \
      -vf "ass=/tmp/initial_standby.ass" \
      -c:v libx264 -preset ultrafast -tune zerolatency -pix_fmt yuv420p -r 60 -g 120 -b:v 2500k \
      -c:a aac -b:a 128k -ar 44100 \
      -f mpegts "$PIPE_PATH" >/dev/null 2>&1 &
    INPUT_PID=$!
}

start_live_feed() {
    local STREAMER_NAME="$1"
    stop_current_input
    echo "🔴 تحويل التغذية للستريمر: [$STREAMER_NAME]..."

    streamlink --http-header "User-Agent=$UA" "https://kick.com/$STREAMER_NAME" "$QUALITY" --stdout 2>/dev/null | \
    ffmpeg -hide_banner -loglevel error -nostdin \
      -i pipe:0 \
      -c:v libx264 -preset ultrafast -tune zerolatency -pix_fmt yuv420p -r 60 -g 120 -b:v 4500k \
      -c:a aac -b:a 128k -ar 44100 \
      -f mpegts "$PIPE_PATH" >/dev/null 2>&1 &
    INPUT_PID=$!
}

UA="Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"

sleep 3

while true; do
    # التأكد من أن السيرفر الرئيسي ما زال يعالج
    if ! kill -0 "$FFMPEG_PID" 2>/dev/null; then
        echo "❌ خطأ: انقطع الاتصال الرئيسي، إعادة التشغيل..."
        break
    fi

    FOUND_LIVE=false
    SELECTED_STREAMER=""
    SELECTED_INDEX=-1

    CHECK_LIMIT=${#STREAMERS_RANK[@]}
    if [ "$CURRENT_MODE" == "LIVE" ] && [ "$CURRENT_ACTIVE_INDEX" -ge 0 ]; then
        CHECK_LIMIT=$((CURRENT_ACTIVE_INDEX + 1))
    fi

    for ((i=0; i<CHECK_LIMIT; i++)); do
        STREAMER=$(echo "${STREAMERS_RANK[$i]}" | xargs)
        [ -z "$STREAMER" ] && continue

        IS_ON=$(streamlink --http-header "User-Agent=$UA" --stream-timeout 8 "https://kick.com/$STREAMER" "$QUALITY" --stream-url 2>/dev/null | grep -m1 "^http")

        if [ -n "$IS_ON" ]; then
            FOUND_LIVE=true
            SELECTED_STREAMER="$STREAMER"
            SELECTED_INDEX=$i
            break
        fi
    done

    if [ "$FOUND_LIVE" = true ]; then
        if [ "$CURRENT_ACTIVE_STREAMER" != "$SELECTED_STREAMER" ] || ! kill -0 "$INPUT_PID" 2>/dev/null; then
            start_live_feed "$SELECTED_STREAMER"
            CURRENT_ACTIVE_STREAMER="$SELECTED_STREAMER"
            CURRENT_ACTIVE_INDEX=$SELECTED_INDEX
            CURRENT_MODE="LIVE"
        fi
    else
        if [ "$CURRENT_MODE" != "STANDBY" ] || ! kill -0 "$INPUT_PID" 2>/dev/null; then
            start_standby_feed
            CURRENT_ACTIVE_STREAMER=""
            CURRENT_ACTIVE_INDEX=-1
            CURRENT_MODE="STANDBY"
        fi
    fi

    sleep 15
done

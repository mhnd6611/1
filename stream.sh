#!/bin/bash

# ==============================================================================
# نظام البث الذكي 24/7 - نظام الأولوية لـ 10 ستريمرز مع فلاتر تحسين الجودة
# ==============================================================================

# قائمة الستريمرز مرتبة حسب الأولوية (من الأعلى رقم 1 إلى الأقل رقم 10)
STREAMERS_RANK=(
    "drb7h"    # أولوية 1 (الأهم)
    "S5B"      # أولوية 2
    "ABO8ALYY"     # أولوية 3
    "ID7O"   # أولوية 4
    "F1AISAL"   # أولوية 5
    "ABO_KHRBAA"   # أولوية 6
    "iMonkey_D"   # أولوية 7
    "FHLWY"   # أولوية 8
    "aymnalsatam"   # أولوية 9
    "IB6H"  # أولوية 10
)

RESTREAM_KEY="${RESTREAM_KEY:-re_12394050_eventb0c61bd69bcd4207a19d91e5f4a74f69}"
YOUTUBE_KEY="${YOUTUBE_KEY:-}"
QUALITY="${STREAM_QUALITY:-best}"
DEST="${STREAM_DEST:-restream}"

# تنظيف المفاتيح
if [[ "$YOUTUBE_KEY" == "X" || "$YOUTUBE_KEY" == "x" ]]; then YOUTUBE_KEY=""; fi
if [[ "$RESTREAM_KEY" == "X" || "$RESTREAM_KEY" == "x" ]]; then RESTREAM_KEY=""; fi

# تحديد الخط المناسب للعربية
if fc-list : family | grep -qi "Noto Naskh Arabic"; then
    FONT_NAME="Noto Naskh Arabic"
elif fc-list : family | grep -qi "Scheherazade"; then
    FONT_NAME="Scheherazade New"
else
    FONT_NAME="Sans"
fi

STREAM_PID=""
CURRENT_MODE="NONE"
CURRENT_ACTIVE_STREAMER=""

cleanup() {
    echo "🧹 إيقاف عمليات البث..."
    trap - EXIT INT TERM
    [ -n "$STREAM_PID" ] && kill -9 "$STREAM_PID" 2>/dev/null
    exit 0
}
trap cleanup EXIT INT TERM

stop_stream() {
    if [ -n "$STREAM_PID" ]; then
        kill -9 "$STREAM_PID" 2>/dev/null
        STREAM_PID=""
    fi
}

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
    local TARGET_NAME="$1"
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
Dialogue: 0,0:00:00.00,9:59:59.99,Subtitle,,0,0,0,,{\fad(600,600)}جاري انتظار قائمة الستريمرز المحددة
EOF
}

start_standby_stream() {
    generate_initial_ass
    stop_stream

    echo "⏳ بدء بث شاشة الانتظار (جميع الستريمرز أوفلاين)..."
    OUTPUTS=$(get_outputs)

    ffmpeg -hide_banner -loglevel error -nostdin \
      -re -f lavfi -i color=c=0x140024:s=1920x1080:r=60 \
      -f lavfi -i anullsrc=r=44100:cl=stereo \
      -map 0:v:0 -map 1:a:0 \
      -vf "ass=/tmp/initial_standby.ass" \
      -c:v libx264 -preset superfast -tune zerolatency -pix_fmt yuv420p -r 60 -g 120 -b:v 3500k \
      -c:a aac -b:a 128k -ar 44100 \
      -flvflags no_duration_filesize \
      $OUTPUTS >/tmp/ffmpeg.log 2>&1 &
    STREAM_PID=$!
}

start_live_stream() {
    local M3U8="$1"
    local STREAMER_NAME="$2"
    stop_stream
    echo "🔴 بدء البث المباشر للستريمر: [$STREAMER_NAME] (الأعلى أولوية حالياً)..."
    OUTPUTS=$(get_outputs)

    # تطبيق فلاتر الألوان والوضوح و 60 فريم
    ffmpeg -hide_banner -loglevel error -nostdin \
      -headers "User-Agent: Mozilla/5.0 (Windows NT 10.0; Win64; x64)" \
      -reconnect 1 -reconnect_at_eof 1 -reconnect_streamed 1 -reconnect_delay_max 5 \
      -fflags +genpts+discardcorrupt -i "$M3U8" \
      -vf "fps=60,unsharp=3:3:0.8:3:3:0.0,eq=contrast=1.12:saturation=1.2" \
      -c:v libx264 -preset superfast -tune zerolatency -pix_fmt yuv420p -r 60 -g 120 \
      -b:v 6000k -maxrate 6000k -bufsize 12000k \
      -c:a aac -b:a 160k -ar 44100 \
      -flvflags no_duration_filesize \
      $OUTPUTS >/tmp/ffmpeg.log 2>&1 &
    STREAM_PID=$!
}

UA="Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"

sleep 2

while true; do
    FOUND_LIVE=false
    SELECTED_STREAMER=""
    SELECTED_M3U8=""

    # الدوران على الستريمرز حسب ترتيب الأولوية من 1 إلى 10
    for STREAMER in "${STREAMERS_RANK[@]}"; do
        [ -z "$STREAMER" ] && continue

        # جلب رابط البث
        M3U8=$(streamlink --http-header "User-Agent=$UA" --hls-live-edge 3 --stream-timeout 10 "https://kick.com/$STREAMER" "$QUALITY" --stream-url 2>/dev/null | grep -m1 "^http")

        if [ -n "$M3U8" ]; then
            FOUND_LIVE=true
            SELECTED_STREAMER="$STREAMER"
            SELECTED_M3U8="$M3U8"
            break # الخروج فوراً للتمسك بالأعلى أولوية
        fi
    done

    if [ "$FOUND_LIVE" = true ]; then
        # إذا تغير الستريمر (مثلاً دخل ستريمر بأولوية أعلى) أو توقف البث
        if [ "$CURRENT_ACTIVE_STREAMER" != "$SELECTED_STREAMER" ] || ! kill -0 "$STREAM_PID" 2>/dev/null; then
            echo "🎯 التحويل للستريمر الأعلى أولوية المتاح: $SELECTED_STREAMER"
            start_live_stream "$SELECTED_M3U8" "$SELECTED_STREAMER"
            CURRENT_ACTIVE_STREAMER="$SELECTED_STREAMER"
            CURRENT_MODE="LIVE"
        fi
    else
        # في حال كان جميع الستريمرز الـ 10 أوفلاين
        if [ "$CURRENT_MODE" != "STANDBY" ] || ! kill -0 "$STREAM_PID" 2>/dev/null; then
            echo "⏳ لا يوجد أي ستريمر متصل من القائمة.. التحويل لشاشة الانتظار..."
            start_standby_stream
            CURRENT_ACTIVE_STREAMER=""
            CURRENT_MODE="STANDBY"
        fi
    fi

    # فحص القائمة كل 15 ثانية للتحقق من دخول ستريمر ذو أولوية أعلى
    sleep 15
done

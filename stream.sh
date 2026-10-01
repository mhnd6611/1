#!/bin/bash
set +m

# RLM لتصحيح اتجاه النص العربي
RLM=$'\u200f'

# ═════════ إعدادات ريسبكت ═════════
TITLE="${RLM}لم يبدأ ستريمرز ريسبكت البث بعد"
SUBTITLE="${RLM}جاري انتضار ستريمرز ريسبكت بدأ البث."
LABEL="${RLM}قائمة الستريمرز:"
COLOR_T="&H00FFFFFF"
COLOR_S="&H00FFFFFF"
COLOR_L="&H00FFFFFF"
COLOR_OUTLINE="&H00000000"
BG="0x140024"
FS_T=82
FS_S=58
FS_L=30
POS_T=300
POS_S=210
POS_L=430
OUTLINE=4
SHADOW=2
LOGO_URL="https://i.top4top.io/p_39264fv5g0.png"
LOGO_W=280
LOGO_BOTTOM=60
LOGO_SHOW=5
LOGO_CYCLE=7
# ══════════════════════════════════

RESTREAM_KEY="${RESTREAM_KEY:-}"
[ -z "$RESTREAM_KEY" ] && { echo "ERR: no key"; exit 1; }
[ -z "$STREAMERS_LIST" ] && { echo "ERR: no streamers"; exit 1; }

UA="Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"
RESTREAM_URL="rtmp://live.restream.io/live/$RESTREAM_KEY"
FIFO="/tmp/relay.ts"

IFS=',' read -r -a STREAMERS <<< "$STREAMERS_LIST"

if fc-list : family | grep -qi "Noto Naskh Arabic"; then
    FONT="Noto Naskh Arabic"
elif fc-list : family | grep -qi "Noto Kufi Arabic"; then
    FONT="Noto Kufi Arabic"
else
    FONT="DejaVu Sans"
fi
echo "Font: $FONT"

LIST_STR=""
for i in "${!STREAMERS[@]}"; do
    S=$(echo "${STREAMERS[$i]}" | xargs)
    [ -z "$S" ] && continue
    if [ -z "$LIST_STR" ]; then
        LIST_STR="$S"
    else
        LIST_STR="$LIST_STR · $S"
    fi
done
echo "List: $LIST_STR"

LOGO=""
if curl -sL --max-time 25 -A "Mozilla/5.0" "$LOGO_URL" -o /tmp/logo.png 2>/dev/null; then
    if [ -s /tmp/logo.png ] && file /tmp/logo.png 2>/dev/null | grep -qiE "PNG|JPEG|image"; then
        LOGO="/tmp/logo.png"
        echo "✅ logo OK"
    else
        echo "⚠️ logo not image"
    fi
else
    echo "⚠️ logo download failed"
fi

cat > /tmp/s.ass <<EOF
[Script Info]
ScriptType: v4.00+
PlayResX: 1920
PlayResY: 1080
ScaledBorderAndShadow: yes
WrapStyle: 2

[V4+ Styles]
Format: Name, Fontname, Fontsize, PrimaryColour, SecondaryColour, OutlineColour, BackColour, Bold, Italic, Underline, StrikeOut, ScaleX, ScaleY, Spacing, Angle, BorderStyle, Outline, Shadow, Alignment, MarginL, MarginR, MarginV, Encoding
Style: T,$FONT,$FS_T,$COLOR_T,&H00000000,$COLOR_OUTLINE,&H80000000,-1,0,0,0,100,100,1,0,1,$OUTLINE,$SHADOW,2,10,10,$POS_T,1
Style: S,$FONT,$FS_S,$COLOR_S,&H00000000,$COLOR_OUTLINE,&H80000000,-1,0,0,0,100,100,1,0,1,$OUTLINE,$SHADOW,2,10,10,$POS_S,1
Style: L,$FONT,$FS_L,$COLOR_L,&H00000000,$COLOR_OUTLINE,&H80000000,-1,0,0,0,100,100,1,0,1,3,2,2,10,10,$POS_L,1

[Events]
Format: Layer, Start, End, Style, Name, MarginL, MarginR, MarginV, Effect, Text
Dialogue: 0,0:00:00.00,9:59:59.99,L,,0,0,0,,{\\fad(600,600)}$LABEL $LIST_STR
Dialogue: 0,0:00:00.00,9:59:59.99,T,,0,0,0,,{\\fad(600,600)}$TITLE
Dialogue: 0,0:00:00.00,9:59:59.99,S,,0,0,0,,{\\fad(600,600)}$SUBTITLE
EOF

rm -f "$FIFO"
mkfifo "$FIFO"
exec 3<>"$FIFO"

run() {
    if [ -n "$LOGO" ]; then
        ffmpeg -y -hide_banner -loglevel warning -nostdin \
            -re -f lavfi -i "color=c=$BG:s=1920x1080:r=30" \
            -loop 1 -framerate 30 -i "$LOGO" \
            -f lavfi -i "anullsrc=r=44100:cl=stereo" \
            -filter_complex "[0:v]ass=/tmp/s.ass[b];[1:v]scale=$LOGO_W:-2[l];[b][l]overlay=x=(W-w)/2:y=H-h-$LOGO_BOTTOM:enable='lt(mod(t\,$LOGO_CYCLE)\,$LOGO_SHOW)'[v]" \
            -map "[v]" -map 2:a:0 \
            -c:v libx264 -preset ultrafast -tune zerolatency -pix_fmt yuv420p -g 60 \
            -c:a aac -b:a 128k -ar 44100 -ac 2 \
            -max_muxing_queue_size 4096 \
            -f mpegts "$FIFO" >/tmp/prod.log 2>&1 &
    else
        ffmpeg -y -hide_banner -loglevel warning -nostdin \
            -re -f lavfi -i "color=c=$BG:s=1920x1080:r=30" \
            -f lavfi -i "anullsrc=r=44100:cl=stereo" \
            -vf "ass=/tmp/s.ass" \
            -map 0:v:0 -map 1:a:0 \
            -c:v libx264 -preset ultrafast -tune zerolatency -pix_fmt yuv420p -g 60 \
            -c:a aac -b:a 128k -ar 44100 -ac 2 \
            -max_muxing_queue_size 4096 \
            -f mpegts "$FIFO" >/tmp/prod.log 2>&1 &
    fi
    PROD=$!
    sleep 5
    if ! kill -0 $PROD 2>/dev/null; then
        echo "❌ standby failed:"; cat /tmp/prod.log; return 1
    fi

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
                if [ -n "$LOGO" ]; then
                    ffmpeg -y -hide_banner -loglevel warning -nostdin \
                        -re -f lavfi -i "color=c=$BG:s=1920x1080:r=30" \
                        -loop 1 -framerate 30 -i "$LOGO" \
                        -f lavfi -i "anullsrc=r=44100:cl=stereo" \
                        -filter_complex "[0:v]ass=/tmp/s.ass[b];[1:v]scale=$LOGO_W:-2[l];[b][l]overlay=x=(W-w)/2:y=H-h-$LOGO_BOTTOM:enable='lt(mod(t\,$LOGO_CYCLE)\,$LOGO_SHOW)'[v]" \
                        -map "[v]" -map 2:a:0 \
                        -c:v libx264 -preset ultrafast -tune zerolatency -pix_fmt yuv420p -g 60 \
                        -c:a aac -b:a 128k -ar 44100 -ac 2 \
                        -max_muxing_queue_size 4096 \
                        -f mpegts "$FIFO" >/tmp/prod.log 2>&1 &
                else
                    ffmpeg -y -hide_banner -loglevel warning -nostdin \
                        -re -f lavfi -i "color=c=$BG:s=1920x1080:r=30" \
                        -f lavfi -i "anullsrc=r=44100:cl=stereo" \
                        -vf "ass=/tmp/s.ass" \
                        -map 0:v:0 -map 1:a:0 \
                        -c:v libx264 -preset ultrafast -tune zerolatency -pix_fmt yuv420p -g 60 \
                        -c:a aac -b:a 128k -ar 44100 -ac 2 \
                        -max_muxing_queue_size 4096 \
                        -f mpegts "$FIFO" >/tmp/prod.log 2>&1 &
                fi
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

                if [ -n "$LOGO" ]; then
                    ffmpeg -y -hide_banner -loglevel warning -nostdin \
                        -re -f lavfi -i "color=c=$BG:s=1920x1080:r=30" \
                        -loop 1 -framerate 30 -i "$LOGO" \
                        -f lavfi -i "anullsrc=r=44100:cl=stereo" \
                        -filter_complex "[0:v]ass=/tmp/s.ass[b];[1:v]scale=$LOGO_W:-2[l];[b][l]overlay=x=(W-w)/2:y=H-h-$LOGO_BOTTOM:enable='lt(mod(t\,$LOGO_CYCLE)\,$LOGO_SHOW)'[v]" \
                        -map "[v]" -map 2:a:0 \
                        -c:v libx264 -preset ultrafast -tune zerolatency -pix_fmt yuv420p -g 60 \
                        -c:a aac -b:a 128k -ar 44100 -ac 2 \
                        -max_muxing_queue_size 4096 \
                        -f mpegts "$FIFO" >/tmp/prod.log 2>&1 &
                else
                    ffmpeg -y -hide_banner -loglevel warning -nostdin \
                        -re -f lavfi -i "color=c=$BG:s=1920x1080:r=30" \
                        -f lavfi -i "anullsrc=r=44100:cl=stereo" \
                        -vf "ass=/tmp/s.ass" \
                        -map 0:v:0 -map 1:a:0 \
                        -c:v libx264 -preset ultrafast -tune zerolatency -pix_fmt yuv420p -g 60 \
                        -c:a aac -b:a 128k -ar 44100 -ac 2 \
                        -max_muxing_queue_size 4096 \
                        -f mpegts "$FIFO" >/tmp/prod.log 2>&1 &
                fi
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

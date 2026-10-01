#!/bin/bash
set +m

# ═════════ إعدادات ريسبكت ═════════
TITLE="لم يبدأ ستريمرز ريسبكت البث بعد"
SUBTITLE="جاري انتضار ستريمرز ريسبكت بدأ البث."
LABEL="قائمة الستريمرز:"
COLOR_T="white"
COLOR_S="white"
COLOR_L="#CCCCCC"
COLOR_OUTLINE="black"
BG="0x140024"
FS_T=82
FS_S=58
FS_L=22
Y_LIST=60
Y_TITLE=200
Y_SUB=380
OUTLINE=4
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

# مسار الخط
FONT_FILE=$(fc-match -f '%{file}' "Noto Naskh Arabic" 2>/dev/null)
[ -z "$FONT_FILE" ] && FONT_FILE=$(fc-match -f '%{file}' "Sans" 2>/dev/null)
echo "Font: $FONT_FILE"

# قائمة الستريمرز
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

# تحميل الشعار
LOGO=""
if curl -sL --max-time 25 -A "Mozilla/5.0" "$LOGO_URL" -o /tmp/logo_src.png 2>/dev/null; then
    if [ -s /tmp/logo_src.png ] && file /tmp/logo_src.png 2>/dev/null | grep -qiE "PNG|JPEG|image"; then
        convert /tmp/logo_src.png -resize ${LOGO_W}x /tmp/logo.png 2>/dev/null
        if [ -s /tmp/logo.png ]; then
            LOGO="/tmp/logo.png"
            echo "✅ logo OK"
        fi
    else
        echo "⚠️ logo not image"
    fi
else
    echo "⚠️ logo download failed"
fi

# ═════════ رسم النصوص كصورة PNG بـ ImageMagick ═════════
echo "🖌️ rendering text PNG..."
convert -size 1920x1080 xc:transparent \
    -font "$FONT_FILE" \
    -gravity north \
    -fill "$COLOR_L" -stroke "$COLOR_OUTLINE" -strokewidth 2 \
    -pointsize $FS_L -annotate +0+$Y_LIST "$LABEL $LIST_STR" \
    -fill "$COLOR_T" -stroke "$COLOR_OUTLINE" -strokewidth $OUTLINE \
    -pointsize $FS_T -annotate +0+$Y_TITLE "$TITLE" \
    -fill "$COLOR_S" -stroke "$COLOR_OUTLINE" -strokewidth $OUTLINE \
    -pointsize $FS_S -annotate +0+$Y_SUB "$SUBTITLE" \
    /tmp/texts.png

if [ ! -s /tmp/texts.png ]; then
    echo "❌ text PNG failed"
    exit 1
fi
echo "✅ texts.png OK: $(file -b /tmp/texts.png)"

# FIFO
rm -f "$FIFO"
mkfifo "$FIFO"
exec 3<>"$FIFO"

# ═════════ تشغيل ═════════
run() {
    if [ -n "$LOGO" ]; then
        ffmpeg -y -hide_banner -loglevel warning -nostdin \
            -re -f lavfi -i "color=c=$BG:s=1920x1080:r=30" \
            -loop 1 -framerate 30 -i /tmp/texts.png \
            -loop 1 -framerate 30 -i "$LOGO" \
            -f lavfi -i "anullsrc=r=44100:cl=stereo" \
            -filter_complex "[0:v][1:v]overlay=0:0[b];[b][2:v]overlay=x=(W-w)/2:y=H-h-$LOGO_BOTTOM:enable='lt(mod(t\,$LOGO_CYCLE)\,$LOGO_SHOW)'[v]" \
            -map "[v]" -map 3:a:0 \
            -c:v libx264 -preset ultrafast -tune zerolatency -pix_fmt yuv420p -g 60 \
            -c:a aac -b:a 128k -ar 44100 -ac 2 \
            -max_muxing_queue_size 4096 \
            -f mpegts "$FIFO" >/tmp/prod.log 2>&1 &
    else
        ffmpeg -y -hide_banner -loglevel warning -nostdin \
            -re -f lavfi -i "color=c=$BG:s=1920x1080:r=30" \
            -loop 1 -framerate 30 -i /tmp/texts.png \
            -f lavfi -i "anullsrc=r=44100:cl=stereo" \
            -filter_complex "[0:v][1:v]overlay=0:0[v]" \
            -map "[v]" -map 2:a:0 \
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
                        -loop 1 -framerate 30 -i /tmp/texts.png \
                        -loop 1 -framerate 30 -i "$LOGO" \
                        -f lavfi -i "anullsrc=r=44100:cl=stereo" \
                        -filter_complex "[0:v][1:v]overlay=0:0[b];[b][2:v]overlay=x=(W-w)/2:y=H-h-$LOGO_BOTTOM:enable='lt(mod(t\,$LOGO_CYCLE)\,$LOGO_SHOW)'[v]" \
                        -map "[v]" -map 3:a:0 \
                        -c:v libx264 -preset ultrafast -tune zerolatency -pix_fmt yuv420p -g 60 \
                        -c:a aac -b:a 128k -ar 44100 -ac 2 \
                        -max_muxing_queue_size 4096 \
                        -f mpegts "$FIFO" >/tmp/prod.log 2>&1 &
                else
                    ffmpeg -y -hide_banner -loglevel warning -nostdin \
                        -re -f lavfi -i "color=c=$BG:s=1920x1080:r=30" \
                        -loop 1 -framerate 30 -i /tmp/texts.png \
                        -f lavfi -i "anullsrc=r=44100:cl=stereo" \
                        -filter_complex "[0:v][1:v]overlay=0:0[v]" \
                        -map "[v]" -map 2:a:0 \
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
                        -loop 1 -framerate 30 -i /tmp/texts.png \
                        -loop 1 -framerate 30 -i "$LOGO" \
                        -f lavfi -i "anullsrc=r=44100:cl=stereo" \
                        -filter_complex "[0:v][1:v]overlay=0:0[b];[b][2:v]overlay=x=(W-w)/2:y=H-h-$LOGO_BOTTOM:enable='lt(mod(t\,$LOGO_CYCLE)\,$LOGO_SHOW)'[v]" \
                        -map "[v]" -map 3:a:0 \
                        -c:v libx264 -preset ultrafast -tune zerolatency -pix_fmt yuv420p -g 60 \
                        -c:a aac -b:a 128k -ar 44100 -ac 2 \
                        -max_muxing_queue_size 4096 \
                        -f mpegts "$FIFO" >/tmp/prod.log 2>&1 &
                else
                    ffmpeg -y -hide_banner -loglevel warning -nostdin \
                        -re -f lavfi -i "color=c=$BG:s=1920x1080:r=30" \
                        -loop 1 -framerate 30 -i /tmp/texts.png \
                        -f lavfi -i "anullsrc=r=44100:cl=stereo" \
                        -filter_complex "[0:v][1:v]overlay=0:0[v]" \
                        -map "[v]" -map 2:a:0 \
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

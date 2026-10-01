#!/bin/bash
set +m

# ==============================================================================
# CONFIG — Respect
# ==============================================================================
STANDBY_TITLE="لم يبدأ ستريمرز ريسبكت البث بعد"
STANDBY_SUBTITLE="جاري انتضار ستريمرز ريسبكت بدأ البث."
COLOR_TITLE="&H00FEB4D8"
COLOR_SUBTITLE="&H00F755A8"
COLOR_OUTLINE="&H00000000"
COLOR_SHADOW="&H00000000"
OUTLINE_SIZE=2
SHADOW_SIZE=1
BG_COLOR="0x140024"
FONT_SIZE_TITLE=78
FONT_SIZE_SUBTITLE=54
POS_TITLE=420
POS_SUBTITLE=520
LOGO_URL="https://i.top4top.io/p_39264fv5g0.png"
LOGO_WIDTH=380
LOGO_BOTTOM_MARGIN=80
LOGO_SHOW_DURATION=5
LOGO_CYCLE=7
# ==============================================================================

RESTREAM_KEY="${RESTREAM_KEY:-}"
QUALITY="${STREAM_QUALITY:-best}"
[[ "$RESTREAM_KEY" == "X" || "$RESTREAM_KEY" == "x" ]] && RESTREAM_KEY=""

[ -z "$STREAMERS_LIST" ] && { echo "ERR: empty streamers"; exit 1; }
[ -z "$RESTREAM_KEY" ] && { echo "ERR: empty restream key"; exit 1; }

echo "KEY: ${RESTREAM_KEY:0:10}..."
echo "FFMPEG: $(which ffmpeg) — $(ffmpeg -version 2>&1 | head -1)"
echo "SL: $(which streamlink) — $(streamlink --version 2>&1)"

# ---------- Logo ----------
LOGO_FILE=""
_TMP="/tmp/logo_r.png"
echo "DL logo..."
if curl -sL --max-time 25 -A "Mozilla/5.0" "$LOGO_URL" -o "$_TMP" 2>/dev/null; then
    if [ -s "$_TMP" ] && file "$_TMP" | grep -qiE "PNG|JPEG|JPG|image"; then
        LOGO_FILE="$_TMP"
        echo "LOGO OK: $(file -b "$_TMP")"
    else
        echo "LOGO BAD: $(head -c 80 "$_TMP")"
    fi
fi
[ -z "$LOGO_FILE" ] && echo "no logo, continuing without it"

IFS=',' read -r -a STREAMERS_RANK <<< "$STREAMERS_LIST"

if fc-list : family | grep -qi "Noto Naskh Arabic"; then
    FONT_NAME="Noto Naskh Arabic"
elif fc-list : family | grep -qi "Scheherazade"; then
    FONT_NAME="Scheherazade New"
else
    FONT_NAME="Sans"
fi
echo "FONT: $FONT_NAME"

RESTREAM_URL="rtmp://live.restream.io/live/$RESTREAM_KEY"
FIFO="/tmp/relay.ts"
UA="Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"

OUTPUT_PID=""
PRODUCER_PID=""
CURRENT_MODE="NONE"
CURRENT_ACTIVE_STREAMER=""
CURRENT_ACTIVE_INDEX=-1

cleanup() {
    trap - EXIT INT TERM
    [ -n "$PRODUCER_PID" ] && kill -9 "$PRODUCER_PID" 2>/dev/null
    [ -n "$OUTPUT_PID" ] && kill -9 "$OUTPUT_PID" 2>/dev/null
    exit 0
}
trap cleanup EXIT INT TERM

alive() { [ -n "$1" ] && kill -0 "$1" 2>/dev/null; }

# ---------- FIFO ----------
setup_fifo() {
    rm -f "$FIFO"
    mkfifo "$FIFO"
    exec 3<>"$FIFO"
}

# ---------- ASS ----------
generate_ass() {
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

[Events]
Format: Layer, Start, End, Style, Name, MarginL, MarginR, MarginV, Effect, Text
Dialogue: 0,0:00:00.00,9:59:59.99,Title,,0,0,0,,{\\fad(600,600)}$STANDBY_TITLE
Dialogue: 0,0:00:00.00,9:59:59.99,Subtitle,,0,0,0,,{\\fad(600,600)}$STANDBY_SUBTITLE
EOF
}

# ---------- Output ----------
start_output() {
    echo "OUT: connecting..."
    ffmpeg -y -hide_banner -loglevel warning -nostdin \
      -thread_queue_size 1024 \
      -fflags +genpts+igndts+discardcorrupt \
      -analyzeduration 5000000 -probesize 2000000 \
      -f mpegts -i "$FIFO" \
      -c copy \
      -max_muxing_queue_size 8192 \
      -flvflags no_duration_filesize \
      -f flv "$RESTREAM_URL" >/tmp/ffmpeg_out.log 2>&1 &
    OUTPUT_PID=$!
    sleep 4
    if alive "$OUTPUT_PID"; then
        echo "OUT: OK (PID $OUTPUT_PID)"
        return 0
    fi
    echo "OUT: FAIL"
    tail -n 10 /tmp/ffmpeg_out.log
    return 1
}

# ---------- Cancel old runs (only older IDs) ----------
cancel_old_runs() {
    [ -z "$GH_TOKEN" ] || [ -z "$GITHUB_RUN_ID" ] && return 0
    OLD=$(timeout 15 gh run list --workflow="main.yml" --status=in_progress \
      --json databaseId -q ".[].databaseId" 2>/dev/null | \
      awk -v me="$GITHUB_RUN_ID" '$1 < me' || true)
    for R in $OLD; do
        echo "CANCEL: $R"
        timeout 10 gh run cancel "$R" 2>/dev/null || true
    done
}

stop_producer() {
    if [ -n "$PRODUCER_PID" ]; then
        kill -9 "$PRODUCER_PID" 2>/dev/null
        wait "$PRODUCER_PID" 2>/dev/null
        PRODUCER_PID=""
    fi
    sleep 1
}

# ---------- Standby producer (with fallback) ----------
start_producer_standby() {
    stop_producer
    generate_ass

    if [ -n "$LOGO_FILE" ]; then
        echo "SB: with logo..."
        ffmpeg -y -hide_banner -loglevel warning -nostdin \
          -re -f lavfi -i color=c=${BG_COLOR}:s=1920x1080:r=30 \
          -loop 1 -framerate 30 -i "$LOGO_FILE" \
          -f lavfi -i anullsrc=r=44100:cl=stereo \
          -filter_complex "[0:v]ass=/tmp/standby.ass[base];[1:v]scale=${LOGO_WIDTH}:-2[logo];[base][logo]overlay=x=(W-w)/2:y=H-h-${LOGO_BOTTOM_MARGIN}:enable=lt(mod(t\,${LOGO_CYCLE})\,${LOGO_SHOW_DURATION})[vout]" \
          -map "[vout]" -map 2:a:0 \
          -c:v libx264 -preset ultrafast -tune zerolatency -pix_fmt yuv420p -r 30 -g 60 \
          -c:a aac -b:a 128k -ar 44100 -ac 2 \
          -max_muxing_queue_size 4096 \
          -f mpegts "$FIFO" >/tmp/ffmpeg_in.log 2>&1 &
        PRODUCER_PID=$!
        sleep 5
        if alive "$PRODUCER_PID"; then
            echo "SB: OK (with logo)"
            return 0
        fi
        echo "SB: logo failed, retrying without it"
        tail -n 10 /tmp/ffmpeg_in.log
        LOGO_FILE=""
    fi

    echo "SB: no logo..."
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
    sleep 5
    if alive "$PRODUCER_PID"; then
        echo "SB: OK (no logo)"
        return 0
    fi
    echo "SB: FAIL"
    tail -n 15 /tmp/ffmpeg_in.log
    return 1
}

# ---------- Live producer ----------
start_producer_live() {
    local M3U8="$1"
    local NAME="$2"
    stop_producer
    echo "LIVE: $NAME"
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
    if ! alive "$PRODUCER_PID"; then
        echo "LIVE FAIL: $NAME"
        tail -n 10 /tmp/ffmpeg_in.log
        return 1
    fi
    return 0
}

# ============================================================
# MAIN — infinite supervisor
# ============================================================
while true; do

    setup_fifo

    # Producer FIRST
    SB_OK=false
    for i in 1 2 3; do
        if start_producer_standby; then SB_OK=true; break; fi
        echo "retry SB $i/3"; sleep 3
    done
    if [ "$SB_OK" != "true" ]; then
        echo "FATAL: standby failed"; sleep 15; continue
    fi

    # Output
    OUT_OK=false
    for i in 1 2 3 4 5; do
        if start_output; then OUT_OK=true; break; fi
        echo "retry OUT $i/5"; sleep 5
    done
    if [ "$OUT_OK" != "true" ]; then
        echo "FATAL: output failed"
        stop_producer
        sleep 15
        continue
    fi

    CURRENT_MODE="STANDBY"
    CURRENT_ACTIVE_STREAMER=""
    CURRENT_ACTIVE_INDEX=-1

    ( cancel_old_runs ) >/tmp/cancel_old.log 2>&1 &

    DIAG_TICK=0
    INNER_LOOP=true

    while [ "$INNER_LOOP" = true ]; do

        if ! alive "$OUTPUT_PID"; then
            echo "OUT died — restarting"
            OUT_OK=false
            for i in 1 2 3; do
                if start_output; then OUT_OK=true; break; fi
                sleep 5
            done
            if [ "$OUT_OK" != "true" ]; then
                echo "OUT permanently dead — breaking to top"
                stop_producer
                INNER_LOOP=false
                break
            fi
        fi

        FOUND_LIVE=false
        SEL_NAME=""; SEL_M3U8=""; SEL_IDX=-1

        CHECK_LIMIT=${#STREAMERS_RANK[@]}
        if [ "$CURRENT_MODE" == "LIVE" ] && [ "$CURRENT_ACTIVE_INDEX" -ge 0 ]; then
            CHECK_LIMIT=$((CURRENT_ACTIVE_INDEX + 1))
        fi

        for ((i=0; i<CHECK_LIMIT; i++)); do
            S=$(echo "${STREAMERS_RANK[$i]}" | xargs)
            [ -z "$S" ] && continue
            M=$(streamlink --http-header "User-Agent=$UA" --hls-live-edge 3 \
                 --stream-timeout 15 "https://kick.com/$S" "$QUALITY" \
                 --stream-url 2>/dev/null | grep -m1 "^http" || true)
            if [ -n "$M" ]; then
                FOUND_LIVE=true; SEL_NAME="$S"; SEL_M3U8="$M"; SEL_IDX=$i
                break
            fi
        done

        if [ "$FOUND_LIVE" = true ]; then
            NEED=false
            [ "$CURRENT_MODE" != "LIVE" ] && NEED=true
            [ "$CURRENT_ACTIVE_STREAMER" != "$SEL_NAME" ] && NEED=true
            if [ -n "$PRODUCER_PID" ] && ! alive "$PRODUCER_PID"; then NEED=true; fi

            if [ "$NEED" = true ]; then
                echo "SWITCH -> $SEL_NAME"
                if start_producer_live "$SEL_M3U8" "$SEL_NAME"; then
                    CURRENT_ACTIVE_STREAMER="$SEL_NAME"
                    CURRENT_ACTIVE_INDEX=$SEL_IDX
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
            if [ "$CURRENT_MODE" != "STANDBY" ] || [ -z "$PRODUCER_PID" ] || ! alive "$PRODUCER_PID"; then
                echo "no live — standby"
                if ! start_producer_standby; then
                    echo "SB failed — break to top"
                    [ -n "$OUTPUT_PID" ] && kill -9 "$OUTPUT_PID" 2>/dev/null
                    INNER_LOOP=false
                    break
                fi
                CURRENT_MODE="STANDBY"
                CURRENT_ACTIVE_STREAMER=""
                CURRENT_ACTIVE_INDEX=-1
            fi
        fi

        DIAG_TICK=$((DIAG_TICK + 1))
        if [ $((DIAG_TICK % 4)) -eq 0 ]; then
            echo "── DIAG $(date -u +%H:%M:%S)Z ──"
            echo "OUT: $(alive $OUTPUT_PID && echo UP || echo DOWN) | PROD: $(alive $PRODUCER_PID && echo UP || echo DOWN) | MODE: $CURRENT_MODE"
            echo "OUT: $(tail -n 1 /tmp/ffmpeg_out.log 2>/dev/null | head -c 200)"
            echo "IN:  $(tail -n 1 /tmp/ffmpeg_in.log 2>/dev/null | head -c 200)"
        fi

        sleep 15
    done

    echo "inner loop exited — restarting from top"
    sleep 10
done

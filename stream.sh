#!/bin/bash
set +m

# ═══════════════════════════════════════════════════
#  Respect Broadcast — Smart Priority Architecture
# ═══════════════════════════════════════════════════

STREAMERS_LIST="${STREAMERS_LIST:-drb7h,S5B,ABO8ALYY,ID7O,F1AISAL,xmusabrt,TAF86,abo_khrbaa,Peerless,Seagull,iMonkey_D,FHLWY,Hook,okb8,wolf,NASSER,Aymnalsatam,BoQamar,NEFOXD,RAYN,xya7ya,W1pey,AL_Hashidi,moustache,ALRND,klash,OGxHusni,Sayko_911,ZAiKRx}"
LOGO_URL="https://i.top4top.io/p_39264fv5g0.png"
UA="Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"

RESTREAM_KEY="${RESTREAM_KEY:-}"
[ -z "$RESTREAM_KEY" ] && { echo "❌ مفتاح Restream فارغ"; exit 1; }

RESTREAM_URL="rtmp://live.restream.io/live/$RESTREAM_KEY"
FIFO="/tmp/relay.ts"
WORKDIR="/tmp/respect_ui"

IFS=',' read -r -a STREAMERS <<< "$STREAMERS_LIST"
mkdir -p "$WORKDIR"

# 1. توليد شاشة الانتظار (بدون مربعات بيضاء)
if [ ! -f "$WORKDIR/standby.ts" ]; then
    echo "🎨 تجهيز شاشة الانتظار..."
    cat > /tmp/make_ui.py <<'PYEOF'
from PIL import Image, ImageDraw, ImageFont
import os
W, H = 1920, 1080
WORKDIR = os.environ["WORKDIR"]
STREAMERS = [s.strip() for s in os.environ.get("STREAMERS_LIST", "").split(',') if s.strip()]
bg = Image.new("RGB", (W, H), (10, 2, 20))
d = ImageDraw.Draw(bg)
try:
    font = ImageFont.truetype(os.path.expanduser("~/.fonts/Orbitron-var.ttf"), 100)
    font_sub = ImageFont.truetype(os.path.expanduser("~/.fonts/Cairo-var.ttf"), 40)
    font_list = ImageFont.truetype(os.path.expanduser("~/.fonts/Orbitron-var.ttf"), 24)
    
    d.text((W//2, 200), "RESPECT", font=font, fill=(212, 179, 255), anchor="mm")
    d.text((W//2, 300), "جاري انتظار انضمام الستريمرز...", font=font_sub, fill=(255, 255, 255), anchor="mm")
    
    COLS = 5
    for i, item in enumerate(STREAMERS):
        row, col = i // COLS, i % COLS
        x, y = 250 + col * 300, 450 + row * 60
        d.text((x, y), item.upper(), font=font_list, fill=(255, 255, 255), anchor="lm")
except Exception as e: print(e)
bg.save(f"{WORKDIR}/bg.png")
PYEOF
    WORKDIR="$WORKDIR" STREAMERS_LIST="$STREAMERS_LIST" python3 /tmp/make_ui.py
    ffmpeg -y -hide_banner -loglevel warning -loop 1 -framerate 30 -i "$WORKDIR/bg.png" -f lavfi -i "anullsrc=r=44100:cl=stereo" -t 4 -c:v libx264 -preset ultrafast -pix_fmt yuv420p -g 30 -c:a aac -ar 44100 -ac 2 -shortest -f mpegts "$WORKDIR/standby.ts"
fi

# 2. إعداد الأنبوب
rm -f "$FIFO"
mkfifo "$FIFO"
exec 3<>"$FIFO"

cleanup() {
    kill -TERM "$OUT" 2>/dev/null
    kill -TERM -- -"$PROD" 2>/dev/null
    pkill -f streamlink 2>/dev/null
    exit 0
}
trap cleanup SIGTERM SIGINT

# 3. المخرج (OUT)
start_output() {
    ffmpeg -y -hide_banner -loglevel warning -nostdin -thread_queue_size 1024 \
        -fflags +genpts+igndts+discardcorrupt -err_detect ignore_err \
        -f mpegts -i "$FIFO" -map 0:v:0 -map 0:a:0? -c:v copy -c:a copy \
        -max_muxing_queue_size 4096 -flvflags no_duration_filesize -rtmp_live live \
        -f flv "$RESTREAM_URL" >/tmp/out.log 2>&1 &
    OUT=$!
    sleep 3
}

# 4. شاشة الانتظار
start_producer_standby() {
    setsid ffmpeg -y -hide_banner -loglevel warning -nostdin -re -stream_loop -1 -i "$WORKDIR/standby.ts" \
        -c copy -f mpegts "$FIFO" >/tmp/prod.log 2>&1 &
    PROD=$!
}

# 5. البث المباشر
start_producer_live() {
    setsid bash -c "streamlink --http-header 'User-Agent=$UA' 'https://kick.com/$1' best --stdout 2>/dev/null | \
        ffmpeg -y -hide_banner -loglevel warning -nostdin -thread_queue_size 1024 -fflags +genpts+igndts+discardcorrupt -err_detect ignore_err \
        -i pipe:0 -c:v copy -c:a aac -b:a 128k -ar 44100 -ac 2 -f mpegts '$FIFO' >/tmp/prod.log 2>&1" &
    PROD=$!
}

kill_producer() {
    if [ -n "$PROD" ]; then 
        kill -TERM -- -"$PROD" 2>/dev/null
        sleep 0.1 
        kill -9 -- -"$PROD" 2>/dev/null
    fi
    PROD=""
}

# ═══════════════════════════════════════════════════
#  التشغيل الرئيسي
# ═══════════════════════════════════════════════════
echo "🚀 بدء التشغيل..."
start_producer_standby
sleep 2
start_output

MODE="STANDBY"
ACTIVE=""
ACTIVE_IDX="-1"

while true; do
    # التأكد من المخرج
    if ! kill -0 "$OUT" 2>/dev/null; then
        start_output
    fi

    # التأكد من المنتج
    if ! kill -0 "$PROD" 2>/dev/null; then
        start_producer_standby
        MODE="STANDBY"; ACTIVE=""; ACTIVE_IDX="-1"
    fi

    # 1. البحث عن ستريمر (إذا كنا في وضع الانتظار)
    if [ "$MODE" = "STANDBY" ]; then
        FOUND=""
        FOUND_IDX="-1"
        for ((i=0; i<${#STREAMERS[@]}; i++)); do
            S=$(echo "${STREAMERS[$i]}" | xargs); [ -z "$S" ] && continue
            URL=$(timeout 3 streamlink --http-header "User-Agent=$UA" "https://kick.com/$S" best --stream-url 2>/dev/null | grep -m1 "^http")
            if [ -n "$URL" ]; then FOUND="$S"; FOUND_IDX=$i; break; fi
        done

        if [ -n "$FOUND" ]; then
            echo "🎯 وجدنا: $FOUND (تبديل...)"
            kill_producer; sleep 0.1
            start_producer_live "$FOUND"
            sleep 2
            if kill -0 "$PROD" 2>/dev/null; then 
                MODE="LIVE"; ACTIVE="$FOUND"; ACTIVE_IDX="$FOUND_IDX"; echo "✅ مباشر: $FOUND"
            else 
                start_producer_standby; MODE="STANDBY"; ACTIVE=""; ACTIVE_IDX="-1"
            fi
        fi
    fi

    # 2. إذا كنا في وضع البث المباشر
    if [ "$MODE" = "LIVE" ] && [ -n "$ACTIVE" ]; then
        
        # أ) هل الستريمر الحالي لا يزال يبث؟
        URL=$(timeout 3 streamlink --http-header "User-Agent=$UA" "https://kick.com/$ACTIVE" best --stream-url 2>/dev/null | grep -m1 "^http")
        if [ -z "$URL" ]; then
            echo "⏳ توقف $ACTIVE — تحويل للانتظار..."
            kill_producer; sleep 0.1
            start_producer_standby
            MODE="STANDBY"; ACTIVE=""; ACTIVE_IDX="-1"
        
        # ب) إذا كان لا يزال يبث، هل يوجد أحد أعلى منه أولوية بدأ يبث؟
        else
            if [ "$ACTIVE_IDX" -gt 0 ]; then
                for ((i=0; i<ACTIVE_IDX; i++)); do
                    S=$(echo "${STREAMERS[$i]}" | xargs)
                    CHECK_URL=$(timeout 2 streamlink --http-header "User-Agent=$UA" "https://kick.com/$S" best --stream-url 2>/dev/null | grep -m1 "^http")
                    if [ -n "$CHECK_URL" ]; then
                        echo "🚀 ستريمر أعلى أولوية بدأ البث: $S (تحويل فوري...)"
                        kill_producer; sleep 0.1
                        start_producer_live "$S"
                        sleep 2
                        if kill -0 "$PROD" 2>/dev/null; then 
                            MODE="LIVE"; ACTIVE="$S"; ACTIVE_IDX=$i
                        else 
                            start_producer_standby; MODE="STANDBY"; ACTIVE=""; ACTIVE_IDX="-1"
                        fi
                        break
                    fi
                done
            fi
        fi
    fi

    sleep 2
done

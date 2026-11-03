#!/bin/bash
set +m

# ═══════════════════════════════════════════════════
#  Respect Broadcast — Smart Priority + Infinite Chain
# ═══════════════════════════════════════════════════

STREAMERS_LIST="${STREAMERS_LIST:-drb7h,S5B,ABO8ALYY,ID7O,F1AISAL,xmusabrt,TAF86,abo_khrbaa,Peerless,Seagull,iMonkey_D,FHLWY,Hook,okb8,wolf,NASSER,Aymnalsatam,BoQamar,NEFOXD,RAYN,xya7ya,W1pey,AL_Hashidi,moustache,ALRND,klash,OGxHusni,Sayko_911,ZAiKRx}"
LOGO_URL="https://i.top4top.io/p_39264fv5g0.png"
UA="Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"

RESTREAM_KEY="${RESTREAM_KEY:-}"
[ -z "$RESTREAM_KEY" ] && { echo "❌ مفتاح Restream فارغ"; exit 1; }

RESTREAM_URL="rtmp://live.restream.io/live/$RESTREAM_KEY"
FIFO="/tmp/relay.ts"
WORKDIR="/tmp/respect_ui"

# إعدادات التوقيت للسلسلة اللانهائية
MAX_STREAM_SEC=19800      # 330 دقيقة = 5.5 ساعات (وقت الخروج)
TRIGGER_AT_SEC=18000      # 300 دقيقة = 5 ساعات (وقت إطلاق الرن التالي)
START_TS=$(date +%s)

IFS=',' read -r -a STREAMERS <<< "$STREAMERS_LIST"
mkdir -p "$WORKDIR"

# ═══════════════════════════════════════════════════
#  1. نظام المراقبة (Watchdog) 
# ═══════════════════════════════════════════════════
API_BASE="https://api.github.com/repos/${GITHUB_REPOSITORY}/actions/workflows/main.yml/runs"

get_active_runs() {
    curl -s -H "Authorization: token ${GITHUB_TOKEN}" \
              -H "Accept: application/vnd.github+json" \
              "${API_BASE}?per_page=30" | \
    jq -r --arg self "$GITHUB_RUN_ID" \
      '.workflow_runs[]? | select(.id != ($self|tonumber)) | select(.status == "in_progress" or .status == "queued" or .status == "waiting") | "\(.id):\(.event):\(.status)"' \
      2>/dev/null || true
}

count_chain() {
    echo "$1" | grep ":repository_dispatch:" | wc -l | tr -d ' '
}

if [ "${TRIGGER_TYPE}" != "repository_dispatch" ]; then
    INITIAL=$(get_active_runs)
    if [ "$(count_chain "$INITIAL")" -gt 0 ]; then
        echo "[$(date)] هناك سلسلة نشطة بالفعل. سيتم الإلغاء لتجنب التكرار."
        exit 0
    fi
fi

echo "[$(date)] جاري فحص الرنات السابقة..."
while true; do
    ACTIVE=$(get_active_runs)
    if [ -z "$ACTIVE" ]; then
        echo "[$(date)] لا يوجد رن نشط. بدء البث الآن."
        break
    fi
    sleep 3
done

# ═══════════════════════════════════════════════════
#  2. إعداد شاشة الانتظار والأنبوب
# ═══════════════════════════════════════════════════
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
    ffmpeg -y -hide_banner -loglevel warning -loop 1 -framerate 30 -i "$WORKDIR/bg.png" -f lavfi -i "anullsrc=r=48000:cl=stereo" -t 4 -c:v libx264 -preset ultrafast -pix_fmt yuv420p -g 30 -c:a aac -ar 48000 -ac 2 -shortest -f mpegts "$WORKDIR/standby.ts"
fi

rm -f "$FIFO"
mkfifo "$FIFO"
exec 3<>"$FIFO"

cleanup() {
    echo "[$(date)] تنظيف وإغلاق..."
    kill -TERM "$OUT" 2>/dev/null
    kill -TERM -- -"$PROD" 2>/dev/null
    pkill -f streamlink 2>/dev/null
    exit 0
}
trap cleanup SIGTERM SIGINT

# ═══════════════════════════════════════════════════
#  3. دوال الإخراج والبث (تم إصلاح الصوت هنا)
# ═══════════════════════════════════════════════════
start_output() {
    ffmpeg -y -hide_banner -loglevel warning -nostdin -thread_queue_size 1024 \
        -fflags +genpts+igndts+discardcorrupt -err_detect ignore_err \
        -f mpegts -i "$FIFO" -map 0:v:0 -map 0:a:0? -c:v copy \
        -c:a aac -b:a 192k -ar 48000 -ac 2 -af "aresample=async=1" \
        -max_muxing_queue_size 4096 -flvflags no_duration_filesize -rtmp_live live \
        -f flv "$RESTREAM_URL" >/tmp/out.log 2>&1 &
    OUT=$!
    sleep 3
}

start_producer_standby() {
    setsid ffmpeg -y -hide_banner -loglevel warning -nostdin -re -stream_loop -1 -i "$WORKDIR/standby.ts" \
        -c copy -f mpegts "$FIFO" >/tmp/prod.log 2>&1 &
    PROD=$!
}

start_producer_live() {
    setsid bash -c "streamlink --http-header 'User-Agent=$UA' 'https://kick.com/$1' best --stdout 2>/dev/null | \
        ffmpeg -y -hide_banner -loglevel warning -nostdin -thread_queue_size 1024 -fflags +genpts+igndts+discardcorrupt -err_detect ignore_err \
        -i pipe:0 -c copy -f mpegts '$FIFO' >/tmp/prod.log 2>&1" &
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

trigger_next() {
    echo "[$(date)] جاري إطلاق الرن التالي في الخلفية..."
    for attempt in $(seq 1 10); do
        CODE=$(curl -s -o /dev/null -w "%{http_code}" \
            -X POST \
            -H "Authorization: token ${GITHUB_TOKEN}" \
            -H "Accept: application/vnd.github+json" \
            "https://api.github.com/repos/${GITHUB_REPOSITORY}/dispatches" \
            -d "{\"event_type\":\"chain-trigger\",\"client_payload\":{\"parent_run\":\"${GITHUB_RUN_ID}\",\"restream_key\":\"${RESTREAM_KEY}\"}}")
        if [ "$CODE" = "204" ]; then
            echo "[$(date)] تم إطلاق الرن التالي بنجاح."
            return 0
        fi
        echo "[$(date)] فشل الإطلاق (HTTP=$CODE). محاولة $attempt..."
        sleep 10
    done
    return 1
}

# ═══════════════════════════════════════════════════
#  4. التشغيل الرئيسي
# ═══════════════════════════════════════════════════
echo "🚀 بدء التشغيل..."
start_producer_standby
sleep 2
start_output

MODE="STANDBY"
ACTIVE=""
ACTIVE_IDX="-1"
TRIGGER_ATTEMPTED=0
TRIGGER_PID=""

while true; do
    NOW=$(date +%s)
    ELAPSED=$((NOW - START_TS))

    # الخروج عند الوصول للحد الأقصى (5.5 ساعات)
    if [ "$ELAPSED" -ge "$MAX_STREAM_SEC" ]; then
        echo "[$(date)] وصلنا للحد الأقصى (5.5 ساعات). تسليم المهمة للرن التالي."
        break
    fi

    # إطلاق الرن التالي عند الدقيقة 300 (5 ساعات)
    if [ "$TRIGGER_ATTEMPTED" -eq 0 ] && [ "$ELAPSED" -ge "$TRIGGER_AT_SEC" ]; then
        TRIGGER_ATTEMPTED=1
        trigger_next &
        TRIGGER_PID=$!
    fi

    if ! kill -0 "$OUT" 2>/dev/null; then
        start_output
    fi

    if ! kill -0 "$PROD" 2>/dev/null; then
        start_producer_standby
        MODE="STANDBY"; ACTIVE=""; ACTIVE_IDX="-1"
    fi

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

    if [ "$MODE" = "LIVE" ] && [ -n "$ACTIVE" ]; then
        URL=$(timeout 3 streamlink --http-header "User-Agent=$UA" "https://kick.com/$ACTIVE" best --stream-url 2>/dev/null | grep -m1 "^http")
        if [ -z "$URL" ]; then
            echo "⏳ توقف $ACTIVE — تحويل للانتظار..."
            kill_producer; sleep 0.1
            start_producer_standby
            MODE="STANDBY"; ACTIVE=""; ACTIVE_IDX="-1"
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

if [ -n "$TRIGGER_PID" ]; then
    wait "$TRIGGER_PID" 2>/dev/null || true
fi

if [ "$TRIGGER_ATTEMPTED" -eq 0 ]; then
    trigger_next || echo "[$(date)] فشل إطلاق الرن الأخير! النظام سيعتمد على الكرون."
fi

cleanup

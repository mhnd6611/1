#!/bin/bash
set +m

# ═══════════════════════════════════════════════════
#  SXB Broadcast — Custom Design (Square 1:1)
# ═══════════════════════════════════════════════════

STREAMER="SXB"
TITLE_AR="توقف البث من شونق"
SUBTITLE_AR="بث شونق سابثون 30 يوم!"
LOGO_URL="https://cdn.imagetourls.com/uploads/tyImg/FoLz2RXV.png"
ACCOUNT_NAME="Slayer_RT"
CLIP_URL="https://www.image2url.com/r2/default/audio/1794504710389-f7679c92-16cb-475d-9cd8-c6e9796dbd69.mp3"
CLIP_INTERVAL=360      
CLIP_VOLUME=0.75 
UA="Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"

RESTREAM_KEY="${RESTREAM_KEY:-re_12215822_event7443f45547114c8aaf6a9153b0da6831}"
[ -z "$RESTREAM_KEY" ] && { echo "❌ مفتاح Restream فارغ"; exit 1; }

RESTREAM_URL="rtmp://live.restream.io/live/$RESTREAM_KEY"
WORKDIR="/tmp/standby_sxb"
mkdir -p "$WORKDIR"

# ═══════════════════════════════════════════════════
#  العداد الثابت
# ═══════════════════════════════════════════════════
echo "00:00:00" > "$WORKDIR/timer.txt"
(
    START_TIME=$(date +%s)
    while true; do
        NOW=$(date +%s)
        DIFF=$((NOW - START_TIME))
        H=$((DIFF / 3600))
        M=$(((DIFF % 3600) / 60))
        S=$((DIFF % 60))
        printf "%02d:%02d:%02d" $H $M $S > "$WORKDIR/timer.txt"
        sleep 1
    done
) &
TIMER_PID=$!
trap "kill $TIMER_PID" EXIT

# ── 1) تصميم واجهة المستخدم (الشعار، الاسم، شارة LIVE) 1:1 ──
if [ ! -f "$WORKDIR/overlay.png" ]; then
    echo "🎨 تصميم التراكب (1:1) حسب طلبك..."
    cat > /tmp/make_overlay.py <<'PYEOF'
from PIL import Image, ImageDraw, ImageFont
import urllib.request, io, os
W, H = 1080, 1080
WORKDIR = os.environ["WORKDIR"]
LOGO_URL = os.environ["LOGO_URL"]
ACCOUNT = os.environ.get("ACCOUNT_NAME", "Slayer_RT")
FONT_AR = os.path.expanduser("~/.fonts/Cairo-var.ttf")
FONT_EN = os.path.expanduser("~/.fonts/Orbitron-var.ttf")

def load_font(path, size, weight=700):
    try:
        font = ImageFont.truetype(path, size)
        axes = font.get_variation_axes()
        if len(axes) == 1: font.set_variation_by_axes([weight])
        elif len(axes) == 2: font.set_variation_by_axes([0, weight])
        return font
    except: return ImageFont.load_default()

img = Image.new("RGBA", (W, H), (0,0,0,0))
d = ImageDraw.Draw(img)

# 1. الشعار والاسم (فوق يسار - X: 3%, Y: 3%)
x_brand = int(W * 0.03)  # 32px
y_brand = int(H * 0.03)  # 32px

try:
    req = urllib.request.Request(LOGO_URL, headers={"User-Agent": "Mozilla/5.0"})
    logo = Image.open(io.BytesIO(urllib.request.urlopen(req, timeout=15).read())).convert("RGBA")
    lw = 80; lh = int(logo.height * (lw/logo.width))
    logo = logo.resize((lw, lh), Image.LANCZOS)
    img.alpha_composite(logo, (x_brand, y_brand))
    x_text = x_brand + lw + 15
    y_text = y_brand + (lh // 2) - 20
except: 
    x_text = x_brand
    y_text = y_brand

d.text((x_text, y_text), ACCOUNT, font=load_font(FONT_EN, 45, 900),
       fill=(255,255,255,255), anchor="lm")

# 2. شارة LIVE (تحت المنتصف - X: 50%, Y: 90%)
# نرسم مستطيل أحمر بحواف دائرية
badge_w, badge_h = 280, 60
x_badge = int(W * 0.50) - (badge_w // 2)
y_badge = int(H * 0.90) - (badge_h // 2)

d.rounded_rectangle([(x_badge, y_badge), (x_badge + badge_w, y_badge + badge_h)], 
                    radius=30, fill=(255, 0, 0, 200), outline=(255,255,255,100), width=2)

# نص "تغطية مباشرة"
d.text((x_badge + badge_w//2 + 15, y_badge + badge_h//2), "تغطية مباشرة", 
       font=load_font(FONT_AR, 32, 900), fill=(255,255,255,255), anchor="mm", direction="rtl")

# النقطة البيضاء
d.ellipse([(x_badge + 20, y_badge + 20), (x_badge + 40, y_badge + 40)], fill=(255,255,255,255))

img.save(f"{WORKDIR}/overlay.png")
PYEOF
    LOGO_URL="$LOGO_URL" ACCOUNT_NAME="$ACCOUNT_NAME" WORKDIR="$WORKDIR" python3 /tmp/make_overlay.py
fi

# ── 2) شاشة الانتظار (خلفية كحلية) ──
if [ ! -f "$WORKDIR/standby.ts" ]; then
    echo "🎨 تصميم شاشة الانتظار..."
    cat > /tmp/make_ui.py <<'PYEOF'
from PIL import Image, ImageDraw, ImageFilter, ImageFont
import os
W, H = 1080, 1080
WORKDIR = os.environ["WORKDIR"]
FONT_AR = os.path.expanduser("~/.fonts/Cairo-var.ttf")

bg = Image.new("RGB", (W, H), (0, 2, 31)) # نفس لون الخلفية اللي اخترته #00021f
d = ImageDraw.Draw(bg)
try:
    font = ImageFont.truetype(FONT_AR, 60)
    d.text((W//2, H//2), "جاري تجهيز البث...", font=font, fill=(255,255,255), anchor="mm")
except: pass
bg.save(f"{WORKDIR}/bg.png")
PYEOF
    WORKDIR="$WORKDIR" python3 /tmp/make_ui.py
    ffmpeg -y -hide_banner -loglevel warning -loop 1 -framerate 30 -i "$WORKDIR/bg.png" \
        -f lavfi -i "anullsrc=r=44100:cl=stereo" -t 2 \
        -c:v libx264 -preset ultrafast -pix_fmt yuv420p -g 60 -r 30 \
        -c:a aac -b:a 128k -ar 44100 -ac 2 -shortest \
        -f mpegts "$WORKDIR/standby.ts"
fi

# ── 3) المقطع الصوتي ──
if [ ! -f "$WORKDIR/interval_audio.wav" ]; then
    if [ -n "$CLIP_URL" ]; then
        echo "🎵 تحميل المقطع الصوتي..."
        curl -sL --max-time 60 -A "Mozilla/5.0" "$CLIP_URL" -o "$WORKDIR/clip_src"
        CLIP_DUR=$(ffprobe -v error -show_entries format=duration -of csv=p=0 "$WORKDIR/clip_src" 2>/dev/null | cut -d. -f1)
        CLIP_DUR=${CLIP_DUR:-10}
        LEAD_SIL=45
        TAIL_SIL=$(( CLIP_INTERVAL - LEAD_SIL - CLIP_DUR ))
        [ "$TAIL_SIL" -lt 10 ] && TAIL_SIL=10
        
        ffmpeg -y -hide_banner -loglevel error -f lavfi -i "anullsrc=r=44100:cl=stereo" -t "$LEAD_SIL" -c:a pcm_s16le -ar 44100 -ac 2 "$WORKDIR/silence_lead.wav"
        ffmpeg -y -hide_banner -loglevel error -f lavfi -i "anullsrc=r=44100:cl=stereo" -t "$TAIL_SIL" -c:a pcm_s16le -ar 44100 -ac 2 "$WORKDIR/silence_tail.wav"
        ffmpeg -y -hide_banner -loglevel error -i "$WORKDIR/silence_lead.wav" -i "$WORKDIR/clip_src" -i "$WORKDIR/silence_tail.wav" \
            -filter_complex "[0:a]aformat=sample_fmts=fltp:channel_layouts=stereo[a0];[1:a]aresample=44100,aformat=sample_fmts=fltp:channel_layouts=stereo[a1];[2:a]aformat=sample_fmts=fltp:channel_layouts=stereo[a2];[a0][a1][a2]concat=n=3:v=0:a=1[out]" \
            -map "[out]" -c:a pcm_s16le -ar 44100 -ac 2 "$WORKDIR/interval_audio.wav"
    fi
fi

# ── 4) تسليم/تسلّم ──
OLD_RUNS=$(gh run list --workflow="main.yml" --status=in_progress --json databaseId --jq '.[].databaseId' 2>/dev/null | awk -v m="$GITHUB_RUN_ID" '$1 != m')
if [ -n "$OLD_RUNS" ]; then
    for R in $OLD_RUNS; do timeout 10 gh run cancel "$R" 2>/dev/null || true; done
    sleep 8
fi

# ── 5) دالة البث المباشر ──
stream_live() {
    LIVE_URL=$(timeout 15 streamlink --http-header "User-Agent=$UA" "https://kick.com/$STREAMER" best --stream-url 2>/dev/null | grep -m1 "^http")
    [ -z "$LIVE_URL" ] && return 1

    echo "🔴 جاري البث بتصميمك المخصص (1:1) وفلاتر الألوان..."

    # تطبيق كل شي مرة واحدة: المقاس المربع + لون #00021f + الفلاتر اللي طلبتها (سطوع، تباين، تشبع) + التراكب + العداد
    ffmpeg -hide_banner -loglevel warning -stats -nostdin \
        -thread_queue_size 512 -fflags +genpts+discardcorrupt -err_detect +crccheck+bitstream+buffer \
        -reconnect 1 -reconnect_streamed 1 -reconnect_delay_max 5 \
        -i "$LIVE_URL" \
        -stream_loop -1 -i "$WORKDIR/interval_audio.wav" \
        -i "$WORKDIR/overlay.png" \
        -filter_complex "\
[0:v]scale=1080:-2,pad=1080:1080:(ow-iw)/2:(oh-ih)/2:color=0x00021f,eq=brightness=0.2:contrast=1.21:saturation=1.63[base];\
[base][2:v]overlay=0:0[ov];\
[ov]drawtext=fontfile=$HOME/.fonts/Orbitron-var.ttf:textfile=$WORKDIR/timer.txt:reload=1:fontsize=45:fontcolor=white:x=w*0.75:y=h*0.03:box=1:boxcolor=0x000000@0.5:boxborderw=10[outv];\
[0:a]aresample=44100,aformat=sample_fmts=fltp:channel_layouts=stereo[game];\
[1:a]aresample=44100,aformat=sample_fmts=fltp:channel_layouts=stereo,volume=${CLIP_VOLUME}[clip];\
[clip]asplit=2[clip_sc][clip_mix];\
[game][clip_sc]sidechaincompress=threshold=0.04:ratio=8:attack=15:release=500[game_duck];\
[game_duck][clip_mix]amix=inputs=2:duration=first:dropout_transition=0:normalize=0[outa]" \
        -map "[outv]" -map "[outa]" \
        -c:v libx264 -preset ultrafast -profile:v high -threads 2 \
        -b:v 5000k -maxrate 5000k -bufsize 10000k \
        -pix_fmt yuv420p -g 60 -r 30 \
        -c:a aac -b:a 160k -ar 44100 -ac 2 \
        -max_muxing_queue_size 9999 -flvflags no_duration_filesize \
        -f flv "$RESTREAM_URL"
}

stream_standby() {
    echo "⏳ إرسال شاشة الانتظار..."
    ffmpeg -hide_banner -loglevel error -nostdin \
        -re -stream_loop -1 -i "$WORKDIR/standby.ts" \
        -c copy -f flv "$RESTREAM_URL"
}

# ── 6) الحلقة الرئيسية (صمود مطلق) ──
echo "🚀 بدء المراقبة..."
while true; do
    stream_live
    EXIT_CODE=$?
    if [ $EXIT_CODE -ne 0 ]; then
        echo "⚠️ انقطع البث المباشر. تفعيل شاشة الانتظار..."
        stream_standby
    fi
    echo "⏳ إعادة الفحص بعد 5 ثوانٍ..."
    sleep 5
done

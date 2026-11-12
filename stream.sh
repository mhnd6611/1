#!/bin/bash
set +m

# ═══════════════════════════════════════════════════
#  SXB Broadcast — Stable Timer + Max Quality
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
#  بدء العداد الخلفي
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

# ── 1) شاشة الانتظار ──
if [ ! -f "$WORKDIR/standby.ts" ]; then
    # ... (نفس كود البايثون لتصميم الشاشة والتراكب والصوت) ...
    echo "🎨 تصميم شاشة الانتظار..."
    cat > /tmp/make_ui.py <<'PYEOF'
from PIL import Image, ImageDraw, ImageFilter, ImageFont
import urllib.request, io, os
W, H = 1080, 1920
WORKDIR = os.environ["WORKDIR"]
FONT_AR = os.path.expanduser("~/.fonts/Cairo-var.ttf")
FONT_EN = os.path.expanduser("~/.fonts/Orbitron-var.ttf")
TITLE = os.environ.get("TITLE_AR", "توقف البث")
SUBTITLE = os.environ.get("SUBTITLE_AR", "جاري الانتظار...")
LOGO_URL = os.environ.get("LOGO_URL", "")
ACCOUNT = os.environ.get("ACCOUNT_NAME", "Slayer_RT")

def load_font(path, size, weight=700):
    try:
        font = ImageFont.truetype(path, size)
        axes = font.get_variation_axes()
        if len(axes) == 1: font.set_variation_by_axes([weight])
        elif len(axes) == 2: font.set_variation_by_axes([0, weight])
        return font
    except: return ImageFont.load_default()

bg = Image.new("RGB", (W, H))
d = ImageDraw.Draw(bg)
for y in range(H):
    t = y / H
    d.line([(0, y), (W, y)], fill=(int(30*(1-t)), 0, 0))
glow = Image.new("RGBA", (W, H), (0,0,0,0))
gd = ImageDraw.Draw(glow)
gd.ellipse([W//2-500, H//2-700, W//2+500, H//2+700], fill=(255,0,0,90))
bg = Image.alpha_composite(bg.convert("RGBA"), glow.filter(ImageFilter.GaussianBlur(250)))

corner = Image.new("RGBA", (W, H), (0,0,0,0))
cd = ImageDraw.Draw(corner)
S = 60
def br(cx, cy, fx, fy):
    cd.line([(cx,cy),(cx+S*fx,cy)], fill=(255,0,0,255), width=4)
    cd.line([(cx,cy),(cx,cy+S*fy)], fill=(255,0,0,255), width=4)
br(30,30,1,1); br(W-30,30,-1,1); br(30,H-30,1,-1); br(W-30,H-30,-1,-1)
bg = Image.alpha_composite(bg, corner)

cw, ch = 900, 760
cx0, cy0 = (W-cw)//2, (H-ch)//2
card = Image.new("RGBA", (W, H), (0,0,0,0))
ImageDraw.Draw(card).rounded_rectangle([(cx0,cy0),(cx0+cw,cy0+ch)], radius=24,
    fill=(20,0,0,180), outline=(255,0,0,140), width=3)
bg = Image.alpha_composite(bg, card)

y_logo_end = cy0 + 80
try:
    req = urllib.request.Request(LOGO_URL, headers={"User-Agent": "Mozilla/5.0"})
    logo = Image.open(io.BytesIO(urllib.request.urlopen(req, timeout=15).read())).convert("RGBA")
    lw = 260; lh = int(logo.height * (lw/logo.width))
    logo = logo.resize((lw, lh), Image.LANCZOS)
    bg.alpha_composite(logo, ((W-lw)//2, cy0+40))
    y_logo_end = cy0 + 40 + lh + 30
except: pass

d2 = ImageDraw.Draw(bg)
d2.text((W//2, y_logo_end+60),  TITLE,    font=load_font(FONT_AR, 82, 900),
        fill=(255,255,255,255), anchor="mm", direction="rtl")
d2.text((W//2, y_logo_end+170), SUBTITLE, font=load_font(FONT_AR, 42, 700),
        fill=(255,255,255,210), anchor="mm", direction="rtl")
d2.text((W//2, cy0+ch-100),     ACCOUNT,  font=load_font(FONT_EN, 64, 900),
        fill=(255,0,0,255), anchor="mm")

bg.convert("RGB").save(f"{WORKDIR}/bg.png")
PYEOF
    WORKDIR="$WORKDIR" ACCOUNT_NAME="$ACCOUNT_NAME" TITLE_AR="$TITLE_AR" \
    SUBTITLE_AR="$SUBTITLE_AR" LOGO_URL="$LOGO_URL" python3 /tmp/make_ui.py
    ffmpeg -y -hide_banner -loglevel warning -loop 1 -framerate 30 -i "$WORKDIR/bg.png" \
        -f lavfi -i "anullsrc=r=44100:cl=stereo" -t 4 \
        -c:v libx264 -preset ultrafast -pix_fmt yuv420p -g 60 -r 30 \
        -c:a aac -b:a 128k -ar 44100 -ac 2 -shortest \
        -f mpegts "$WORKDIR/standby.ts"
fi

# ── 2) صورة التراكب ──
if [ ! -f "$WORKDIR/overlay.png" ]; then
    echo "🎨 تصميم التراكب..."
    cat > /tmp/make_overlay.py <<'PYEOF'
from PIL import Image, ImageDraw, ImageFont
import urllib.request, io, os
W, H = 1080, 1920
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
S = 50
def br(cx, cy, fx, fy):
    d.line([(cx,cy),(cx+S*fx,cy)], fill=(255,0,0,220), width=3)
    d.line([(cx,cy),(cx,cy+S*fy)], fill=(255,0,0,220), width=3)
br(24,24,1,1); br(W-24,24,-1,1); br(24,H-24,1,-1); br(W-24,H-24,-1,-1)

y_next = 60
try:
    req = urllib.request.Request(LOGO_URL, headers={"User-Agent": "Mozilla/5.0"})
    logo = Image.open(io.BytesIO(urllib.request.urlopen(req, timeout=15).read())).convert("RGBA")
    lw = 200; lh = int(logo.height * (lw/logo.width))
    logo = logo.resize((lw, lh), Image.LANCZOS)
    img.alpha_composite(logo, ((W-lw)//2, 60))
    y_next = 60 + lh + 30
except: pass
d.text((W//2, y_next+30), ACCOUNT, font=load_font(FONT_EN, 52, 900),
       fill=(255,255,255,255), anchor="mm")

bar_y, bar_h = H-200, 130
bar = Image.new("RGBA", (W, bar_h), (0,0,0,0))
bd = ImageDraw.Draw(bar)
for x in range(W):
    t = x / W
    bd.line([(x,0),(x,bar_h)], fill=(int(15+25*t), 0, 0, 215))
mask = Image.new("L", (W, bar_h), 0)
ImageDraw.Draw(mask).rounded_rectangle([(0,0),(W-1,bar_h-1)], radius=20, fill=255)
img.paste(bar, (0, bar_y), mask)
d.rounded_rectangle([(0,bar_y),(W-1,bar_y+bar_h-1)], radius=20, outline=(255,0,0,180), width=3)
d.text((90, bar_y+bar_h//2), "تغطية مباشرة", font=load_font(FONT_AR, 54, 900),
       fill=(255,255,255,255), anchor="lm", direction="rtl")

img.save(f"{WORKDIR}/overlay.png")
PYEOF
    LOGO_URL="$LOGO_URL" ACCOUNT_NAME="$ACCOUNT_NAME" WORKDIR="$WORKDIR" python3 /tmp/make_overlay.py
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
        
        echo "   مدة المقطع: ${CLIP_DUR}s — صمت مبدئي: ${LEAD_SIL}s — صمت نهائي: ${TAIL_SIL}s"
        
        ffmpeg -y -hide_banner -loglevel error -f lavfi -i "anullsrc=r=44100:cl=stereo" \
            -t "$LEAD_SIL" -c:a pcm_s16le -ar 44100 -ac 2 "$WORKDIR/silence_lead.wav"
        ffmpeg -y -hide_banner -loglevel error -f lavfi -i "anullsrc=r=44100:cl=stereo" \
            -t "$TAIL_SIL" -c:a pcm_s16le -ar 44100 -ac 2 "$WORKDIR/silence_tail.wav"
            
        ffmpeg -y -hide_banner -loglevel error \
            -i "$WORKDIR/silence_lead.wav" -i "$WORKDIR/clip_src" -i "$WORKDIR/silence_tail.wav" \
            -filter_complex "[0:a]aformat=sample_fmts=fltp:channel_layouts=stereo[a0];\
[1:a]aresample=44100,aformat=sample_fmts=fltp:channel_layouts=stereo[a1];\
[2:a]aformat=sample_fmts=fltp:channel_layouts=stereo[a2];\
[a0][a1][a2]concat=n=3:v=0:a=1[out]" \
            -map "[out]" -c:a pcm_s16le -ar 44100 -ac 2 "$WORKDIR/interval_audio.wav"
    else
        ffmpeg -y -hide_banner -loglevel error -f lavfi -i "anullsrc=r=44100:cl=stereo" \
            -t "$CLIP_INTERVAL" -c:a pcm_s16le -ar 44100 -ac 2 "$WORKDIR/interval_audio.wav"
    fi
fi

# ── 4) تسليم/تسلّم ──
echo "🔍 البحث عن رنات قديمة..."
OLD_RUNS=$(gh run list --workflow="main.yml" --status=in_progress --json databaseId \
           --jq '.[].databaseId' 2>/dev/null | awk -v m="$GITHUB_RUN_ID" '$1 != m')
if [ -n "$OLD_RUNS" ]; then
    echo "⚠️ رن قديم نشط: $OLD_RUNS"
    for R in $OLD_RUNS; do timeout 10 gh run cancel "$R" 2>/dev/null || true; done
    sleep 8
else
    echo "✅ لا يوجد رن قديم"
fi

# ── 5) دوال البث ──
stream_live() {
    echo "🔴 بث مباشر: $STREAMER (جودة عالية + الخلفية المموهة) — مقطع كل $CLIP_INTERVAL ث"
    
    # جلب الرابط المباشر أولاً
    LIVE_URL=$(timeout 15 streamlink --http-header "User-Agent=$UA" "https://kick.com/$STREAMER" best --stream-url 2>/dev/null | grep -m1 "^http")
    [ -z "$LIVE_URL" ] && return 1

    # استخدام الرابط مباشرة في ffmpeg (يمنع انهيار Bus error)
    ffmpeg -hide_banner -loglevel warning -stats -nostdin \
        -thread_queue_size 512 \
        -fflags +genpts+discardcorrupt \
        -err_detect ignore_err \
        -reconnect 1 -reconnect_streamed 1 -reconnect_delay_max 5 \
        -i "$LIVE_URL" \
        -stream_loop -1 -i "$WORKDIR/interval_audio.wav" \
        -i "$WORKDIR/overlay.png" \
        -filter_complex "\
[0:v]scale=360:640:force_original_aspect_ratio=increase,crop=360:640,boxblur=15:3,scale=1080:1920:flags=bicubic[bg];\
[0:v]scale=1080:-2:flags=lanczos[fg];\
[bg][fg]overlay=(W-w)/2:(H-h)/2[base];\
[base][2:v]overlay=0:0[ov];\
[ov]drawtext=fontfile=$HOME/.fonts/Cairo-var.ttf:textfile=$WORKDIR/timer.txt:reload=1:fontsize=44:fontcolor=white:x=w-tw-120:y=h-165:box=1:boxcolor=0x000000@0.65:boxborderw=14[outv];\
[0:a]aresample=44100,aformat=sample_fmts=fltp:channel_layouts=stereo[game];\
[1:a]aresample=44100,aformat=sample_fmts=fltp:channel_layouts=stereo,volume=${CLIP_VOLUME}[clip];\
[clip]asplit=2[clip_sc][clip_mix];\
[game][clip_sc]sidechaincompress=threshold=0.04:ratio=8:attack=15:release=500[game_duck];\
[game_duck][clip_mix]amix=inputs=2:duration=first:dropout_transition=0:normalize=0[outa]" \
        -map "[outv]" -map "[outa]" \
        -c:v libx264 -preset fast -tune film -profile:v high -level 4.2 \
        -b:v 6000k -maxrate 6000k -bufsize 12000k \
        -pix_fmt yuv420p -g 60 -r 30 \
        -c:a aac -b:a 160k -ar 44100 -ac 2 \
        -max_muxing_queue_size 4096 -flvflags no_duration_filesize \
        -f flv "$RESTREAM_URL"
}

stream_standby() {
    echo "⏳ إرسال شاشة الانتظار..."
    # غيرنا اللوق إلى error عشان ما يزعجك بتكرار السطور كل 4 ثواني
    ffmpeg -hide_banner -loglevel error -nostdin \
        -re -stream_loop -1 -i "$WORKDIR/standby.ts" \
        -c copy -f flv "$RESTREAM_URL"
}

# ── 6) الحلقة الرئيسية ──
echo "🚀 بدء المراقبة..."
while true; do
    LIVE_URL=$(timeout 15 streamlink --http-header "User-Agent=$UA" "https://kick.com/$STREAMER" best --stream-url 2>/dev/null | grep -m1 "^http")
    
    if [ -n "$LIVE_URL" ]; then
        stream_live
        echo "⚠️ انقطع البث المباشر. محاولة الانتظار..."
    else
        stream_standby
        echo "⚠️ البث غير متاح. إرسال شاشة الانتظار..."
    fi
    
    # انتظار 15 ثانية قبل المحاولة مرة charm (يمنع التكرار السريع)
    echo "⏳ إعادة الفحص بعد 15 ثانية..."
    sleep 15
done

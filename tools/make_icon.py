import sys, math
from PIL import Image, ImageDraw, ImageFilter, ImageFont
out = sys.argv[1]
S = 2048
img = Image.new("RGB", (S, S))
# diagonal orange gradient
top = (255, 170, 60); bot = (232, 84, 10)
px = img.load()
for y in range(S):
    for x in range(0, S):
        t = (0.65*y + 0.35*x) / S
        px[x, y] = tuple(int(top[i] + (bot[i]-top[i]) * t) for i in range(3))
# soft highlight circle
hl = Image.new("L", (S, S), 0)
ImageDraw.Draw(hl).ellipse((-S*0.3, -S*0.45, S*1.0, S*0.55), fill=60)
hl = hl.filter(ImageFilter.GaussianBlur(S*0.08))
img = Image.composite(Image.new("RGB", (S, S), (255, 230, 190)), img, hl)

# heart shape (parametric)
def heart_pts(cx, cy, sc):
    pts = []
    for i in range(720):
        t = i / 720 * 2 * math.pi
        x = 16 * math.sin(t) ** 3
        y = 13*math.cos(t) - 5*math.cos(2*t) - 2*math.cos(3*t) - math.cos(4*t)
        pts.append((cx + x*sc, cy - y*sc))
    return pts
cx, cy, sc = S/2, S*0.53, S*0.0215
# shadow
sh = Image.new("L", (S, S), 0)
ImageDraw.Draw(sh).polygon(heart_pts(cx, cy + S*0.025, sc), fill=110)
sh = sh.filter(ImageFilter.GaussianBlur(S*0.025))
img = Image.composite(Image.new("RGB", (S, S), (150, 50, 0)), img, sh)
d = ImageDraw.Draw(img)
d.polygon(heart_pts(cx, cy, sc), fill=(255, 255, 255))

# ECG line across the heart
w = S*0.028
y0 = cy - S*0.02
line = [(S*0.12, y0), (S*0.30, y0), (S*0.36, y0 - S*0.06), (S*0.42, y0 + S*0.05),
        (S*0.49, y0 - S*0.24), (S*0.56, y0 + S*0.17), (S*0.62, y0 - S*0.03),
        (S*0.66, y0), (S*0.88, y0)]
col = (238, 92, 14)
d.line(line, fill=col, width=int(w), joint="curve")
for p in (line[0], line[-1]):
    d.ellipse((p[0]-w/2, p[1]-w/2, p[0]+w/2, p[1]+w/2), fill=col)
# white segments outside the heart for contrast
img = img.resize((1024, 1024), Image.LANCZOS)
img.save(out, "PNG")
print("ok", img.size, img.mode)

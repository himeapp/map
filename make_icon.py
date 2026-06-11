#!/usr/bin/env python3
"""기존 민트 글로우 아이콘을 바닥에 눕히고 그 위에 파란 지도 핀을 세운 아이콘 생성."""
import math
from PIL import Image, ImageDraw, ImageFilter

S = 2                      # supersample
W = 1024 * S
SRC = "icon.png"
OUT = "icon_pin.png"


def lerp(a, b, t):
    return tuple(int(round(a[i] + (b[i] - a[i]) * t)) for i in range(len(a)))


# ---------------------------------------------------------------- 배경(초록 동심원 지면, 풀블리드)
# 가운데 밝은 민트 → 가장자리 진한 민트의 방사형 그라데이션 + 은은한 동심원 링.
# 저해상도로 그린 뒤 확대해서 빠르고 매끄럽게.
N = 320
cxr, cyr = 0.5, 0.55          # 동심원 중심(핀 발밑 쪽으로 살짝 아래)
c_in = (224, 250, 244)        # 중심(밝은 민트)
c_out = (120, 214, 204)       # 가장자리(진한 민트)
field = Image.new("RGB", (N, N))
fp = field.load()
maxr = math.hypot(max(cxr, 1 - cxr), max(cyr, 1 - cyr))
for j in range(N):
    for i in range(N):
        dx = i / N - cxr
        dy = j / N - cyr
        r = math.hypot(dx, dy) / maxr           # 0..1
        col = lerp(c_in, c_out, min(1.0, r ** 0.85))
        ring = math.sin(r * 26) * 7             # 동심원 링(밝기 ±7)
        col = tuple(max(0, min(255, c + int(ring))) for c in col)
        fp[i, j] = col
canvas = field.resize((W, W), Image.LANCZOS).convert("RGBA")


# ---------------------------------------------------------------- 바닥(눕힌 아이콘)
def solve_perspective(dst, src):
    """출력(dst) 좌표 -> 입력(src) 좌표 매핑 8계수 (가우스 소거)."""
    A, b = [], []
    for (X, Y), (x, y) in zip(dst, src):
        A.append([X, Y, 1, 0, 0, 0, -X * x, -Y * x]); b.append(x)
        A.append([0, 0, 0, X, Y, 1, -X * y, -Y * y]); b.append(y)
    n = 8
    M = [A[i] + [b[i]] for i in range(n)]
    for col in range(n):
        piv = max(range(col, n), key=lambda r: abs(M[r][col]))
        M[col], M[piv] = M[piv], M[col]
        pv = M[col][col]
        M[col] = [v / pv for v in M[col]]
        for r in range(n):
            if r != col and M[r][col] != 0:
                f = M[r][col]
                M[r] = [M[r][k] - f * M[col][k] for k in range(n + 1)]
    return [M[i][n] for i in range(n)]


# (지면은 위 배경이 곧 풀블리드 초록 동심원이므로 별도 바닥 합성 없음)

# ---------------------------------------------------------------- 핀 그림자
# 핀 끝점 바로 아래에 맑고 부드러운 타원 그림자
shadow = Image.new("RGBA", (W, W), (0, 0, 0, 0))
sd = ImageDraw.Draw(shadow)
sx, sy = 512 * S, 606 * S
sd.ellipse([sx - 118 * S, sy - 30 * S, sx + 118 * S, sy + 30 * S],
           fill=(36, 96, 150, 75))
shadow = shadow.filter(ImageFilter.GaussianBlur(22 * S))
canvas.alpha_composite(shadow)


# ---------------------------------------------------------------- 파란 지도 핀
cx = 512 * S
head_y = 350 * S
tip_y = 600 * S
r = 150 * S

# 외곽선(teardrop) 계산
d = tip_y - head_y
beta = math.acos(r / d)
# 아래 방향(0,1) 기준 ± beta 회전한 접점
t1 = (cx + r * math.sin(beta),  head_y + r * math.cos(beta))   # 오른쪽 접점
t2 = (cx - r * math.sin(beta),  head_y + r * math.cos(beta))   # 왼쪽 접점
tip = (cx, tip_y)

pin = Image.new("RGBA", (W, W), (0, 0, 0, 0))
pd = ImageDraw.Draw(pin)
# 핀 실루엣(머리 원 + 꼬리 삼각형) — 단색으로 채워 마스크로 사용
sil = Image.new("L", (W, W), 0)
sdl = ImageDraw.Draw(sil)
sdl.ellipse([cx - r, head_y - r, cx + r, head_y + r], fill=255)
sdl.polygon([t1, t2, tip], fill=255)

# 파란 세로 그라데이션
grad = Image.new("RGBA", (W, W), (0, 0, 0, 0))
gdr = ImageDraw.Draw(grad)
c_top = (74, 158, 255)
c_bot = (20, 84, 214)
gy0, gy1 = head_y - r, tip_y
for y in range(int(gy0), int(gy1) + 1):
    t = (y - gy0) / (gy1 - gy0)
    gdr.line([(0, y), (W, y)], fill=lerp(c_top, c_bot, t) + (255,))
grad.putalpha(sil)
pin.alpha_composite(grad)

# 윗쪽 하이라이트(광택)
hl = Image.new("RGBA", (W, W), (0, 0, 0, 0))
hd = ImageDraw.Draw(hl)
hd.ellipse([cx - r * 0.62, head_y - r * 0.72, cx + r * 0.62, head_y - r * 0.02],
           fill=(255, 255, 255, 70))
hl = hl.filter(ImageFilter.GaussianBlur(10 * S))
hlm = Image.composite(hl, Image.new("RGBA", (W, W), (0, 0, 0, 0)),
                      sil)
pin.alpha_composite(hlm)

# 가운데 흰 구멍
hole_r = int(r * 0.42)
hole = Image.new("RGBA", (W, W), (0, 0, 0, 0))
hod = ImageDraw.Draw(hole)
hod.ellipse([cx - hole_r, head_y - hole_r, cx + hole_r, head_y + hole_r],
            fill=(255, 255, 255, 255))
# 구멍 안쪽 살짝 그림자 링
hod.ellipse([cx - hole_r, head_y - hole_r, cx + hole_r, head_y + hole_r],
            outline=(15, 70, 180, 90), width=int(5 * S))
pin.alpha_composite(hole)

canvas.alpha_composite(pin)


# ---------------------------------------------------------------- 마무리
out = canvas.convert("RGB").resize((1024, 1024), Image.LANCZOS)
out.save(OUT, "PNG")
print("saved", OUT)

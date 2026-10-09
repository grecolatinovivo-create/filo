#!/usr/bin/env python3
"""FILO — preparazione del kit grafico "velluto blu-notte + filo d'oro".

Script RIPRODUCIBILE: dai PNG sorgente del kit (generati da IA, RGBA 1254² ecc.)
produce gli imageset dell'asset catalog usati dal tema `notte`
(Theme.usaArte == true). Gli altri temi restano vettoriali.

Uso:
    python3 native-ios/tools/prepare_art.py [CARTELLA_KIT] [--preview OUT.png]

    CARTELLA_KIT  default /home/claude/kit (contiene filo_*.png)
    --preview     salva anche un'anteprima statica di una griglia 5×5

Output: native-ios/Resources/Assets.xcassets/<Nome>.imageset/{<Nome>.png,
Contents.json}. Le PNG passano da pngquant se disponibile (altrimenti
PIL optimize=True). Dipendenze: Pillow, numpy.

Regole di lavorazione (vedi anche i commenti di ogni funzione):
- Tessere idle/lit: ritaglio sul CORPO (soglia alfa 240: niente bagliore né
  ombra), corpo riportato ESATTAMENTE alla stessa misura (BODY×BODY px) e
  centrato in una tela TILE×TILE identica per entrambe: sovrapponendo le due
  immagini i corpi combaciano al pixel. Il bagliore della lit e l'ombra della
  idle restano nel margine fisso (MARGIN su ogni lato), con sfumatura ai bordi.
- Sfondo: 1290×2796 (iPhone Pro Max @3x), LANCZOS + leggera nitidezza, opaco.
- Logo, card, icone: ritaglio sul bbox alfa e ridimensionamento.
"""
from __future__ import annotations

import json
import os
import shutil
import subprocess
import sys
from pathlib import Path

import numpy as np
from PIL import Image, ImageFilter

REPO_IOS = Path(__file__).resolve().parent.parent
ASSETS = REPO_IOS / "Resources" / "Assets.xcassets"

# Tessera: tela 240 px (= 80 pt @3x), margine 8% per lato → corpo ~202 px
# (~67 pt @3x, cella di gioco tipica 60–70 pt). In SwiftUI l'immagine si
# disegna a `side / BODY_FRACTION` così il CORPO coincide con la cella.
TILE = 240
MARGIN = 0.08
BODY = int(round(TILE * (1 - 2 * MARGIN)))   # 202
BODY_ALPHA = 240                              # soglia "corpo pieno"
EDGE_FADE = 6                                 # px di sfumatura alfa al bordo tela

BG_SIZE = (1290, 2796)
LOGO_W = 1200
CARD_SIDE = 360
ICON_MAX = 180


# ---------------------------------------------------------------- utilità

def alpha_bbox(im: Image.Image, thr: int) -> tuple[int, int, int, int]:
    """Bounding box (x0, y0, x1_incl, y1_incl) dei pixel con alfa >= thr."""
    a = np.asarray(im.getchannel("A"))
    ys, xs = np.where(a >= thr)
    if len(xs) == 0:
        raise ValueError("immagine completamente trasparente")
    return int(xs.min()), int(ys.min()), int(xs.max()), int(ys.max())


def crop_bbox(im: Image.Image, thr: int = 8, pad: int = 0) -> Image.Image:
    x0, y0, x1, y1 = alpha_bbox(im, thr)
    return im.crop((max(0, x0 - pad), max(0, y0 - pad),
                    min(im.width, x1 + 1 + pad), min(im.height, y1 + 1 + pad)))


def fit(im: Image.Image, max_side: int) -> Image.Image:
    s = max_side / max(im.size)
    size = (max(1, round(im.width * s)), max(1, round(im.height * s)))
    return im.resize(size, Image.LANCZOS)


def edge_fade(im: Image.Image, px: int) -> Image.Image:
    """Attenua l'alfa negli ultimi `px` pixel della tela (niente tagli netti)."""
    w, h = im.size
    xs = np.minimum(np.arange(w), np.arange(w)[::-1]).astype(np.float32)
    ys = np.minimum(np.arange(h), np.arange(h)[::-1]).astype(np.float32)
    rx = np.clip(xs / px, 0, 1)
    ry = np.clip(ys / px, 0, 1)
    ramp = np.minimum.outer(ry, rx)
    arr = np.asarray(im).astype(np.float32)
    arr[..., 3] *= ramp
    return Image.fromarray(arr.clip(0, 255).astype(np.uint8), "RGBA")


def write_imageset(name: str, im: Image.Image, scale: str = "3x") -> Path:
    """Scrive <name>.imageset con un solo PNG (idiom universal, scala `scale`)."""
    d = ASSETS / f"{name}.imageset"
    d.mkdir(parents=True, exist_ok=True)
    for old in d.glob("*.png"):
        old.unlink()
    png = d / f"{name}.png"
    im.save(png, optimize=True)
    optimize_png(png, opaque=(im.mode == "RGB"))
    images = []
    for s in ("1x", "2x", "3x"):
        entry = {"idiom": "universal", "scale": s}
        if s == scale:
            entry = {"filename": png.name, **entry}
        images.append(entry)
    contents = {"images": images, "info": {"author": "xcode", "version": 1}}
    (d / "Contents.json").write_text(json.dumps(contents, indent=2) + "\n")
    return png


def optimize_png(path: Path, opaque: bool) -> None:
    exe = shutil.which("pngquant")
    if exe:
        # Qualità alta: gradienti e bagliori senza banding visibile.
        q = "88-100" if opaque else "85-100"
        r = subprocess.run([exe, "--force", "--skip-if-larger", "--strip", "--speed", "1",
                            "--quality", q, "--output", str(path), str(path)],
                           capture_output=True)
        if r.returncode not in (0, 98, 99):   # 98/99: non conveniente → resta l'originale
            print(f"  pngquant rc={r.returncode} su {path.name}: {r.stderr.decode()[:200]}")
    else:
        Image.open(path).save(path, optimize=True)


# ---------------------------------------------------------------- tessere

def tile(src: Image.Image) -> Image.Image:
    """Corpo della tessera → BODY×BODY px esatti, centrato in tela TILE×TILE."""
    x0, y0, x1, y1 = alpha_bbox(src, BODY_ALPHA)
    bw, bh = x1 - x0 + 1, y1 - y0 + 1
    sx, sy = BODY / bw, BODY / bh            # scala (quasi uniforme: ~1% di differenza)
    big = src.resize((round(src.width * sx), round(src.height * sy)), Image.LANCZOS)
    # bbox del corpo NELL'immagine ridimensionata (niente errori di arrotondamento)
    bx0, by0, bx1, by1 = alpha_bbox(big, BODY_ALPHA)
    cx, cy = (bx0 + bx1 + 1) / 2, (by0 + by1 + 1) / 2
    left, top = round(cx - TILE / 2), round(cy - TILE / 2)
    canvas = Image.new("RGBA", (TILE, TILE), (0, 0, 0, 0))
    canvas.alpha_composite(big, dest=(max(0, -left), max(0, -top)),
                           source=(max(0, left), max(0, top)))
    return edge_fade(canvas, EDGE_FADE)


def body_metrics(im: Image.Image) -> dict:
    x0, y0, x1, y1 = alpha_bbox(im, BODY_ALPHA)
    a = np.asarray(im.getchannel("A"))
    # raggio d'angolo: prima riga (dall'alto) in cui il corpo è largo quanto il bbox
    r = 0
    for y in range(y0, y1):
        xs = np.where(a[y] >= BODY_ALPHA)[0]
        if xs.min() <= x0 + 1:
            r = y - y0
            break
    return {"bbox": (x0, y0, x1, y1), "w": x1 - x0 + 1, "h": y1 - y0 + 1, "radius": r}


# ---------------------------------------------------------------- sfondo

def background(src: Image.Image) -> Image.Image:
    im = src.convert("RGB")
    tw, th = BG_SIZE
    # ritaglio centrale al rapporto di destinazione, poi ridimensionamento
    target = tw / th
    if im.width / im.height > target:
        w = round(im.height * target)
        im = im.crop(((im.width - w) // 2, 0, (im.width - w) // 2 + w, im.height))
    else:
        h = round(im.width / target)
        im = im.crop((0, (im.height - h) // 2, im.width, (im.height - h) // 2 + h))
    im = im.resize(BG_SIZE, Image.LANCZOS)
    return im.filter(ImageFilter.UnsharpMask(radius=1.4, percent=35, threshold=2))


# ---------------------------------------------------------------- icone

def split_icons(sheet: Image.Image, thr: int = 8) -> list[Image.Image]:
    """Separa le icone per colonne di alfa vuote (da sinistra a destra)."""
    a = np.asarray(sheet.getchannel("A"))
    col = (a >= thr).any(axis=0)
    runs, start = [], None
    for x, v in enumerate(col):
        if v and start is None:
            start = x
        elif not v and start is not None:
            runs.append((start, x))
            start = None
    if start is not None:
        runs.append((start, len(col)))
    runs = [r for r in runs if r[1] - r[0] > 40]          # scarta pulviscolo
    return [crop_bbox(sheet.crop((x0, 0, x1, sheet.height)), thr) for x0, x1 in runs]


# ---------------------------------------------------------------- anteprima

def preview(out: Path) -> None:
    """Griglia 5×5 (6 tessere accese + filo d'oro) con gli asset finali;
    ordine dei livelli come in app: tessere → filo → numeri."""
    from PIL import ImageDraw, ImageFont

    def load(n):
        return Image.open(ASSETS / f"{n}.imageset" / f"{n}.png").convert("RGBA")

    bg, idle, lit = load("BgVelluto"), load("TileIdle"), load("TileLit")
    W = 1170                                     # iPhone @3x, larghezza 390 pt
    H = round(W * 1.15)
    canvas = bg.convert("RGBA").resize((W, round(W * bg.height / bg.width)), Image.LANCZOS)
    canvas = canvas.crop((0, (canvas.height - H) // 2, W, (canvas.height - H) // 2 + H))

    gap_pt, pad_pt = 6, 16
    side = (W / 3 - 2 * pad_pt - 4 * gap_pt) / 5 * 3     # px @3x
    gap, pad = gap_pt * 3, pad_pt * 3
    oy = (H - (5 * side + 4 * gap)) / 2
    path = [7, 8, 13, 18, 17, 16]
    vals = [3, 7, 2, 9, 4, 1, 6, 5, 8, 2, 4, 9, 3, 7, 1, 6, 2, 8, 5, 3, 7, 4, 1, 9, 6]
    draw_size = round(side / (1 - 2 * MARGIN))
    idle_s = idle.resize((draw_size, draw_size), Image.LANCZOS)
    lit_s = lit.resize((draw_size, draw_size), Image.LANCZOS)
    try:
        font = ImageFont.truetype("DejaVuSansMono-Bold.ttf", round(side * 0.4))
    except OSError:
        font = ImageFont.load_default()

    def centre(i):
        return (pad + (i % 5) * (side + gap) + side / 2, oy + (i // 5) * (side + gap) + side / 2)

    for i in range(25):
        cx, cy = centre(i)
        tile_im = lit_s if i in path else idle_s
        canvas.alpha_composite(tile_im, (round(cx - draw_size / 2), round(cy - draw_size / 2)))
    # filo "corda d'oro": alone sfocato + tratto a 3 toni + anima chiara
    pts = [centre(i) for i in path]
    glow = Image.new("RGBA", canvas.size, (0, 0, 0, 0))
    gd = ImageDraw.Draw(glow)
    gd.line(pts, fill=(255, 196, 64, 170), width=round(7.5 * 3 * 2.2), joint="curve")
    glow = glow.filter(ImageFilter.GaussianBlur(9))
    canvas.alpha_composite(glow)
    rope = Image.new("RGBA", canvas.size, (0, 0, 0, 0))
    rd = ImageDraw.Draw(rope)
    w = round(7.5 * 3)
    # contorno scuro sottile (CordaOro: oroOmbra 55%) che stacca la corda dall'oro
    rd.line(pts, fill=(0x4A, 0x30, 0x04, 140), width=w + 8, joint="curve")
    for p in pts:
        rd.ellipse((p[0] - w / 2, p[1] - w / 2, p[0] + w / 2, p[1] + w / 2), fill=(0xC8, 0x8A, 0x12, 255))
    rd.line(pts, fill=(0xC8, 0x8A, 0x12, 255), width=w, joint="curve")
    rd.line(pts, fill=(0xF5, 0xB5, 0x31, 255), width=round(w * 0.75), joint="curve")
    rd.line(pts, fill=(0xFF, 0xD7, 0x66, 255), width=round(w * 0.45), joint="curve")
    rd.line(pts, fill=(0xFF, 0xF4, 0xD2, 230), width=max(2, round(w * 0.16)), joint="curve")
    canvas.alpha_composite(rope)

    # numeri SOPRA il filo (come in app: tessere → filo → numeri), con alone
    # di contrasto: chiaro su tessera accesa, scuro su spenta (NumeroCella)
    halo = Image.new("RGBA", canvas.size, (0, 0, 0, 0))
    hd = ImageDraw.Draw(halo)
    for i in range(25):
        cx, cy = centre(i)
        hcol = (0xFF, 0xF4, 0xD2, 235) if i in path else (0, 0, 0, 200)
        hd.text((cx, cy), str(vals[i]), fill=hcol, font=font, anchor="mm",
                stroke_width=4, stroke_fill=hcol)
    canvas.alpha_composite(halo.filter(ImageFilter.GaussianBlur(3)))
    d = ImageDraw.Draw(canvas)
    for i in range(25):
        cx, cy = centre(i)
        col = (0x1A, 0x14, 0x08) if i in path else (0xF2, 0xF5, 0xFB)
        d.text((cx, cy), str(vals[i]), fill=col, font=font, anchor="mm")
    canvas.convert("RGB").save(out, optimize=True)
    print(f"anteprima: {out}")


# ---------------------------------------------------------------- main

def main(argv: list[str]) -> None:
    args = [a for a in argv if not a.startswith("--")]
    kit = Path(args[0]) if args else Path("/home/claude/kit")
    prev = None
    if "--preview" in argv:
        i = argv.index("--preview")
        prev = Path(argv[i + 1]) if i + 1 < len(argv) else kit / "preview_board.png"
    src = lambda n: Image.open(kit / n).convert("RGBA")

    idle, lit = tile(src("filo_tile_idle.png")), tile(src("filo_tile_lit.png"))
    mi, ml = body_metrics(idle), body_metrics(lit)
    print(f"TileIdle corpo {mi}\nTileLit  corpo {ml}")
    assert abs(mi["w"] - ml["w"]) <= 1 and abs(mi["h"] - ml["h"]) <= 1, "corpi non combacianti"
    assert all(abs(a - b) <= 1 for a, b in zip(mi["bbox"], ml["bbox"])), "corpi non allineati"
    write_imageset("TileIdle", idle)
    write_imageset("TileLit", lit)

    write_imageset("BgVelluto", background(src("filo_bg_game.png")))
    write_imageset("LogoFilo", fit(crop_bbox(src("filo_logo.png")), LOGO_W))

    for nome, file in (("CardDaily", "filo_card_daily.png"), ("CardSalita", "filo_card_salita.png")):
        write_imageset(nome, fit(crop_bbox(src(file)), CARD_SIDE))

    icone = split_icons(src("filo_icons_sheet.png"))
    assert len(icone) == 3, f"attese 3 icone, trovate {len(icone)}"
    for nome, im in zip(("IconStar", "IconMedal", "IconHeart"), icone):
        write_imageset(nome, fit(im, ICON_MAX))

    totale = 0
    for d in sorted(ASSETS.glob("*.imageset")):
        for p in d.glob("*.png"):
            im = Image.open(p)
            totale += p.stat().st_size
            print(f"{p.relative_to(ASSETS)}: {im.size[0]}×{im.size[1]} {im.mode} {p.stat().st_size/1024:.0f} KB")
    print(f"TOTALE imageset: {totale/1024/1024:.2f} MB")
    if prev:
        preview(prev)


if __name__ == "__main__":
    main(sys.argv[1:])

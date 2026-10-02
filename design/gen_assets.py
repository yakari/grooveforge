#!/usr/bin/env python3
"""Generate every icon and splash asset from the backgrounds and a logo.

    python3 gen_assets.py [--logo svg|3d] [--out DIR] [--install]

Sources, all in this directory:
  grooveforge_icon_background.svg       rounded square + border
  grooveforge_icon_background_full.svg  full bleed, no rounding
  grooveforge_splash_portrait.svg       1440x2560, wordmark and slogan baked in
  grooveforge_splash_landscape.svg      2560x1440
  grooveforge_logo.svg  or  grooveforge_logo_3d.png   (--logo)

The two logo sources are NOT framed alike: the SVG sits inside a 1024 canvas
with margins, the 3D render is tight on the composition and carries a bloom
halo that reaches every corner. A raw alpha bounding box is therefore useless
on the 3D one. Both are cropped on an alpha THRESHOLD instead, then fitted
into the same target box — measured once from the SVG — so that switching
source does not move the logo.

What this writes is the set of MASTERS the Flutter tooling consumes, plus the
files that tooling does not produce (Linux hicolor set, maskable and Apple
touch icons, Play Store icon). After running it:

    dart run flutter_launcher_icons
    dart run flutter_native_splash:create

--install copies the masters to the paths pubspec.yaml already points at, and
the web files into web/. It overwrites; without it nothing outside --out is
touched.
"""
import argparse
import os
import shutil
import subprocess
from PIL import Image, ImageFilter

HERE = os.path.dirname(os.path.abspath(__file__))
PROJECT = os.path.dirname(HERE)

ICON_ROUNDED = "grooveforge_icon_background.svg"
ICON_FULL = "grooveforge_icon_background_full.svg"
SPLASH_PORTRAIT = "grooveforge_splash_portrait.svg"
SPLASH_LANDSCAPE = "grooveforge_splash_landscape.svg"
LOGO_SVG = "grooveforge_logo.svg"
LOGO_3D = "grooveforge_logo_3d.png"

# Alpha below this is halo, not artwork. Measured on both sources: the 3D
# render keeps a faint glow out to the image corners, so a plain getbbox()
# returns the whole canvas.
ART_THRESHOLD = 48

# Safe zones, given as the diameter of the guaranteed CIRCLE, as a fraction
# of the canvas. Fitting the artwork into a square of that size would push its
# corners outside the mask: a square of side d has a diagonal of 1.41 d. The
# artwork is therefore scaled so that its own diagonal fits the circle.
#   adaptive: Android masks a 108dp canvas down to a 66dp circle
#   maskable: the web spec guarantees only a circle of 80% diameter
#   macOS:    Apple's grid puts the artwork in 824 of 1024, with margins
ADAPTIVE_SAFE = 66 / 108
MASKABLE_SAFE = 0.80
MACOS_ART = 824 / 1024
# Android 12+ draws the splash icon itself: a 1152 px canvas of which only the
# central 768 survives the mask.
ANDROID12_CANVAS = 1152
ANDROID12_SAFE = 768 / 1152

LINUX_SIZES = (16, 24, 32, 48, 64, 128, 256, 512)
BACKDROP = (10, 24, 40)          # used only where alpha must be dropped

# ------------------------------------------------------------------ helpers


def render_svg(name, width, height=None, strip=()):
    """Rasterise an SVG with rsvg-convert, optionally dropping whole groups.

    `strip` names top-level group ids to remove before rasterising; that is
    how the splash background is produced without its wordmark, and the
    centre layer without its background.
    """
    path = os.path.join(HERE, name)
    if strip:
        source = open(path).read()
        for ident in strip:
            source = _cut_group(source, ident)
        path = os.path.join(TMP, "strip_%s_%s" % ("_".join(strip), name))
        open(path, "w").write(source)
    out = os.path.join(TMP, "render.png")
    cmd = ["rsvg-convert", "-w", str(width)]
    if height:
        cmd += ["-h", str(height)]
    subprocess.run(cmd + [path, "-o", out], check=True)
    return Image.open(out).convert("RGBA")


def _cut_group(source, ident):
    """Remove <g id="ident"> ... </g>, nesting included."""
    import re
    m = re.search(r'<g\b[^>]*\bid="%s"[^>]*>' % re.escape(ident), source)
    if not m:
        raise SystemExit("group not found: " + ident)
    i, depth = m.end(), 1
    while depth:
        nxt = re.search(r'<g\b|</g>', source[i:])
        depth += 1 if nxt.group() == '<g' else -1
        i += nxt.end()
    return source[:m.start()] + source[i:]


def crop_to_art(image, threshold=ART_THRESHOLD):
    mask = image.getchannel("A").point(lambda v: 255 if v >= threshold else 0)
    return image.crop(mask.getbbox())


def fit(art, width, height):
    """Scale to fit inside the box, preserving the aspect ratio."""
    k = min(width / art.width, height / art.height)
    return art.resize((max(1, round(art.width * k)),
                       max(1, round(art.height * k))), Image.LANCZOS)


def place(canvas, art, box):
    """Centre the artwork inside the box, scaled to contain."""
    x0, y0, x1, y1 = box
    piece = fit(art, x1 - x0, y1 - y0)
    canvas.alpha_composite(piece, (round(x0 + (x1 - x0 - piece.width) / 2),
                                   round(y0 + (y1 - y0 - piece.height) / 2)))
    return canvas


def centred_box(side, fraction):
    margin = side * (1 - fraction) / 2
    return (margin, margin, side - margin, side - margin)


def place_in_circle(canvas, art, diameter):
    """Centre the artwork so that its DIAGONAL fits the given circle.

    What every mask guarantees is a circle, not a square. Scaling the artwork
    to a square of the same size would leave its corners — here the anvil's
    horn and the keyboard's edges — outside the mask, to be cropped.
    """
    k = diameter / (art.width ** 2 + art.height ** 2) ** 0.5
    piece = art.resize((max(1, round(art.width * k)),
                        max(1, round(art.height * k))), Image.LANCZOS)
    canvas.alpha_composite(piece, (round((canvas.width - piece.width) / 2),
                                   round((canvas.height - piece.height) / 2)))
    return canvas


def flatten(image, colour=BACKDROP):
    """Drop the alpha channel; iOS and the Play Store both refuse it."""
    ground = Image.new("RGBA", image.size, colour + (255,))
    return Image.alpha_composite(ground, image).convert("RGB")


def save(image, *parts):
    path = os.path.join(OUT, *parts)
    os.makedirs(os.path.dirname(path), exist_ok=True)
    image.save(path)
    written.append(path)
    return path

# -------------------------------------------------------------------- logo


def logo_art(source):
    """The logo, cropped tight on its artwork, at a generous resolution."""
    if source == "svg":
        return crop_to_art(render_svg(LOGO_SVG, 2048, 2048))
    image = Image.open(os.path.join(HERE, LOGO_3D)).convert("RGBA")
    return crop_to_art(image)


def icon_art_box(side):
    """Where the logo sits on the icon canvas, measured on the SVG.

    Taken from the SVG rather than hard-coded: the backgrounds were authored
    around that exact position, and reading it back keeps the two in step if
    the drawing moves.
    """
    mask = render_svg(LOGO_SVG, side, side).getchannel("A")
    return mask.point(lambda v: 255 if v >= ART_THRESHOLD else 0).getbbox()

# ------------------------------------------------------------------- icons


def build_icons(art):
    side = 1024
    box = icon_art_box(side)

    rounded = place(render_svg(ICON_ROUNDED, side, side), art, box)
    save(flatten(rounded), "icons", "icon_master.png")

    full = place(render_svg(ICON_FULL, side, side), art, box)
    save(flatten(full), "icons", "icon_full_bleed.png")

    # Android adaptive: two separate layers, the foreground kept well inside
    # the circular mask.
    save(render_svg(ICON_FULL, side, side).convert("RGB"),
         "icons", "icon_adaptive_back.png")
    fore = Image.new("RGBA", (side, side), (0, 0, 0, 0))
    save(place_in_circle(fore, art, side * ADAPTIVE_SAFE),
         "icons", "icon_adaptive_fore.png")

    # Android 13 themed icons keep only the alpha, the system supplies the
    # colour. A flat silhouette of the whole logo is an unreadable blob, so
    # the alpha is weighted by luminance: the bright parts — the rim, the
    # wave, the keys — survive, the dark body drops out.
    mono = place_in_circle(Image.new("RGBA", (side, side), (0, 0, 0, 0)),
                           art, side * ADAPTIVE_SAFE)
    luminance = mono.convert("L").point(lambda v: min(255, int(v * 1.6)))
    shape = Image.new("RGBA", mono.size, (255, 255, 255, 0))
    shape.putalpha(Image.composite(luminance,
                                   Image.new("L", mono.size, 0),
                                   mono.getchannel("A").point(
                                       lambda v: 255 if v >= ART_THRESHOLD else 0)))
    save(shape, "icons", "icon_monochrome.png")

    maskable = place_in_circle(render_svg(ICON_FULL, side, side), art,
                               side * MASKABLE_SAFE)
    save(flatten(maskable), "icons", "icon_maskable.png")

    # macOS: the artwork does not reach the edges, and it casts a shadow.
    macos = Image.new("RGBA", (side, side), (0, 0, 0, 0))
    inner = round(side * MACOS_ART)
    shaped = rounded.resize((inner, inner), Image.LANCZOS)
    offset = (side - inner) // 2
    shadow = Image.new("RGBA", (side, side), (0, 0, 0, 0))
    shadow.paste(Image.new("RGBA", (inner, inner), (0, 0, 0, 90)),
                 (offset, offset + round(side * 0.012)),
                 shaped.getchannel("A"))
    macos.alpha_composite(shadow.filter(ImageFilter.GaussianBlur(side * 0.016)))
    macos.alpha_composite(shaped, (offset, offset))
    save(macos, "icons", "icon_macos.png")

    save(flatten(rounded).resize((512, 512), Image.LANCZOS),
         "icons", "icon_play_store.png")

    # --- web
    for size in (192, 512):
        save(flatten(rounded).resize((size, size), Image.LANCZOS),
             "web", "Icon-%d.png" % size)
        save(flatten(maskable).resize((size, size), Image.LANCZOS),
             "web", "Icon-maskable-%d.png" % size)
    save(flatten(rounded).resize((32, 32), Image.LANCZOS), "web", "favicon.png")
    save(flatten(rounded).resize((180, 180), Image.LANCZOS),
         "web", "apple-touch-icon.png")

    # --- Linux hicolor tree, which flutter_launcher_icons does not emit
    for size in LINUX_SIZES:
        save(rounded.resize((size, size), Image.LANCZOS),
             "linux", "hicolor", "%dx%d" % (size, size), "apps",
             "grooveforge.png")
    return rounded

# ----------------------------------------------------------------- splashes


def logo_slot(name):
    """Read the <rect id="logo-slot"> the background reserves for the logo."""
    import re
    source = open(os.path.join(HERE, name)).read()
    m = re.search(r'id="logo-slot" x="(\d+)" y="(\d+)"\s+width="(\d+)"', source)
    x, y, side = (int(m.group(i)) for i in (1, 2, 3))
    return (x, y, x + side, y + side)


def build_splashes(art):
    for name, tag, (w, h) in ((SPLASH_PORTRAIT, "portrait", (1440, 2560)),
                              (SPLASH_LANDSCAPE, "landscape", (2560, 1440))):
        box = logo_slot(name)
        save(flatten(place(render_svg(name, w, h), art, box)),
             "splash", "splash_%s.png" % tag)
        # Background alone: Android stretches this layer to fill, and a
        # gradient takes that without showing it. Text would not.
        save(flatten(render_svg(name, w, h, strip=("wordmark", "slogan"))),
             "splash", "splash_bg_%s.png" % tag)

    # Centre layer: logo, wordmark and slogan on transparency, cropped tight.
    # This is what goes in the layer a splash centres without distorting it.
    w, h = 2560, 1440
    centre = place(render_svg(SPLASH_LANDSCAPE, w, h, strip=("background",)),
                   art, logo_slot(SPLASH_LANDSCAPE))
    save(crop_to_art(centre, threshold=8), "splash", "splash_center.png")

    # Android 12+ draws its own splash icon; only the central third survives.
    canvas = Image.new("RGBA", (ANDROID12_CANVAS,) * 2, (0, 0, 0, 0))
    save(place_in_circle(canvas, art, ANDROID12_CANVAS * ANDROID12_SAFE),
         "splash", "splash_android12.png")

# ----------------------------------------------------------------- install


def install():
    """Copy the masters into the tracked folder the pubspec points at.

    design/assets/ is regenerable and git-ignored, so the files the Flutter
    tooling reads cannot live there: a fresh clone would not have them. They
    go to assets/branding/, which is tracked. The web icons go straight to
    web/, where the runner expects them.
    """
    branding = os.path.join(PROJECT, "assets", "branding")
    os.makedirs(branding, exist_ok=True)
    masters = [
        ("icons", "icon_master.png"), ("icons", "icon_full_bleed.png"),
        ("icons", "icon_adaptive_back.png"), ("icons", "icon_adaptive_fore.png"),
        ("icons", "icon_monochrome.png"), ("icons", "icon_macos.png"),
        ("icons", "icon_play_store.png"),
        ("splash", "splash_bg_portrait.png"), ("splash", "splash_center.png"),
        ("splash", "splash_android12.png"),
    ]
    for parts in masters:
        shutil.copy2(os.path.join(OUT, *parts), os.path.join(branding, parts[-1]))
        print("  installed: assets/branding/%s" % parts[-1])

    web = [("favicon.png", ("web", "favicon.png")),
           ("Icon-192.png", ("web", "icons", "Icon-192.png")),
           ("Icon-512.png", ("web", "icons", "Icon-512.png")),
           ("Icon-maskable-192.png", ("web", "icons", "Icon-maskable-192.png")),
           ("Icon-maskable-512.png", ("web", "icons", "Icon-maskable-512.png")),
           ("apple-touch-icon.png", ("web", "icons", "apple-touch-icon.png"))]
    for name, dst in web:
        d = os.path.join(PROJECT, *dst)
        os.makedirs(os.path.dirname(d), exist_ok=True)
        shutil.copy2(os.path.join(OUT, "web", name), d)
        print("  installed: %s" % "/".join(dst))


def main():
    global OUT, TMP, written
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--logo", choices=("svg", "3d"), default="svg")
    p.add_argument("--out", default=os.path.join(HERE, "assets"))
    p.add_argument("--install", action="store_true")
    args = p.parse_args()

    OUT = os.path.abspath(args.out)
    TMP = os.path.join(OUT, ".tmp")
    written = []
    os.makedirs(TMP, exist_ok=True)

    art = logo_art(args.logo)
    print("logo source: %s, artwork %dx%d" % (args.logo, art.width, art.height))
    build_icons(art)
    build_splashes(art)
    shutil.rmtree(TMP, ignore_errors=True)

    for path in written:
        size = Image.open(path).size
        print("  %-52s %sx%s" % (os.path.relpath(path, OUT), *size))
    print("%d files in %s" % (len(written), OUT))

    if args.install:
        print()
        install()
        print("\nNow run:\n  dart run flutter_launcher_icons"
              "\n  dart run flutter_native_splash:create")


if __name__ == "__main__":
    main()

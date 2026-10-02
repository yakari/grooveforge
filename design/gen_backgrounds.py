#!/usr/bin/env python3
"""Generate the SVG backgrounds the GrooveForge logo is laid over.

    python3 gen_backgrounds.py [--slogan "PLUGIN RACK • SCALES • REHEARSALS"]

Four files, all written next to this script:

  grooveforge_icon_background.svg       rounded square + border, 1024x1024
  grooveforge_icon_background_full.svg  the same, full bleed, no rounding
  grooveforge_splash_portrait.svg       1440x2560
  grooveforge_splash_landscape.svg      2560x1440

Why TWO icon backgrounds. The rounded square suits macOS, Windows, Linux and
the favicon: there, the rounding is part of the artwork. But iOS and Android
adaptive icons apply their OWN mask to a full square; handing them an
already-rounded shape yields a badge floating in an empty field. Hence the
full-bleed variant.

The rounded background keeps the exact colours and coordinates of
grooveforge_logo_icon.svg, so the logo lands pixel for pixel where it did.

Splash text is converted to paths: the SVGs therefore depend on no installed
font and render identically everywhere. The source font, Orbitron under the
OFL, stays in polices/ so the files can be regenerated after a slogan change.

Each splash carries an invisible <rect id="logo-slot">: that is the area
reserved for the logo, which the asset generation script reads to know where
to composite it.
"""
import argparse
import os
from fontTools.ttLib import TTFont
from fontTools.pens.svgPathPen import SVGPathPen
from fontTools.pens.transformPen import TransformPen
from fontTools.misc.transform import Transform

HERE = os.path.dirname(os.path.abspath(__file__))
FONT = os.path.join(HERE, "polices", "Orbitron-Bold.ttf")

DEFAULT_SLOGAN = "PLUGIN RACK • SCALES • REHEARSALS"
WORDMARK = "GROOVEFORGE"

# --- palette, taken from the logo ---------------------------------------
BG_CENTRE  = "#26323e"
BG_MID  = "#172836"
BG_EDGE    = "#0a1828"
BG_CORNER    = "#040c1a"
FORGE_WARM  = "#c2581f"
WORDMARK_TOP     = "#ffb469"
WORDMARK_BOTTOM      = "#d9712a"
SLOGAN_COLOUR = "#6ec9e0"

# ------------------------------------------------------------- typography

def _font():
    f = TTFont(FONT)
    return f, f["head"].unitsPerEm, f.getBestCmap(), f.getGlyphSet(), f["hmtx"]


def text_width(text, size, tracking=0.0):
    """Rendered width, in user units."""
    _, upem, cmap, _, hmtx = _font()
    scale = size / upem
    total = 0.0
    for channel in text:
        name = cmap.get(ord(channel))
        total += (hmtx[name][0] * scale if name else size * 0.5) + tracking
    return total - tracking if text else 0.0


def size_for_width(text, target_width, tracking_em=0.0):
    """Point size that makes the text exactly this wide.

    The size is computed rather than guessed: "GROOVEFORGE" set in Orbitron
    runs over eight ems wide, and a size picked by eye overflows the canvas
    in portrait.
    """
    reference_size = 1000.0
    measured = text_width(text, reference_size, reference_size * tracking_em)
    return target_width * reference_size / measured


def text_to_path(text, size, tracking=0.0):
    """Turn a string into a single SVG path, baseline at y=0.

    Font outlines grow towards positive y, SVG grows downwards: the transform
    therefore flips the Y axis. The resulting path no longer depends on any
    installed font.
    """
    _, upem, cmap, glyphs, hmtx = _font()
    scale = size / upem
    pen = SVGPathPen(glyphs)
    x = 0.0
    for channel in text:
        name = cmap.get(ord(channel))
        if name is None:
            x += size * 0.5
            continue
        glyphs[name].draw(TransformPen(pen, Transform(scale, 0, 0, -scale, x, 0)))
        x += hmtx[name][0] * scale + tracking
    return pen.getCommands()


def cap_height(size):
    f, upem, _, _, _ = _font()
    os2 = f["OS/2"]
    raw = getattr(os2, "sCapHeight", None) or upem * 0.7
    return raw * size / upem

# --------------------------------------------------------- backgrounds

def _background_gradients(width, height, prefix):
    """The logo's two glows: a cold one above, the forge below.

    In userSpaceOnUse rather than bounding-box fractions: these backgrounds
    are meant to be stretched or cropped, and absolute coordinates stay
    readable when that happens.
    """
    return f'''    <radialGradient id="{prefix}Ground" gradientUnits="userSpaceOnUse"
       cx="{width * 0.5:.0f}" cy="{height * 0.38:.0f}" r="{max(width, height) * 0.78:.0f}">
      <stop offset="0" stop-color="{BG_CENTRE}" />
      <stop offset="0.34" stop-color="{BG_MID}" />
      <stop offset="0.66" stop-color="{BG_EDGE}" />
      <stop offset="1" stop-color="{BG_CORNER}" />
    </radialGradient>
    <radialGradient id="{prefix}Forge" gradientUnits="userSpaceOnUse"
       cx="{width * 0.5:.0f}" cy="{height * 0.60:.0f}" r="{max(width, height) * 0.46:.0f}">
      <stop offset="0" stop-color="{FORGE_WARM}" stop-opacity="0.42" />
      <stop offset="0.5" stop-color="#8e3b16" stop-opacity="0.2" />
      <stop offset="1" stop-color="#8e3b16" stop-opacity="0" />
    </radialGradient>'''


def rounded_icon():
    """The icon background exactly as it is in grooveforge_logo_icon.svg.

    Coordinates untouched — 816x826 from (104,104), border at 107.5 — so the
    logo lands in exactly the same place as before.
    """
    return '''<?xml version="1.0" encoding="UTF-8" standalone="no"?>
<svg xmlns="http://www.w3.org/2000/svg" width="1024" height="1024"
     viewBox="0 0 1024 1024" version="1.1" id="grooveforge-icon-background">
  <title>GrooveForge - icon background, rounded square</title>
  <defs>
    <radialGradient id="gGround" cx="0.5" cy="0.30" r="0.80">
      <stop offset="0" stop-color="#26323e" />
      <stop offset="0.34" stop-color="#172836" />
      <stop offset="0.66" stop-color="#0a1828" />
      <stop offset="1" stop-color="#040c1a" />
    </radialGradient>
    <radialGradient id="gForge" cx="0.46" cy="0.56" r="0.46">
      <stop offset="0" stop-color="#c2581f" stop-opacity="0.42" />
      <stop offset="0.5" stop-color="#8e3b16" stop-opacity="0.2" />
      <stop offset="1" stop-color="#8e3b16" stop-opacity="0" />
    </radialGradient>
    <linearGradient id="gFrame" x1="0.12" y1="0" x2="0.88" y2="1">
      <stop offset="0" stop-color="#7cc6dc" />
      <stop offset="0.18" stop-color="#2a4d60" />
      <stop offset="0.44" stop-color="#39383f" />
      <stop offset="0.66" stop-color="#6b4336" />
      <stop offset="0.84" stop-color="#8e3d28" />
      <stop offset="1" stop-color="#c08457" />
    </linearGradient>
  </defs>
  <g id="background">
    <rect x="104" y="104" width="816" height="826" rx="186" fill="url(#gGround)" />
    <rect x="104" y="104" width="816" height="826" rx="186" fill="url(#gForge)" />
  </g>
  <g id="border">
    <rect x="107.5" y="107.5" width="809" height="819" rx="182.5"
          fill="none" stroke="url(#gFrame)" stroke-width="9" stroke-linejoin="round" />
  </g>
</svg>
'''


def full_bleed_icon():
    """The same background, covering the whole square, with no border.

    iOS and Android adaptive icons apply their own mask: giving them a drawn
    rounding would produce a badge sitting in an empty square.
    """
    return '''<?xml version="1.0" encoding="UTF-8" standalone="no"?>
<svg xmlns="http://www.w3.org/2000/svg" width="1024" height="1024"
     viewBox="0 0 1024 1024" version="1.1" id="grooveforge-icon-background-full">
  <title>GrooveForge - full-bleed icon background (iOS, Android adaptive)</title>
  <defs>
    <radialGradient id="gGround" cx="0.5" cy="0.34" r="0.86">
      <stop offset="0" stop-color="#26323e" />
      <stop offset="0.34" stop-color="#172836" />
      <stop offset="0.66" stop-color="#0a1828" />
      <stop offset="1" stop-color="#040c1a" />
    </radialGradient>
    <radialGradient id="gForge" cx="0.46" cy="0.58" r="0.52">
      <stop offset="0" stop-color="#c2581f" stop-opacity="0.42" />
      <stop offset="0.5" stop-color="#8e3b16" stop-opacity="0.2" />
      <stop offset="1" stop-color="#8e3b16" stop-opacity="0" />
    </radialGradient>
  </defs>
  <rect width="1024" height="1024" fill="url(#gGround)" />
  <rect width="1024" height="1024" fill="url(#gForge)" />
</svg>
'''


def splash(width, height, slogan, name):
    """Full-bleed splash background; logo and text placed by proportion.

    The layout follows the original splash: logo in the upper two thirds,
    name below it, slogan under the name. Everything is expressed as a
    fraction of the canvas so both orientations stay siblings.
    """
    landscape = width > height
    logo_side = (height * 0.57) if landscape else (width * 0.63)
    logo_cy = height * (0.39 if landscape else 0.43)
    logo_x = (width - logo_side) / 2
    logo_y = logo_cy - logo_side / 2

    wordmark_size = size_for_width(WORDMARK, width * (0.42 if landscape else 0.80))
    slogan_tracking = 0.09
    slogan_size = size_for_width(
        slogan, width * (0.36 if landscape else 0.72), slogan_tracking)

    wordmark_base = logo_y + logo_side + height * (0.115 if landscape else 0.075)
    slogan_base = wordmark_base + height * (0.055 if landscape else 0.035)

    wordmark_width = text_width(WORDMARK, wordmark_size)
    slogan_width = text_width(slogan, slogan_size, slogan_size * slogan_tracking)
    wordmark_path = text_to_path(WORDMARK, wordmark_size)
    slogan_path = text_to_path(slogan, slogan_size, slogan_size * slogan_tracking)

    return f'''<?xml version="1.0" encoding="UTF-8" standalone="no"?>
<svg xmlns="http://www.w3.org/2000/svg" width="{width}" height="{height}"
     viewBox="0 0 {width} {height}" version="1.1" id="{name}">
  <title>GrooveForge - splash background, {'landscape' if landscape else 'portrait'}</title>
  <defs>
{_background_gradients(width, height, 'g')}
    <linearGradient id="gWordmark" gradientUnits="userSpaceOnUse"
       x1="0" y1="{wordmark_base - cap_height(wordmark_size):.0f}" x2="0" y2="{wordmark_base:.0f}">
      <stop offset="0" stop-color="{WORDMARK_TOP}" />
      <stop offset="1" stop-color="{WORDMARK_BOTTOM}" />
    </linearGradient>
    <filter id="fWordmarkGlow" x="-20%" y="-60%" width="140%" height="220%">
      <feGaussianBlur stdDeviation="{wordmark_size * 0.12:.1f}" />
    </filter>
  </defs>

  <g id="background">
    <rect width="{width}" height="{height}" fill="url(#gGround)" />
    <rect width="{width}" height="{height}" fill="url(#gForge)" />
  </g>

  <rect id="logo-slot" x="{logo_x:.0f}" y="{logo_y:.0f}"
        width="{logo_side:.0f}" height="{logo_side:.0f}" fill="none" />

  <g id="wordmark" transform="translate({(width - wordmark_width) / 2:.1f} {wordmark_base:.1f})">
    <path d="{wordmark_path}" fill="{WORDMARK_BOTTOM}" opacity="0.55" filter="url(#fWordmarkGlow)" />
    <path d="{wordmark_path}" fill="url(#gWordmark)" />
  </g>

  <g id="slogan" transform="translate({(width - slogan_width) / 2:.1f} {slogan_base:.1f})">
    <path d="{slogan_path}" fill="{SLOGAN_COLOUR}" />
  </g>
</svg>
'''


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--slogan", default=DEFAULT_SLOGAN)
    args = p.parse_args()

    outputs = {
        "grooveforge_icon_background.svg": rounded_icon(),
        "grooveforge_icon_background_full.svg": full_bleed_icon(),
        "grooveforge_splash_portrait.svg":
            splash(1440, 2560, args.slogan, "grooveforge-splash-portrait"),
        "grooveforge_splash_landscape.svg":
            splash(2560, 1440, args.slogan, "grooveforge-splash-landscape"),
    }
    for name, content in outputs.items():
        path = os.path.join(HERE, name)
        with open(path, "w") as f:
            f.write(content)
        print("written: %-40s %6d bytes" % (name, len(content)))


if __name__ == "__main__":
    main()

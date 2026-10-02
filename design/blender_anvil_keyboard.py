"""GrooveForge logo modelled in 3D, in the exact composition of the icon.

    blender -b --factory-startup --python blender_logo_3d.py -- \
            [--out render.png] [--blend project.blend] [--samples 128]

The difference with blender_scene3d.py (which merely gave thickness to the
SVG silhouettes): here the anvil and the keyboard are real volumes, modelled
piece by piece. Only the wave stays an SVG curve, because its front-on shape
is precisely what we want to keep.

What comes from the SVG is the FRAMING: every element occupies exactly the
place, size and orientation it has in grooveforge_logo.svg. Seen head-on
through Camera_logo (orthographic), the icon's composition comes back; turn
around it and you see a real anvil and a real keyboard.

Conventions
-----------
The icon plane is XZ, the viewer sits at -Y.
  X(px), Z(px)  turn an SVG coordinate into a scene coordinate
  L(px)         turns a length
Y is depth: it does not exist in the SVG, it is the part we invent. It
decreases towards the viewer (anvil at the back, wave in front).
"""
import bpy, bmesh, math, re, sys
from mathutils import Vector, Matrix

argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
def opt(n, d): return argv[argv.index(n) + 1] if n in argv else d
SVG     = opt("--svg", "/home/yann/dev/grooveforge/grooveforge/design/"
                       "grooveforge_logo.svg")
OUT     = opt("--out",   "/tmp/gf3d.png")
BLEND   = opt("--blend", "/tmp/gf3d.blend")
SAMPLES = int(opt("--samples", "128"))

PX = 2.0 / 1024                      # 1 SVG unit -> scene metres
def X(px):  return (px - 512) * PX   # SVG abscissa -> scene X
def Z(py):  return (512 - py) * PX   # SVG ordinate (downwards) -> scene Z
def L(px):  return px * PX           # a length

# -------------------------------------------------------------- depths
# All in SVG units, converted by L(). Y decreases towards the viewer.
BLOCK_HALF     = 96      # the block the anvil stands on
CASE_BACK    = -90     # back face of the keyboard case
CASE_FRONT     = -190    # front face (the control panel)
KEYBED_RECESS        = 14      # key bed recess below the panel
KEY_FRONT      = -216    # white keys stand proud of the panel
BLACK_KEY_FRONT   = -232
WHEEL_AXIS       = -167    # wheel axis, set back from the panel
WHEEL_RADIUS     = 46
KNOB_FRONT      = -220
WAVE_Y         = -290    # the molten ribbon, in the foreground
WAVE_DEPTH        = 55

# ------------------------------------------- dimensions taken from the SVG
# The anvil is not dimensioned by hand: its silhouette is the SVG's 'anvil'
# path. What we add is the thickness — invisible head-on.
#
# Body thickness profile: (SVG y, half-thickness). It reads as a forge anvil:
# thick face, pinched waist, flared foot.
ANVIL_PROFILE = [(548, 72), (505, 62), (455, 38), (400, 28),
                  (340, 38), (302, 46), (238, 46)]
ANVIL_BODY_X = (380, 880)     # x=380 is the step in the path: the body
                                 # must start there and not before, or it
                                 # overhangs the horn like a ledge
# The horn is a real cone: measured on the path, it goes from 98 px tall at
# its root to 20 px at the tip.
HORN_BASE   = (400, 50, 314)    # x, radius, y of the centre
HORN_FLATTEN = 0.85              # elliptical section: the horn must fit
                                 # within the body's thickness, or its root
                                 # bulges out past the flanks
HORN_TIP = (220, 7, 274)
HARDY   = (688, 724, 36)        # square hardy hole in the heel: x0, x1, side
PRITCHEL = (748, 9)              # pritchel hole: x, radius
TABLE    = (380, 778, 246, 268)  # the polished face, on top

# Keyboard
# Keyboard
CASE   = (203, 821, 513, 793)     # x0, x1, y0, y1
CASE_RADIUS = 46                   # rx of the SVG rect: the case must
                                     # follow the rim, otherwise its sharp
                                     # corners stick out past the border
KEYBED       = (326, 794, 604, 780)     # the key bed
SHOULDER    = 714                      # where the black keys stop
KEY_Y  = (610, 772)               # start and end of the white keys
WHITE_KEYS  = 10
BLACK_KEY_WIDTH = 26
# A real keyboard: the black keys are not evenly spaced, they follow the 2-3
# pattern. Over ten white keys (C D E F G A B C D E) there are seven of them.
BLACK_BETWEEN = (0, 1, 3, 4, 5, 7, 8)
KNOBS   = ((239, 560), (291, 560), (727, 561), (775, 561))
WHEELS     = ((227, 255, 646, 734), (276, 304, 646, 734))   # x0, x1, y0, y1
# (x, y, width, height, material): a powered device never has every LED lit
# at once, and that is what makes it believable
LEDS    = ((228, 604, 26, 11, "diode"),           # power, amber
             (277, 604, 26, 11, "diode_eteinte"),
             (231, 748, 18,  9, "diode_froide"),    # MIDI activity, cyan
             (280, 748, 18,  9, "diode_eteinte"))

# ------------------------------------------------------------------ tools

def collection(name):
    channel = bpy.data.collections.get(name)
    if channel is None:
        channel = bpy.data.collections.new(name)
        bpy.context.scene.collection.children.link(channel)
    return channel


def put_in_collection(obj, name):
    for channel in list(obj.users_collection):
        channel.objects.unlink(obj)
    collection(name).objects.link(obj)
    return obj


def make_object(name, bm, coll, material=None):
    """Turn a bmesh into an object filed in its collection."""
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me); bm.free()
    ob = bpy.data.objects.new(name, me)
    if material:
        me.materials.append(material)
    return put_in_collection(ob, coll)


def bevel(ob, width, segments=3, angle=50):
    """A real object has no sharp edge: everything carries a bevel."""
    m = ob.modifiers.new("Bevel", 'BEVEL')
    m.width = width
    m.segments = segments
    m.limit_method = 'ANGLE'
    m.angle_limit = math.radians(angle)
    m.harden_normals = True
    return m


def drill(ob, cutter):
    m = ob.modifiers.new("Drill " + cutter.name, 'BOOLEAN')
    m.operation = 'DIFFERENCE'
    m.object = cutter
    m.solver = 'EXACT'
    cutter.display_type = 'WIRE'
    cutter.hide_render = True
    return m


def box(bm, x0, x1, y0, y1, z0, z1):
    bmesh.ops.create_cube(
        bm, size=1.0,
        matrix=Matrix.Translation(((x0 + x1) / 2, (y0 + y1) / 2, (z0 + z1) / 2))
               @ Matrix.Diagonal((x1 - x0, y1 - y0, z1 - z0, 1.0)))


def frustum(bm, bottom, top):
    """Frustum between two horizontal rectangles.

    `bas` and `haut` are (x0, x1, y0, y1, z); used for the anvil's body and
    foot, which flare out.
    """
    def corners(r):
        x0, x1, y0, y1, z = r
        return [(x0, y0, z), (x1, y0, z), (x1, y1, z), (x0, y1, z)]
    v_bottom = [bm.verts.new(p) for p in corners(bottom)]
    v_top = [bm.verts.new(p) for p in corners(top)]
    for i in range(4):
        j = (i + 1) % 4
        bm.faces.new((v_bottom[i], v_bottom[j], v_top[j], v_top[i]))
    bm.faces.new(v_bottom[::-1])
    bm.faces.new(v_top)


def rounded_rect(x0, x1, y0, y1, r, per_corner=10):
    """Outline of a rounded rectangle, in SVG units (y downwards)."""
    corners = (((x1 - r, y0 + r), -90), ((x1 - r, y1 - r),   0),
             ((x0 + r, y1 - r),  90), ((x0 + r, y0 + r), 180))
    pts = []
    for (cx, cy), start in corners:
        for i in range(per_corner + 1):
            a = math.radians(start + 90.0 * i / per_corner)
            pts.append((cx + math.cos(a) * r, cy + math.sin(a) * r))
    return pts


def cylinder(bm, centre, radius, length, axis='Y', segments=48, radius2=None):
    rot = {'X': Matrix.Rotation(math.radians(90), 4, 'Y'),
           'Y': Matrix.Rotation(math.radians(-90), 4, 'X'),
           'Z': Matrix.Identity(4)}[axis]
    bmesh.ops.create_cone(
        bm, cap_ends=True, cap_tris=False, segments=segments,
        radius1=radius, radius2=radius if radius2 is None else radius2,
        depth=length,
        matrix=Matrix.Translation(centre) @ rot)


def extrude_polygon(bm, contour, y0, y1):
    """Extrude a contour given in the XZ plane between two depths.

    White keys are T-shaped (full width at the front, narrowed where the
    black keys pass): extruding one contour avoids the internal faces that
    gluing two boxes together would leave.
    """
    front = [bm.verts.new((x, y0, z)) for x, z in contour]
    back = [bm.verts.new((x, y1, z)) for x, z in contour]
    n = len(contour)
    for i in range(n):
        j = (i + 1) % n
        bm.faces.new((front[i], front[j], back[j], back[i]))
    bm.faces.new(front[::-1])
    bm.faces.new(back)

# -------------------------------------------------------------- materials

def material(name, base, metallic=0.0, rough=0.5, emission=None, force=0.0):
    """Plain material, no texture: for parts too small to show one."""
    m = bpy.data.materials.new(name)
    if not m.node_tree:
        m.use_nodes = True
    b = m.node_tree.nodes.get("Principled BSDF")
    set_input(b, "Base Color", base)
    set_input(b, "Metallic", metallic)
    set_input(b, "Roughness", rough)
    if emission is not None:
        set_input(b, "Emission Color", emission)
        set_input(b, "Emission Strength", force)
    return m


def set_input(node, socket, value):
    """Set a value on an input if that input exists.

    Principled BSDF input names move from one Blender version to the next
    ("Specular" became "Specular IOR Level"): the ones that have gone are
    skipped silently rather than crashing the build.
    """
    if socket in node.inputs:
        node.inputs[socket].default_value = value


def _new_material(name):
    """Fresh material, with its BSDF and object coordinates at scale 1.

    OBJECT coordinates and not "generated" ones: generated coordinates are
    normalised over the bounding box, so the grain would change size from one
    key to the next. In object coordinates it keeps the same fineness
    everywhere.
    """
    m = bpy.data.materials.new(name)
    if not m.node_tree:
        m.use_nodes = True
    nt = m.node_tree
    b = nt.nodes.get("Principled BSDF")
    coord = nt.nodes.new('ShaderNodeTexCoord')
    coord.location = (-1100, 0)
    return m, nt, b, coord.outputs['Object']


def _noise(nt, vector, scale, detail=6.0, roughness=0.5, y=0):
    n = nt.nodes.new('ShaderNodeTexNoise')
    n.location = (-900, y)
    n.inputs['Scale'].default_value = scale
    n.inputs['Detail'].default_value = detail
    n.inputs['Roughness'].default_value = roughness
    nt.links.new(vector, n.inputs['Vector'])
    return n


def _bump(nt, height, force, distance, normal=None, y=0):
    b = nt.nodes.new('ShaderNodeBump')
    b.location = (-400, y)
    b.inputs['Strength'].default_value = force
    b.inputs['Distance'].default_value = distance
    nt.links.new(height, b.inputs['Height'])
    if normal is not None:
        nt.links.new(normal, b.inputs['Normal'])
    return b.outputs['Normal']


# Gradients lifted straight from the SVG, with their axes in SVG units.
# They are what gives the logo its two-tone reading: cold on the left, forge
# on the right. Carrying them over to 3D beats reinventing them.
G_NEON      = ((0.00, '#a7fdfc'), (0.30, '#d8f6e8'), (0.50, '#fcebb7'),
               (0.76, '#ffe99d'), (1.00, '#fff2ac'))
G_NEON_SOFT = ((0.00, '#45c8e8'), (0.36, '#9fd9df'), (0.62, '#f0b25a'),
               (1.00, '#e2701c'))
G_RIBBON     = ((0.00, '#5a4a48'), (0.26, '#6b4238'), (0.52, '#8a4229'),
               (0.78, '#c05f22'), (1.00, '#e78230'))
# Emission does not follow the colour ramp: pushed to white, an orange turns
# pink. This one climbs towards amber, like the heart of the wave in the
# original icon (hue 53 degrees, not 0).
G_EMBER    = ((0.00, '#1d0f08'), (0.45, '#7d3310'), (0.78, '#dd6414'),
               (1.00, '#ffb347'))
AXIS_NEON    = ((300, 0), (700, 0))            # across the wave's span
AXIS_SOFT    = ((203, 0), (821, 0))            # across the keyboard's span
AXIS_RIBBON   = ((330, 430), (614.4, 559.2))    # slanted, as in the SVG


def _linear(hex_colour):
    """#rrggbb sRGB -> linear RGBA, the space Cycles works in."""
    def channel(v):
        v /= 255.0
        return v / 12.92 if v <= 0.04045 else ((v + 0.055) / 1.055) ** 2.4
    return tuple(channel(int(hex_colour[i:i + 2], 16)) for i in (1, 3, 5)) + (1.0,)


def _gradient(nt, vec, axis, stops, y=0):
    """Colour ramp projected onto an arbitrary axis of the image plane.

    Rather than rotating a Mapping node, the projection is a dot product:
    t = (p - A)·(B-A)/|B-A|², which is 0 at A and 1 at B. The axis can
    therefore be slanted — the ribbon's is — with no angle arithmetic at all.

    WORLD position is used, not object coordinates: the axis is given in
    scene coordinates, whereas the keyboard rim is a curve imported from the
    SVG, with its own scale and its own translation. In object coordinates
    its gradient would land somewhere else entirely.
    """
    geo = nt.nodes.new('ShaderNodeNewGeometry')
    geo.location = (-1100, y - 200)
    vec = geo.outputs['Position']
    (ax, ay), (bx, by) = axis
    a = (X(ax), 0.0, Z(ay))
    d = (X(bx) - a[0], 0.0, Z(by) - a[2])
    n2 = d[0] ** 2 + d[2] ** 2

    subtract = nt.nodes.new('ShaderNodeVectorMath'); subtract.operation = 'SUBTRACT'
    subtract.location = (-900, y)
    subtract.inputs[1].default_value = a
    nt.links.new(vec, subtract.inputs[0])

    dot = nt.nodes.new('ShaderNodeVectorMath'); dot.operation = 'DOT_PRODUCT'
    dot.location = (-720, y)
    dot.inputs[1].default_value = (d[0] / n2, 0.0, d[2] / n2)
    nt.links.new(subtract.outputs['Vector'], dot.inputs[0])

    ramp = nt.nodes.new('ShaderNodeValToRGB')
    ramp.location = (-540, y)
    nt.links.new(dot.outputs['Value'], ramp.inputs['Fac'])
    cr = ramp.color_ramp
    while len(cr.elements) > 1:
        cr.elements.remove(cr.elements[-1])
    for i, (pos, hex_colour) in enumerate(stops):
        el = cr.elements[0] if i == 0 else cr.elements.new(pos)
        el.position = pos
        el.color = _linear(hex_colour)
    return ramp


def gradient_metal(name, axis, stops, force_min, force_max,
                  metal=0.5, rough_min=0.22, rough_max=0.40, emission_stops=None):
    """Metal tinted by a gradient, glowing at the hot end.

    Two ramps on the same axis: one drives the colour, the other the emission
    strength. That is what makes the wave a dull aluminium ribbon at one end
    and molten metal at the other, instead of one flat tint.
    """
    m, nt, b, vec = _new_material(name)
    set_input(b, "Metallic", metal)
    colour = _gradient(nt, vec, axis, stops)
    nt.links.new(colour.outputs['Color'], b.inputs['Base Color'])
    emitted = colour if emission_stops is None else \
        _gradient(nt, vec, axis, emission_stops, y=-220)
    nt.links.new(emitted.outputs['Color'], b.inputs['Emission Color'])

    heat = _gradient(nt, vec, axis,
                       ((0.0, '#000000'), (0.45, '#3a3a3a'), (1.0, '#ffffff')),
                       y=-420)
    multiply = nt.nodes.new('ShaderNodeMath'); multiply.operation = 'MULTIPLY'
    multiply.location = (-320, -420)
    multiply.inputs[1].default_value = force_max - force_min
    nt.links.new(heat.outputs['Color'], multiply.inputs[0])
    add = nt.nodes.new('ShaderNodeMath'); add.operation = 'ADD'
    add.location = (-160, -420)
    add.inputs[1].default_value = force_min
    nt.links.new(multiply.outputs['Value'], add.inputs[0])
    nt.links.new(add.outputs['Value'], b.inputs['Emission Strength'])

    # brushed grain: roughness varies, so the highlight travels along the ribbon
    polish = _noise(nt, vec, 70.0, detail=6.0, y=-820)
    ramp = nt.nodes.new('ShaderNodeValToRGB')
    ramp.location = (-540, -820)
    ramp.color_ramp.elements[0].color = (rough_min,) * 3 + (1,)
    ramp.color_ramp.elements[1].color = (rough_max,) * 3 + (1,)
    nt.links.new(polish.outputs['Fac'], ramp.inputs['Fac'])
    nt.links.new(ramp.outputs['Color'], b.inputs['Roughness'])
    return m


def raw_metal(name, base, rough_min, rough_max, hammering=0.5):
    """Forge metal: matte overall, but glossy in places.

    What makes it read as "raw" is not the colour but the uneven polish: a
    noise texture drives the roughness, so the sheen moves across the piece
    instead of being uniform. Two reliefs are layered: the broad hollows of
    hammering and the fine grain of cast iron.
    """
    m, nt, b, vec = _new_material(name)
    set_input(b, "Base Color", base)
    set_input(b, "Metallic", 1.0)

    polish = _noise(nt, vec, 42.0, detail=8.0, roughness=0.58)
    ramp = nt.nodes.new('ShaderNodeValToRGB')
    ramp.location = (-650, 0)
    ramp.color_ramp.elements[0].position = 0.34
    ramp.color_ramp.elements[0].color = (rough_min, rough_min, rough_min, 1)
    ramp.color_ramp.elements[1].position = 0.68
    ramp.color_ramp.elements[1].color = (rough_max, rough_max, rough_max, 1)
    nt.links.new(polish.outputs['Fac'], ramp.inputs['Fac'])
    nt.links.new(ramp.outputs['Color'], b.inputs['Roughness'])

    hollow = _noise(nt, vec, 22.0, detail=4.0, y=-300)
    grain = _noise(nt, vec, 190.0, detail=5.0, y=-600)
    normal = _bump(nt, hollow.outputs['Fac'], hammering, 0.006, y=-300)
    nt.links.new(_bump(nt, grain.outputs['Fac'], 0.25, 0.0012, normal, y=-600),
                 b.inputs['Normal'])
    return m


def plastic(name, base, roughness=0.44, grain=0.14, scale=420.0, specular=0.38):
    """Good-hardware plastic: dark, grainy, barely glossy.

    The shell of a high-end controller reflects nothing — hence a
    deliberately low specular level — but it is not matte either: the fine
    grain catches light in thousands of tiny points. A Voronoi cell, closer
    to moulded soft-touch than a noise, is what gives that stipple.
    """
    m, nt, b, vec = _new_material(name)
    set_input(b, "Base Color", base)
    set_input(b, "Metallic", 0.0)
    set_input(b, "Specular IOR Level", specular)

    variation = _noise(nt, vec, 24.0, detail=3.0)
    ramp = nt.nodes.new('ShaderNodeValToRGB')
    ramp.location = (-650, 0)
    ramp.color_ramp.elements[0].color = (roughness - 0.05,) * 3 + (1,)
    ramp.color_ramp.elements[1].color = (roughness + 0.05,) * 3 + (1,)
    nt.links.new(variation.outputs['Fac'], ramp.inputs['Fac'])
    nt.links.new(ramp.outputs['Color'], b.inputs['Roughness'])

    stipple = nt.nodes.new('ShaderNodeTexVoronoi')
    stipple.location = (-900, -300)
    stipple.inputs['Scale'].default_value = scale
    nt.links.new(vec, stipple.inputs['Vector'])
    nt.links.new(_bump(nt, stipple.outputs['Distance'], grain, 0.0008, y=-300),
                 b.inputs['Normal'])
    return m


def palette():
    return {
        # --- the anvil: raw metal, matte but glossy in patches
        "fonte":    raw_metal("Cast iron",        (0.026, 0.034, 0.048, 1), 0.27, 0.43),
        "table":    raw_metal("Forged face", (0.17, 0.22, 0.27, 1),    0.12, 0.26,
                               hammering=0.30),
        "billot":   material("Block",         (0.035, 0.028, 0.022, 1), 0.2, 0.72),
        # --- the keyboard: grained plastic, non-reflective
        "boitier":  plastic("Case",       (0.024, 0.040, 0.064, 1)),
        "cuvette":  plastic("Key bed",(0.012, 0.022, 0.038, 1), 0.56, 0.10),
        "blanche":  plastic("White key",(0.40, 0.46, 0.48, 1), 0.33, 0.07,
                              scale=620.0, specular=0.45),
        "noire":    plastic("Black key",  (0.009, 0.016, 0.028, 1), 0.28, 0.07,
                              scale=620.0, specular=0.45),
        "caoutchouc": plastic("Rubber",  (0.020, 0.030, 0.045, 1), 0.60, 0.22,
                                scale=300.0, specular=0.25),
        "bouton":   plastic("Knob",        (0.045, 0.072, 0.105, 1), 0.36, 0.16,
                              scale=520.0),
        "lunette":  material("Bezel",        (0.10, 0.15, 0.20, 1),   0.8, 0.26),
        "repere":   material("Marker",         (0.80, 0.90, 1.0, 1),    0.0, 0.25,
                             emission=(0.55, 0.85, 1.0, 1), force=2.2),
        # --- the LEDs: some lit, the others at rest
        "diode":    material("LED amber",    (0.85, 0.40, 0.12, 1),   0.0, 0.40,
                             emission=(1.0, 0.44, 0.08, 1), force=3.2),
        "diode_froide": material("LED cyan", (0.20, 0.70, 0.95, 1),   0.0, 0.40,
                                 emission=(0.06, 0.52, 1.0, 1), force=2.8),
        "diode_eteinte": material("LED off", (0.040, 0.050, 0.060, 1),
                                  0.0, 0.34),
        # --- the logo's gradients, carried over from the SVG
        "neon":     gradient_metal("Keyboard rim", AXIS_SOFT, G_NEON_SOFT,
                                  0.9, 1.9, metal=0.2, rough_min=0.18, rough_max=0.30),
        "braise":   gradient_metal("Wave ribbon", AXIS_RIBBON, G_RIBBON,
                                  0.06, 1.20, metal=0.30,
                                  emission_stops=G_EMBER),
        "bord_onde":gradient_metal("Wave edge", AXIS_NEON, G_NEON,
                                  1.0, 2.2, metal=0.35, rough_min=0.16, rough_max=0.28),
    }


def svg_contour(ident, step=5.0):
    """Sample a closed SVG path into a polygon, in SVG units.

    Only the silhouette is taken from the SVG: that is what makes the 3D
    overlay the logo. The thickness is sculpted afterwards.
    """
    import xml.etree.ElementTree as ET
    d = ET.parse(SVG).getroot().find(".//*[@id='%s']" % ident).get('d')
    tokens = re.findall(r'[A-Za-z]|-?\d*\.?\d+(?:[eE]-?\d+)?', d)
    pts, i, cursor, start = [], 0, (0.0, 0.0), (0.0, 0.0)

    def cubic(p0, p1, p2, p3):
        # as many segments as needed to keep each chord under 'pas'
        approx = (abs(p3[0] - p0[0]) + abs(p3[1] - p0[1])
                  + abs(p1[0] - p0[0]) + abs(p1[1] - p0[1]))
        n = max(2, int(approx / step))
        for k in range(1, n + 1):
            t = k / n
            u = 1 - t
            yield (u*u*u*p0[0] + 3*u*u*t*p1[0] + 3*u*t*t*p2[0] + t*t*t*p3[0],
                   u*u*u*p0[1] + 3*u*u*t*p1[1] + 3*u*t*t*p2[1] + t*t*t*p3[1])

    # Inkscape writes absolute (M, C) and relative (m, c) interchangeably:
    # confusing the two yields an entirely wrong path, and raises nothing.
    while i < len(tokens):
        channel = tokens[i]; i += 1
        if channel in 'Zz':
            cursor = start
            continue
        relative = channel.islower()
        if channel in 'Mm':
            a, b = float(tokens[i]), float(tokens[i + 1]); i += 2
            # the very first move is absolute even when written lowercase
            cursor = (cursor[0] + a, cursor[1] + b) if (relative and pts) else (a, b)
            start = cursor
            pts.append(cursor)
            channel = 'l' if relative else 'L'   # the following pairs are line segments
        while i < len(tokens) and not tokens[i].lstrip('-')[:1].isalpha():
            if channel in 'Ll':
                a, b = float(tokens[i]), float(tokens[i + 1]); i += 2
                p = (cursor[0] + a, cursor[1] + b) if relative else (a, b)
                pts.append(p); cursor = p
            elif channel in 'Cc':
                v = [float(tokens[i + k]) for k in range(6)]; i += 6
                if relative:
                    p1 = (cursor[0] + v[0], cursor[1] + v[1])
                    p2 = (cursor[0] + v[2], cursor[1] + v[3])
                    p3 = (cursor[0] + v[4], cursor[1] + v[5])
                else:
                    p1, p2, p3 = (v[0], v[1]), (v[2], v[3]), (v[4], v[5])
                pts.extend(cubic(cursor, p1, p2, p3))
                cursor = p3
            else:
                i += 1

    # drop coincident points, which would make the booleans fail
    cleaned = [pts[0]]
    for p in pts[1:]:
        if abs(p[0] - cleaned[-1][0]) + abs(p[1] - cleaned[-1][1]) > 1e-4:
            cleaned.append(p)
    if (abs(cleaned[0][0] - cleaned[-1][0]) + abs(cleaned[0][1] - cleaned[-1][1])) < 1e-4:
        cleaned.pop()
    return cleaned


def loft_z(bm, stations, x0, x1):
    """Closed solid stacked along Z: stations = [(z, half-thickness in Y)].

    Used as a sculpting former: intersecting it with the extruded silhouette
    yields a part whose thickness varies with height.
    """
    rings = []
    for z, dy in stations:
        rings.append([bm.verts.new(p) for p in
                        ((x0, -dy, z), (x1, -dy, z), (x1, dy, z), (x0, dy, z))])
    for bottom, top in zip(rings, rings[1:]):
        for i in range(4):
            j = (i + 1) % 4
            bm.faces.new((bottom[i], bottom[j], top[j], top[i]))
    bm.faces.new(rings[0][::-1])
    bm.faces.new(rings[-1])


def cone_x(bm, base, tip, segments=40, flatten=1.0):
    """Closed cone whose axis follows X; base and tip are (x, radius, z).

    `aplati` squashes the section along Y: a round horn would be thicker than
    the body at its root and would bulge out of it.
    """
    rings = []
    for x, r, z in (base, tip):
        rings.append([bm.verts.new((x,
                                      math.cos(2 * math.pi * i / segments) * r * flatten,
                                      z + math.sin(2 * math.pi * i / segments) * r))
                        for i in range(segments)])
    for i in range(segments):
        j = (i + 1) % segments
        bm.faces.new((rings[0][i], rings[0][j], rings[1][j], rings[1][i]))
    bm.faces.new(rings[0])
    bm.faces.new(rings[1][::-1])


def sculpt(name, contour, former, coll, material, half):
    """Extruded silhouette, then cut down to the given former.

    This is the principle behind the whole anvil: the silhouette comes from
    the logo and must not move; the volume is given by the former it is
    intersected with.
    """
    bm = bmesh.new()
    extrude_polygon(bm, contour, -half, half)
    ob = make_object(name, bm, coll, material)
    m = ob.modifiers.new("Shape", 'BOOLEAN')
    m.operation = 'INTERSECT'
    m.object = former
    m.solver = 'EXACT'
    return ob

# ----------------------------------------------------------------- anvil

def model_anvil(mats):
    """Forge anvil: face, conical horn, pinched waist, flared foot.

    The silhouette is the SVG's 'anvil' path — head-on, it is the logo. The
    volume comes from two formers: a stack that gives the body its waist, and
    a cone that rounds the horn.
    """
    outline = [(X(x), Z(y)) for x, y in svg_contour('anvil')]
    half = L(max(d for _, d in ANVIL_PROFILE)) * 1.1

    # body former: thickness follows the profile, from foot to face
    bm = bmesh.new()
    loft_z(bm, [(Z(y), L(d)) for y, d in ANVIL_PROFILE],
           X(ANVIL_BODY_X[0]), X(ANVIL_BODY_X[1]))
    body_former = make_object("Body former", bm, "Cutters")

    # horn former: a cone, hence a round horn rather than a flat band
    bm = bmesh.new()
    cone_x(bm, (X(HORN_BASE[0]), L(HORN_BASE[1]), Z(HORN_BASE[2])),
               (X(HORN_TIP[0]), L(HORN_TIP[1]), Z(HORN_TIP[2])),
           flatten=HORN_FLATTEN)
    horn_former = make_object("Horn former", bm, "Cutters")

    body = sculpt("Anvil", outline, body_former, "Anvil",
                     mats["fonte"], half)
    horn = sculpt("Horn", outline, horn_former, "Anvil",
                     mats["fonte"], half)
    for p in horn.data.polygons:
        p.use_smooth = True

    # The horn is fused into the body rather than set against it. Left
    # separate, they exposed the cone's end cap, which showed as a crescent
    # at the root. Merged, there is neither seam nor stray face left: one
    # single closed piece.
    merge = body.modifiers.new("Horn merge", 'BOOLEAN')
    merge.operation = 'UNION'
    merge.object = horn
    merge.solver = 'EXACT'
    horn.hide_render = True
    horn.display_type = 'WIRE'

    # hardy hole (square) and pritchel hole (round), drilled through the heel
    hx0, hx1, side = HARDY
    bm = bmesh.new()
    box(bm, X(hx0), X(hx1), -L(side / 2), L(side / 2),
          Z(TABLE[3]) - L(40), Z(TABLE[2]) + L(30))
    drill(body, make_object("Hardy cutter", bm, "Cutters"))

    bm = bmesh.new()
    cylinder(bm, (X(PRITCHEL[0]), 0, Z((TABLE[2] + TABLE[3]) / 2)),
             L(PRITCHEL[1]), L(120), axis='Z', segments=24)
    drill(body, make_object("Pritchel cutter", bm, "Cutters"))

    bevel(body, L(4), 3)

    # the polished face, hammered by years of striking
    bm = bmesh.new()
    box(bm, X(TABLE[0]), X(TABLE[1]),
          -L(ANVIL_PROFILE[-1][1]) * 0.94, L(ANVIL_PROFILE[-1][1]) * 0.94,
          Z(TABLE[3]), Z(TABLE[2]) + L(1))
    table = make_object("Face", bm, "Anvil", mats["table"])
    bevel(table, L(2), 2)

    # the block: an anvil rests on something. It reaches down to the bottom of
    # the keyboard — "aligned with the bottom" — and stays hidden behind it.
    bm = bmesh.new()
    frustum(bm,
          (X(340), X(690), -L(BLOCK_HALF), L(BLOCK_HALF), Z(CASE[3])),
          (X(370), X(660), -L(BLOCK_HALF * 0.82), L(BLOCK_HALF * 0.82),
           Z(ANVIL_PROFILE[0][0])))
    block = make_object("Block", bm, "Anvil", mats["billot"])
    bevel(block, L(6), 2)
    return body


# --------------------------------------------------------------- keyboard

def key_layout():
    """Position of the white and black keys, in SVG units.

    Returns (white, black) where each white key is (x0, x1, xt0, xt1): its
    own edges, then those of its tail narrowed between the black keys.
    """
    x0, x1 = KEYBED[0], KEYBED[1]
    step = (x1 - x0) / WHITE_KEYS
    gap = 1.2
    blacks = []
    for i in BLACK_BETWEEN:
        channel = x0 + (i + 1) * step
        blacks.append((channel - BLACK_KEY_WIDTH / 2, channel + BLACK_KEY_WIDTH / 2))
    whites = []
    for i in range(WHITE_KEYS):
        a, b = x0 + i * step + gap, x0 + (i + 1) * step - gap
        qa = a + BLACK_KEY_WIDTH / 2 + gap if (i - 1) in BLACK_BETWEEN else a
        qb = b - BLACK_KEY_WIDTH / 2 - gap if i in BLACK_BETWEEN else b
        whites.append((a, b, qa, qb))
    return whites, blacks


def model_keyboard(mats):
    bx0, bx1, by0, by1 = CASE
    front, back = L(CASE_FRONT), L(CASE_BACK)

    # --- the case, and the recess carved into it
    bm = bmesh.new()
    extrude_polygon(bm, [(X(x), Z(y)) for x, y
                          in rounded_rect(bx0, bx1, by0, by1, CASE_RADIUS)],
                     front, back)
    case = make_object("Case", bm, "Keyboard", mats["boitier"])

    lx0, lx1, ly0, ly1 = KEYBED
    bm = bmesh.new()
    box(bm, X(lx0), X(lx1), front - L(20), front + L(KEYBED_RECESS), Z(ly1), Z(ly0))
    hollow = make_object("Recess cutter", bm, "Cutters")

    # the wheel slots, carved as well
    slots = []
    for k, (rx0, rx1, ry0, ry1) in enumerate(WHEELS, 1):
        bm = bmesh.new()
        box(bm, X(rx0), X(rx1), front - L(20), front + L(60), Z(ry1), Z(ry0))
        slots.append(make_object("Slot cutter %d" % k, bm, "Cutters"))

    drill(case, hollow)
    for f in slots:
        drill(case, f)
    bevel(case, L(12), 3)

    # --- the recess floor, so the hollow is not a hole
    bm = bmesh.new()
    box(bm, X(lx0), X(lx1), front + L(KEYBED_RECESS), front + L(KEYBED_RECESS) + L(6), Z(ly1), Z(ly0))
    make_object("Recess floor", bm, "Keyboard", mats["cuvette"])

    # --- the keys
    whites, blacks = key_layout()
    z_front, z_back = Z(KEY_Y[1]), Z(KEY_Y[0])
    z_shoulder = Z(SHOULDER)
    for i, (a, b, qa, qb) in enumerate(whites):
        bm = bmesh.new()
        # T-shaped contour: full width at the front, narrowed tail at the back
        extrude_polygon(bm, [
            (X(a), z_front), (X(b), z_front), (X(b), z_shoulder), (X(qb), z_shoulder),
            (X(qb), z_back), (X(qa), z_back), (X(qa), z_shoulder), (X(a), z_shoulder),
        ], L(KEY_FRONT), front + L(KEYBED_RECESS))
        t = make_object("White key %02d" % (i + 1), bm, "Keyboard", mats["blanche"])
        bevel(t, L(2.6), 2)

    for i, (a, b) in enumerate(blacks):
        bm = bmesh.new()
        # A black key tapers: its top is narrower and a little shorter than its
        # base. It is therefore built as a frustum along Y.
        def rect(inset):
            return (X(a + inset), X(b - inset), Z(SHOULDER - inset * 0.4), Z(KEY_Y[0]))
        r0, r1 = rect(0), rect(2.4)
        v_bottom = [bm.verts.new((r0[0], front + L(KEYBED_RECESS), r0[2])),
              bm.verts.new((r0[1], front + L(KEYBED_RECESS), r0[2])),
              bm.verts.new((r0[1], front + L(KEYBED_RECESS), r0[3])),
              bm.verts.new((r0[0], front + L(KEYBED_RECESS), r0[3]))]
        v_top = [bm.verts.new((r1[0], L(BLACK_KEY_FRONT), r1[2])),
              bm.verts.new((r1[1], L(BLACK_KEY_FRONT), r1[2])),
              bm.verts.new((r1[1], L(BLACK_KEY_FRONT), r1[3])),
              bm.verts.new((r1[0], L(BLACK_KEY_FRONT), r1[3]))]
        for k in range(4):
            j = (k + 1) % 4
            bm.faces.new((v_bottom[k], v_bottom[j], v_top[j], v_top[k]))
        bm.faces.new(v_bottom[::-1]); bm.faces.new(v_top)
        t = make_object("Black key %02d" % (i + 1), bm, "Keyboard", mats["noire"])
        bevel(t, L(2.0), 2)

    # --- the wheels: real knurled discs, half sunk into the panel
    for k, (rx0, rx1, ry0, ry1) in enumerate(WHEELS, 1):
        bm = bmesh.new()
        knurled_wheel(bm, X(rx0 + 4), X(rx1 - 4),
                     L(WHEEL_AXIS), Z((ry0 + ry1) / 2), L(WHEEL_RADIUS))
        r = make_object("Wheel %d" % k, bm, "Keyboard", mats["caoutchouc"])
        for p in r.data.polygons:
            p.use_smooth = True
        bevel(r, L(1.2), 1)

    # --- the rotary knobs
    for k, (cx, cy) in enumerate(KNOBS, 1):
        bm = bmesh.new()
        cylinder(bm, (X(cx), front + L(4), Z(cy)), L(19), L(14), axis='Y', segments=40)
        bezel = make_object("Bezel %d" % k, bm, "Keyboard", mats["lunette"])
        bevel(bezel, L(1.4), 2)

        bm = bmesh.new()
        cylinder(bm, (X(cx), (front + L(KNOB_FRONT)) / 2, Z(cy)),
                 L(14), abs(L(KNOB_FRONT) - front), axis='Y', segments=40, radius2=L(12.5))
        knob = make_object("Knob %d" % k, bm, "Keyboard", mats["bouton"])
        for p in knob.data.polygons:
            p.use_smooth = True
        bevel(knob, L(1.8), 2)

        bm = bmesh.new()      # the indicator, engraved on top of the knob
        box(bm, X(cx) - L(1.6), X(cx) + L(1.6),
              L(KNOB_FRONT) - L(1), L(KNOB_FRONT) + L(1),
              Z(cy) - L(12), Z(cy) - L(3))
        make_object("Marker %d" % k, bm, "Keyboard", mats["repere"])

    # --- the LEDs
    for k, (dx, dy, dw, dh, hue_sat) in enumerate(LEDS, 1):
        bm = bmesh.new()
        box(bm, X(dx), X(dx + dw), front - L(3), front + L(4), Z(dy + dh), Z(dy))
        d = make_object("LED %d" % k, bm, "Keyboard", mats[hue_sat])
        bevel(d, L(1.6), 2)
    return case


def knurled_wheel(bm, x0, x1, cy, cz, radius, teeth=44, hollow=None):
    """Wheel seen edge-on: its axis follows X, its teeth are the knurling.

    This is the geometry of a pitch or modulation wheel: a thick disc of
    which only part of the rim emerges from the panel slot.
    """
    hollow = L(1.8) if hollow is None else hollow
    n = teeth * 2
    left, right = [], []
    for i in range(n):
        a = 2 * math.pi * i / n
        r = radius if i % 2 == 0 else radius - hollow
        y, z = cy + math.cos(a) * r, cz + math.sin(a) * r
        left.append(bm.verts.new((x0, y, z)))
        right.append(bm.verts.new((x1, y, z)))
    for i in range(n):
        j = (i + 1) % n
        bm.faces.new((left[i], left[j], right[j], right[i]))
    bm.faces.new(left[::-1])
    bm.faces.new(right)

# -------------------------------------------------------------------- wave

def import_wave(mats):
    """Pull the wave (ribbon + its two edges) and the panel rim from the SVG.

    The wave is the one element we do not model: its front-on shape is
    exactly what we want to keep. It is registered to the scene frame by
    comparing a reference object — the case outline — with its known place.
    """
    before = set(bpy.data.objects)
    bpy.ops.import_curve.svg(filepath=SVG)
    imported = [o for o in bpy.data.objects if o not in before and o.type == 'CURVE']

    KEEP = {"ribbon": ("braise", "plein", WAVE_Y, WAVE_DEPTH),
             "use145": ("bord_onde", "jonc", WAVE_Y - WAVE_DEPTH / 2, 7),
             "use146": ("bord_onde", "jonc", WAVE_Y - WAVE_DEPTH / 2, 7),
             "chassis-border": ("neon", "jonc", CASE_FRONT - 5, 5)}
    seen, kept_items = set(), []
    for o in sorted(imported, key=lambda o: o.name):
        base = o.name.split('.')[0]
        if base not in KEEP or base in seen:
            bpy.data.objects.remove(o, do_unlink=True)
            continue
        seen.add(base)
        kept_items.append((o, base))

    for o, _ in kept_items:                       # the SVG arrives lying flat
        o.rotation_euler = (math.radians(90), 0, 0)
    bpy.context.view_layer.update()

    # registration: measure the case outline, whose place we know
    reference_object = next(o for o, b in kept_items if b == "chassis-border")
    pts = [reference_object.matrix_world @ v.co
           for s in reference_object.data.splines for v in s.bezier_points]
    mx0, mx1 = min(p.x for p in pts), max(p.x for p in pts)
    mz0 = min(p.z for p in pts)
    k = (X(CASE[1]) - X(CASE[0])) / (mx1 - mx0)
    dx, dz = X(CASE[0]) - mx0 * k, Z(CASE[3]) - mz0 * k

    for o, base in kept_items:
        mat, kind, y, thick = KEEP[base]
        o.scale = (k, k, k)
        o.location = (dx, L(y), dz)
        d = o.data
        d.resolution_u = 14
        # extrude and bevel_depth live in the curve's local space: the object
        # scale multiplies them, so they are divided back out here.
        if kind == "jonc":
            d.dimensions = '3D'
            d.fill_mode = 'FULL'
            d.extrude = 0.0
            d.bevel_depth = L(thick) / k
            d.bevel_resolution = 5
        else:
            d.dimensions = '2D'
            d.fill_mode = 'BOTH'
            d.extrude = L(thick) / 2 / k
            d.bevel_depth = L(2.5) / k
            d.bevel_resolution = 3
        d.materials.clear()
        d.materials.append(mats[mat])
        put_in_collection(o, "Wave" if base != "chassis-border" else "Keyboard")
    print("WAVE REGISTERED: k=%.4f dx=%.3f dz=%.3f" % (k, dx, dz))

# ------------------------------------------------------------ staging

def add_glow(sc, threshold=0.85, size=0.22, force=0.45, saturation=1.10):
    """Neon halo around the bright parts, as in the logo.

    Since Blender 5 the scene compositor is no longer scene.node_tree but a
    node group (scene.compositing_node_group), and the Glare node's settings
    have become inputs — including Type and Quality, which take their
    interface label as a string ("Bloom", not "BLOOM").
    """
    group = bpy.data.node_groups.new("Glow", "CompositorNodeTree")
    group.interface.new_socket("Image", in_out='OUTPUT',
                                socket_type='NodeSocketColor')
    # This group's Group Input is NOT fed by the render: wired to it, the
    # compositor outputs an empty image. A Render Layers node is required
    # inside. Verified by experiment: mean RGBA (0,0,0,0) through the group
    # input, (102,90,79,152) through Render Layers.
    layers = group.nodes.new("CompositorNodeRLayers"); layers.location = (-400, 0)
    output = group.nodes.new("NodeGroupOutput"); output.location = (640, 0)
    glare = group.nodes.new("CompositorNodeGlare"); glare.location = (0, 0)
    glare.inputs['Type'].default_value = 'Bloom'
    glare.inputs['Quality'].default_value = 'High'
    glare.inputs['Threshold'].default_value = threshold
    glare.inputs['Size'].default_value = size
    glare.inputs['Strength'].default_value = force
    group.links.new(layers.outputs['Image'], glare.inputs['Image'])

    # The halo spills past the silhouette, but the render is on a transparent
    # background: without touching alpha, everything that spills would carry
    # colour at zero opacity, and vanish the moment the icon is placed on a
    # background. So the halo's own luminance is carried into the alpha.
    luminance = group.nodes.new("CompositorNodeRGBToBW"); luminance.location = (160, -220)
    group.links.new(glare.outputs['Glare'], luminance.inputs[0])
    maximum = group.nodes.new("ShaderNodeMath"); maximum.location = (310, -220)
    maximum.operation = 'MAXIMUM'
    group.links.new(layers.outputs['Alpha'], maximum.inputs[0])
    group.links.new(luminance.outputs[0], maximum.inputs[1])
    # AgX washes colour out: measured on the render, orange saturation fell to
    # 0.35 where the SVG and the original icon sit at 0.75. It is lifted here
    # rather than by oversaturating the materials, which would blow out under
    # the lights.
    hue_sat = group.nodes.new("CompositorNodeHueSat"); hue_sat.location = (310, 0)
    hue_sat.inputs['Saturation'].default_value = saturation
    group.links.new(glare.outputs['Image'], hue_sat.inputs['Image'])

    set_alpha = group.nodes.new("CompositorNodeSetAlpha"); set_alpha.location = (470, 0)
    # this node defaults to "Apply Mask": it would multiply the image by the
    # alpha instead of setting the alpha, and wipe the halo out
    set_alpha.inputs['Type'].default_value = 'Replace Alpha'
    group.links.new(hue_sat.outputs['Image'], set_alpha.inputs['Image'])
    group.links.new(maximum.outputs[0], set_alpha.inputs['Alpha'])
    group.links.new(set_alpha.outputs['Image'], output.inputs[0])

    sc.compositing_node_group = group
    sc.render.use_compositing = True


def hide_cutters():
    """Put the sculpting formers out of sight without breaking the booleans.

    They serve only to sculpt the parts. Two distinct switches are needed:
    the collection's camera icon removes them from the final render, the eye
    removes them from the viewport's rendered preview. Only the first was
    set, hence the grey volumes floating in the preview.

    The eye, unlike the "Exclude" checkbox, leaves the objects in the
    dependency graph: the boolean modifiers keep evaluating them, and the
    parts stay sculpted.
    """
    coll = collection("Cutters")
    coll.hide_render = True
    for o in coll.objects:
        o.display_type = 'WIRE'      # in case the eye is opened again
    layer = bpy.context.view_layer.layer_collection.children.get(coll.name)
    if layer:
        layer.hide_viewport = True


def choose_engine(sc, samples):
    """Switch the scene to Cycles, on the GPU if the machine has one.

    Trap: engines provided by an add-on — Cycles among them — do NOT appear
    in enum_items. Testing membership of that list falls back to EEVEE every
    single time, without raising anything. The assignment must be attempted
    and its failure caught.
    """
    try:
        sc.render.engine = 'CYCLES'
    except TypeError:
        sc.render.engine = 'BLENDER_EEVEE'
        print("ENGINE: Cycles unavailable, rendering with EEVEE")
        return
    sc.cycles.samples = samples
    sc.cycles.use_denoising = True
    # adaptive sampling stops as soon as noise falls below this threshold: at
    # 0.01 it cuts out long before spending a large sample budget
    sc.cycles.adaptive_threshold = 0.002 if samples >= 512 else 0.01

    prefs = bpy.context.preferences.addons['cycles'].preferences
    for family in ('OPTIX', 'CUDA', 'HIP', 'ONEAPI', 'METAL'):
        try:
            prefs.compute_device_type = family
        except TypeError:
            continue
        prefs.get_devices()
        if any(d.type == family for d in prefs.devices):
            for d in prefs.devices:
                d.use = (d.type == family)
            sc.cycles.device = 'GPU'
            print("ENGINE: Cycles on GPU (%s)" % family)
            return
    print("ENGINE: Cycles on CPU")


def light_scene(cz):
    """Two-tone forge lighting: cold on the left, embers on the right.

    Two families of lamps. The keys provide the light, from above; the
    reflectors are large panels placed IN FRONT of the composition, which
    barely light it but which the metal mirrors. They are where the blue and
    orange sheens on the anvil come from: a flat metallic face does not show
    the light falling on it, it shows what stands in front of it.
    """
    target = Vector((0.0, 0.0, cz))

    def lamp(name, pos, power, colour, size, rot=None):
        d = bpy.data.lights.new(name, 'AREA')
        d.energy, d.color, d.size = power, colour, size
        o = bpy.data.objects.new(name, d)
        o.location = pos
        # with no explicit angles, the lamp aims at the centre of the scene
        o.rotation_euler = rot if rot is not None else \
            (target - Vector(pos)).to_track_quat('-Z', 'Y').to_euler()
        bpy.context.scene.collection.objects.link(o)
        put_in_collection(o, "Lighting")

    lamp("Cold key",  (-2.7, -3.0, cz + 1.9), 185, (0.38, 0.74, 1.00), 2.4,
          (math.radians(54), 0, math.radians(-42)))
    lamp("Forge",       ( 2.8, -2.0, cz - 0.9), 150, (1.00, 0.55, 0.24), 1.8,
          (math.radians(104), 0, math.radians(56)))
    lamp("Back light", ( 0.0,  2.6, cz + 1.4),  65, (0.66, 0.84, 1.00), 3.2,
          (math.radians(-54), 0, 0))
    # the two panels the anvil mirrors
    lamp("Cold reflector", (-2.1, -3.4, cz + 1.0),  45, (0.22, 0.58, 1.00), 4.2)
    lamp("Ember reflector", ( 2.1, -3.2, cz - 0.5),  72, (1.00, 0.52, 0.20), 3.6)


def place_cameras():
    """Orthographic front view — the one that guarantees the composition —
    plus two three-quarter views to judge the volumes."""
    bpy.context.view_layer.update()
    xs, zs = [], []
    for o in bpy.data.objects:
        if o.type != 'MESH' and o.type != 'CURVE':
            continue
        if o.users_collection and o.users_collection[0].name == "Cutters":
            continue
        for channel in o.bound_box:
            w = o.matrix_world @ Vector(channel)
            xs.append(w.x); zs.append(w.z)
    x0, x1, z0, z1 = min(xs), max(xs), min(zs), max(zs)
    cx, cz = (x0 + x1) / 2, (z0 + z1) / 2
    width = max(x1 - x0, z1 - z0) * 1.06
    print("FRAME: x %.2f..%.2f  z %.2f..%.2f" % (x0, x1, z0, z1))

    # The two free cameras aim at the centre of the composition: their
    # orientation is computed rather than hard-coded, otherwise the slightest
    # change of proportions has them looking off to one side.
    target = Vector((cx, 0.0, cz))
    for name, pos, lens in (
            ("Camera_logo", (cx, -6.0, cz), None),
            ("Camera_trois_quarts", (cx - 1.9, -3.1, cz + 1.25), 55),
            ("Camera_rasante", (cx + 2.2, -2.4, cz - 0.75), 62)):
        d = bpy.data.cameras.new(name)
        if lens is None:
            d.type = 'ORTHO'; d.ortho_scale = width
        else:
            d.lens = lens
        o = bpy.data.objects.new(name, d)
        o.location = pos
        o.rotation_euler = (target - Vector(pos)).to_track_quat('-Z', 'Y').to_euler()
        bpy.context.scene.collection.objects.link(o)
        put_in_collection(o, "Cameras")
    bpy.context.scene.camera = bpy.data.objects["Camera_logo"]
    return cz


def main():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    mats = palette()
    collection("Cutters").hide_render = True

    model_anvil(mats)
    model_keyboard(mats)
    import_wave(mats)
    cz = place_cameras()
    light_scene(cz)

    world = bpy.data.worlds.new("World"); bpy.context.scene.world = world
    if not world.node_tree:
        world.use_nodes = True
    world.node_tree.nodes["Background"].inputs[0].default_value = (0.006, 0.011, 0.020, 1)

    sc = bpy.context.scene
    choose_engine(sc, SAMPLES)
    sc.render.resolution_x = sc.render.resolution_y = 1024
    sc.render.film_transparent = True
    # AgX washes out saturated emissives: the "punchy" look gives their hue back
    looks = sc.view_settings.bl_rna.properties['look'].enum_items.keys()
    for candidate in ('AgX - Punchy', 'Punchy', 'AgX - Medium High Contrast'):
        if candidate in looks:
            sc.view_settings.look = candidate
            break

    hide_cutters()

    add_glow(sc)

    bpy.ops.wm.save_as_mainfile(filepath=BLEND)
    print("PROJECT SAVED:", BLEND)
    for cam in [o for o in bpy.data.objects if o.type == 'CAMERA']:
        sc.camera = cam
        sc.render.filepath = OUT.rsplit('.', 1)[0] + '_' + cam.name + '.png'
        bpy.ops.render.render(write_still=True)
    print("RENDERS WRITTEN")

if __name__ == "__main__":
    main()

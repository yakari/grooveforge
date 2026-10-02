"""GrooveForge logo in 3D: the SVG wave, extruded and lifted off the keyboard.

    blender -b --factory-startup --python blender_logo_3d.py -- \
            [--out render.png] [--blend project.blend] [--samples 128]
            [--resolution 1024] [--camera Camera_logo]

The anvil and the keyboard come from blender_anvil_keyboard.py, imported as
a module. This file deals only with the wave.

Earlier procedural attempts lost the charm of the original drawing. So the
'ribbon' path of grooveforge_logo.svg is taken as it is — the hand-drawn
wave, down to the stroke — and only two things are added: a thickness, and a
lift-off.

The lift-off is a plain shear along Y, driven by the abscissa alone: every
contour point is pushed towards the viewer by an amount that depends only on
its x. Two useful consequences:
  - the front view is strictly unchanged, since the camera looks along Y: the
    logo's wave comes back pixel for pixel;
  - the thickness is preserved everywhere, since both faces shift by the same
    amount.

And because the wave is a single solid, its baseline melts into the mass
instead of standing out as a horizontal rod across the composition — which
was the flaw of the version built from separate round beads.
"""
import bpy, bmesh, math, os, sys, importlib.util
from mathutils import Vector

# --- reuse the anvil, the keyboard, the materials and the lighting -------
_base = os.path.join(os.path.dirname(os.path.abspath(__file__)),
                     "blender_anvil_keyboard.py")
_spec = importlib.util.spec_from_file_location("enclume_clavier", _base)
M = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(M)

X, Z, L = M.X, M.Z, M.L

argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
def opt(n, d): return argv[argv.index(n) + 1] if n in argv else d
OUT     = opt("--out",   "/tmp/gf3d_onde.png")
BLEND   = opt("--blend", "/tmp/gf3d_onde.blend")
SAMPLES = int(opt("--samples", "128"))
RESOLUTION = int(opt("--resolution", "1024"))
CAMERA  = opt("--camera", "")      # empty = all three viewpoints

# ------------------------------------------------------------------- wave
# In SVG units. The 'ribbon' path runs from x=300 to x=700 and both of its
# ends are centred on y=512 — exactly the top edge of the keyboard. The wave
# is therefore already resting on it, with nothing to realign.
WAVE_THICKNESS = 26      # "a little": invisible head-on
WAVE_Y_RIM    = M.CASE_FRONT - 5   # at the ends: the rim's own depth
WAVE_Y_PEAK  = -360    # at mid-span: furthest from the keyboard
WAVE_LIFTOFF = 0.35    # half-width of the zone where it leaves the panel
WAVE_STEP       = 5.0     # contour resampling step

# The logo's bright rim: SVG class s-core, so 9 px wide, drawn over the
# fill. In 3D it is a flat band laid on the wave's two edges, sheared exactly
# like the wave — so it stays glued to it instead of barring the composition
# like a rod.
# Its thickness matches the wave's to within two pixels: just enough to keep
# the faces from being coplanar, and to catch a thread of light on the edge.
# Any thicker and it visually detaches from the ribbon.
EDGES          = ('use145', 'use146')   # the two edges, the very ones the
                                        # 'ribbon' fill is derived from
RIM_WIDTH  = 9
RIM_PROUD   = 2      # how far it stands proud of both faces
MITER_LIMIT          = 4.0    # miter limit: beyond it, a corner would turn into a spike


def liftoff(t):
    """Distance from the keyboard panel, along the wave.

    Zero over a wide stretch at both ends — there the wave genuinely rests on
    the keyboard, continuing its rim — then full at mid-span, as a half sine.
    A sine spread over the whole length will not do: the wave would already
    be far in front of the keyboard at the very place it is meant to lean on.
    """
    u = 1.0 - min(1.0, abs(t - 0.5) / WAVE_LIFTOFF)
    return WAVE_Y_RIM + (WAVE_Y_PEAK - WAVE_Y_RIM) * (1 - math.cos(math.pi * u)) / 2


def densify(contour, step, closed=True):
    """Resample the contour so that no segment is longer than `pas`.

    Essential: the path contains long straight segments, of which contour_svg
    keeps only the two endpoints. Without intermediate points the shear would
    cross them in a straight line instead of bending them, and the wave's
    baseline would stay flat.
    """
    output = []
    n = len(contour) if closed else len(contour) - 1
    for i in range(n):
        a, b = contour[i], contour[(i + 1) % len(contour)]
        output.append(a)
        d = math.dist(a, b)
        for k in range(1, int(d / step)):
            u = k * step / d
            output.append((a[0] + (b[0] - a[0]) * u, a[1] + (b[1] - a[1]) * u))
    if not closed:
        output.append(contour[-1])
    return output


def mitred_normals(points):
    """Mitred normals in the XZ plane, to lay a band along a path.

    Taken in the image plane and never in space, the normal keeps the band
    facing the camera. The miter factor — 1/sin(half-angle) — is what keeps
    the spikes sharp: without it every corner would be cut flat.
    """
    output = []
    for i, p in enumerate(points):
        a = points[i - 1] if i > 0 else p
        b = points[i + 1] if i < len(points) - 1 else p
        t_in = Vector((p.x - a.x, 0.0, p.z - a.z))
        t_out = Vector((b.x - p.x, 0.0, b.z - p.z))
        if t_in.length < 1e-9:
            t_in = t_out.copy()
        if t_out.length < 1e-9:
            t_out = t_in.copy()
        t_in.normalize(); t_out.normalize()
        n_in = Vector((-t_in.z, 0.0, t_in.x))
        n_out = Vector((-t_out.z, 0.0, t_out.x))
        n = n_in + n_out
        n = n_in.copy() if n.length < 1e-9 else n
        n.normalize()
        output.append(n * min(1.0 / max(n.dot(n_in), 1e-3), MITER_LIMIT))
    return output


def band(name, width, thickness, setback, material, x0, x1):
    """Flat band laid on the wave's two edges, sheared just like it."""
    bm = bmesh.new()
    before = Vector((0.0, -1.0, 0.0))
    half_w, half_d = L(width) / 2, L(thickness) / 2
    for ident in EDGES:
        path_points = densify(M.svg_contour(ident, step=4.0), WAVE_STEP, closed=False)
        points = [Vector((X(sx),
                          L(liftoff((sx - x0) / (x1 - x0)) + setback),
                          Z(sy))) for sx, sy in path_points]
        rings = [[bm.verts.new(p + n * half_w + before * half_d),
                    bm.verts.new(p + n * half_w - before * half_d),
                    bm.verts.new(p - n * half_w - before * half_d),
                    bm.verts.new(p - n * half_w + before * half_d)]
                   for p, n in zip(points, mitred_normals(points))]
        for a, b in zip(rings, rings[1:]):
            for i in range(4):
                j = (i + 1) % 4
                bm.faces.new((a[i], a[j], b[j], b[i]))
        bm.faces.new(rings[0][::-1])
        bm.faces.new(rings[-1])
    return M.make_object(name, bm, "Wave", material)


def model_wave(mats):
    contour = densify(M.svg_contour('ribbon', step=4.0), WAVE_STEP)
    xs = [p[0] for p in contour]
    x0, x1 = min(xs), max(xs)
    half = L(WAVE_THICKNESS) / 2

    bm = bmesh.new()
    ahead, behind = [], []
    for sx, sy in contour:
        y = L(liftoff((sx - x0) / (x1 - x0)))
        ahead.append(bm.verts.new((X(sx), y - half, Z(sy))))
        behind.append(bm.verts.new((X(sx), y + half, Z(sy))))
    n = len(contour)
    for i in range(n):
        j = (i + 1) % n
        bm.faces.new((ahead[i], ahead[j], behind[j], behind[i]))
    bm.faces.new(ahead[::-1])
    bm.faces.new(behind)

    wave = M.make_object("Wave", bm, "Wave", mats["braise"])
    M.bevel(wave, L(1.6), 2)   # just enough to catch the light

    # the bright rim, flush with the wave: head-on it outlines it as in 2D,
    # from three-quarters it is only a thread along its edge
    rims = band("Rim", RIM_WIDTH, WAVE_THICKNESS + RIM_PROUD, 0,
                    mats["bord_onde"], x0, x1)
    M.bevel(rims, L(0.8), 2)

    print("WAVE: %d points, x %.0f..%.0f" % (n, x0, x1))
    return wave


def keyboard_rim(mats):
    """The panel's glowing rim, also taken straight from the SVG."""
    before = set(bpy.data.objects)
    bpy.ops.import_curve.svg(filepath=M.SVG)
    imported = [o for o in bpy.data.objects if o not in before and o.type == 'CURVE']
    kept = None
    for o in sorted(imported, key=lambda o: o.name):
        if o.name.split('.')[0] == "chassis-border" and kept is None:
            kept = o
        else:
            bpy.data.objects.remove(o, do_unlink=True)

    kept.rotation_euler = (math.radians(90), 0, 0)
    bpy.context.view_layer.update()
    pts = [kept.matrix_world @ v.co
           for s in kept.data.splines for v in s.bezier_points]
    mx0, mx1 = min(p.x for p in pts), max(p.x for p in pts)
    mz0 = min(p.z for p in pts)
    k = (X(M.CASE[1]) - X(M.CASE[0])) / (mx1 - mx0)
    kept.scale = (k, k, k)
    kept.location = (X(M.CASE[0]) - mx0 * k, L(M.CASE_FRONT - 5),
                      Z(M.CASE[3]) - mz0 * k)
    d = kept.data
    d.resolution_u = 14
    d.dimensions = '3D'
    d.fill_mode = 'FULL'
    d.extrude = 0.0
    # extrude and bevel_depth live in local space: object scale multiplies them
    d.bevel_depth = L(5) / k
    d.bevel_resolution = 5
    d.materials.clear()
    d.materials.append(mats["neon"])
    M.put_in_collection(kept, "Keyboard")


def place_cameras():
    """Width measured on anvil and keyboard, height on everything.

    The wave rises higher than the anvil: left out of the vertical figure,
    its spike would be cropped out of frame.
    """
    bpy.context.view_layer.update()

    def extent(collections):
        xs, zs = [], []
        for name in collections:
            for o in bpy.data.collections[name].objects:
                if o.type not in ('MESH', 'CURVE'):
                    continue
                for channel in o.bound_box:
                    w = o.matrix_world @ Vector(channel)
                    xs.append(w.x); zs.append(w.z)
        return min(xs), max(xs), min(zs), max(zs)

    x0, x1, _, _ = extent(("Anvil", "Keyboard"))
    _, _, z0, z1 = extent(("Anvil", "Keyboard", "Wave"))
    cx, cz = (x0 + x1) / 2, (z0 + z1) / 2
    width = max(x1 - x0, z1 - z0) * 1.06
    print("FRAME: x %.2f..%.2f  z %.2f..%.2f" % (x0, x1, z0, z1))

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
        M.put_in_collection(o, "Cameras")
    bpy.context.scene.camera = bpy.data.objects["Camera_logo"]
    return cz


def main():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    mats = M.palette()
    M.collection("Cutters").hide_render = True

    M.model_anvil(mats)
    M.model_keyboard(mats)
    keyboard_rim(mats)
    model_wave(mats)
    cz = place_cameras()
    M.light_scene(cz)

    world = bpy.data.worlds.new("World"); bpy.context.scene.world = world
    if not world.node_tree:
        world.use_nodes = True
    world.node_tree.nodes["Background"].inputs[0].default_value = (0.006, 0.011, 0.020, 1)

    sc = bpy.context.scene
    M.choose_engine(sc, SAMPLES)
    sc.render.resolution_x = sc.render.resolution_y = RESOLUTION
    sc.render.film_transparent = True
    looks = sc.view_settings.bl_rna.properties['look'].enum_items.keys()
    for candidate in ('AgX - Punchy', 'Punchy', 'AgX - Medium High Contrast'):
        if candidate in looks:
            sc.view_settings.look = candidate
            break

    M.hide_cutters()

    M.add_glow(sc)

    bpy.ops.wm.save_as_mainfile(filepath=BLEND)
    print("PROJECT SAVED:", BLEND)
    # A single camera requested: write under the given name, no suffix.
    # Otherwise emit all three viewpoints, each suffixed by camera.
    cams = [o for o in bpy.data.objects if o.type == 'CAMERA']
    if CAMERA:
        cams = [o for o in cams if o.name == CAMERA]
        if not cams:
            raise SystemExit("camera inconnue : " + CAMERA)
    for cam in cams:
        sc.camera = cam
        sc.render.filepath = OUT if CAMERA else \
            OUT.rsplit('.', 1)[0] + '_' + cam.name + '.png'
        bpy.ops.render.render(write_still=True)
        print("RENDER:", sc.render.filepath)


if __name__ == "__main__":
    main()

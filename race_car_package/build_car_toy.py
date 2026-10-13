"""Open-wheel race car, 2022+ style (ground-effect era), modelled after the user's reference.
Original livery, no brands. Units: meters. Y up, +Z forward, ground y=0.
Driver's right side is -X. Wheels are separate nodes with pivot at the hub.
"""
import numpy as np
import trimesh
import shapely.geometry as sg
from trimesh.visual.material import PBRMaterial

MAT = {
    "red":    dict(c=(0.86, 0.13, 0.11), m=0.15, r=0.30),
    "white":  dict(c=(0.94, 0.94, 0.96), m=0.10, r=0.30),
    "navy":   dict(c=(0.16, 0.22, 0.72), m=0.15, r=0.30),
    "carbon": dict(c=(0.09, 0.09, 0.10), m=0.25, r=0.45),
    "inlet":  dict(c=(0.02, 0.02, 0.02), m=0.00, r=0.90),
    "tyre":   dict(c=(0.07, 0.07, 0.07), m=0.00, r=0.85),
    "rim":    dict(c=(0.12, 0.12, 0.13), m=0.60, r=0.35),
    "stripe": dict(c=(0.95, 0.88, 0.10), m=0.00, r=0.60),
    "helmet": dict(c=(0.85, 0.12, 0.12), m=0.20, r=0.25),
    "visor":  dict(c=(0.02, 0.02, 0.04), m=0.60, r=0.10),
    "camera": dict(c=(0.98, 0.85, 0.08), m=0.10, r=0.40),
    "light":  dict(c=(0.90, 0.10, 0.10), m=0.00, r=0.30),
    "lens":   dict(c=(0.02, 0.02, 0.02), m=0.10, r=0.25),
    "led":    dict(c=(1.00, 0.05, 0.04), m=0.00, r=0.20, e=(1.0, 0.03, 0.02)),
    "led_off": dict(c=(0.45, 0.45, 0.47), m=0.30, r=0.25),
}

# ------------------------------------------------------------------ helpers
def catmull(params, sub):
    S = np.array(params, float)
    if sub <= 1 or len(S) < 3:
        return S
    P = np.vstack([2 * S[0] - S[1], S, 2 * S[-1] - S[-2]])
    out = []
    for i in range(1, len(P) - 2):
        p0, p1, p2, p3 = P[i - 1], P[i], P[i + 1], P[i + 2]
        for t in np.linspace(0, 1, sub, endpoint=False):
            out.append(0.5 * (2 * p1 + (-p0 + p2) * t + (2 * p0 - 5 * p1 + 4 * p2 - p3) * t ** 2
                              + (-p0 + 3 * p1 - 3 * p2 + p3) * t ** 3))
    out.append(S[-1])
    return np.array(out)


def loft_rings(rings, cap_front=True, cap_back=True):
    """rings: list of (M,3) closed loops with equal M. Metadata per face: col index, ring index, cap flag."""
    R = np.asarray(rings, float)
    m, n = R.shape[0], R.shape[1]
    verts = R.reshape(-1, 3).tolist()
    faces, col, ring, cap = [], [], [], []
    for i in range(m - 1):
        for j in range(n):
            a, b = i * n + j, i * n + (j + 1) % n
            faces += [[a, a + n, b], [b, a + n, b + n]]
            col += [j, j]; ring += [i, i]; cap += [0, 0]
    for idx, flag, do in ((0, 1, cap_front), (m - 1, 2, cap_back)):
        if not do:
            continue
        ci = len(verts); verts.append(R[idx].mean(0).tolist())
        for j in range(n):
            a, b = idx * n + j, idx * n + (j + 1) % n
            faces.append([ci, a, b] if idx == 0 else [ci, b, a])
            col.append(j); ring.append(idx); cap.append(flag)
    mesh = trimesh.Trimesh(np.array(verts), np.array(faces), process=False)
    # orient outward: check signed volume
    if mesh.volume < 0:
        mesh.faces = mesh.faces[:, ::-1]
    mesh.metadata.update(col=np.array(col), ring=np.array(ring), cap=np.array(cap), n=n, m=m)
    return mesh


def superellipse(n, p):
    t = np.linspace(0, 2 * np.pi, n, endpoint=False) + np.pi / n
    c, s = np.cos(t), np.sin(t)
    return np.sign(c) * np.abs(c) ** (2 / p), np.sign(s) * np.abs(s) ** (2 / p)


def bez(p0, p1, p2, p3, n, endpoint=False):
    t = np.linspace(0, 1, n, endpoint=endpoint)[:, None]
    p0, p1, p2, p3 = map(np.array, (p0, p1, p2, p3))
    return (1 - t) ** 3 * p0 + 3 * (1 - t) ** 2 * t * p1 + 3 * (1 - t) * t ** 2 * p2 + t ** 3 * p3


def loft_with_inlet(rings, depth=0.06, shrink=0.80):
    """Loft whose front face is an inlet: a lip, then a tunnel `depth` deep leading to a dark back wall.
    Faces tagged: metadata['inlet'] True for tunnel walls and back wall."""
    R = [np.asarray(r, float) for r in rings]
    r0 = R[0]; c = r0.mean(0)
    inner = c + shrink * (r0 - c); inner[:, 2] = r0[0, 2] - depth
    lip = c + (0.5 + shrink / 2) * (r0 - c); lip[:, 2] = r0[0, 2] - 0.01   # rounded-looking lip roll
    mesh = loft_rings([inner, lip, r0] + R[1:])
    md = mesh.metadata
    md["inlet"] = ((md["ring"] == 0) & (md["cap"] == 0)) | (md["cap"] == 1)
    return mesh


def body_rings(sections, n=40, sub=6, p=3.0, taper=0.0):
    S = catmull(sections, sub)
    ex, ey = superellipse(n, p)
    rings = []
    for z, xc, yb, yt, hw in S[:, :5]:
        k = 1 - taper * np.clip(ey, 0, 1)
        rings.append(np.stack([xc + hw * ex * k, (yb + yt) / 2 + ey * (yt - yb) / 2, np.full(n, z)], 1))
    return rings


def recessed_inlet(name, outer_xy, slot, z, depth, panel_mat, wall_mat="carbon", back_mat="inlet", both=False):
    """Flat front panel (outer outline minus slot) at z, a tunnel `depth` deep and a dark back wall."""
    panel_poly = sg.Polygon(outer_xy).difference(slot)
    v, f = trimesh.creation.triangulate_polygon(panel_poly)
    panel = trimesh.Trimesh(np.column_stack([v, np.full(len(v), z)]), f)
    if panel.face_normals[:, 2].mean() < 0:
        panel.invert()
    add(name + "_face", panel, panel_mat, both=both)
    ring = np.array(slot.exterior.coords)[:-1]
    n = len(ring)
    V = np.vstack([np.column_stack([ring, np.full(n, z)]), np.column_stack([ring, np.full(n, z - depth)])])
    F = []
    for j in range(n):
        a, b = j, (j + 1) % n
        F += [[a, b, a + n], [b, b + n, a + n]]
    walls = trimesh.Trimesh(V, np.array(F), process=False)
    c = ring.mean(0)
    outward = ((walls.triangles_center[:, :2] - c) * walls.face_normals[:, :2]).sum(1)
    if (outward * walls.area_faces).sum() > 0:      # walls must face into the opening
        walls.invert()
    add(name + "_walls", walls, wall_mat, both=both)
    v, f = trimesh.creation.triangulate_polygon(slot)
    back = trimesh.Trimesh(np.column_stack([v, np.full(len(v), z - depth)]), f)
    if back.face_normals[:, 2].mean() < 0:
        back.invert()
    add(name + "_back", back, back_mat, both=both)


def se_point(t, p):
    c, s_ = np.cos(t), np.sin(t)
    return np.sign(c) * np.abs(c) ** (2 / p), np.sign(s_) * np.abs(s_) ** (2 / p)


def loft_strip(rings, centers):
    """Open strips (no wrap) between rings, capped with fans to `centers` at both ends."""
    R = np.asarray(rings, float); m, n = R.shape[:2]
    verts = R.reshape(-1, 3).tolist(); faces = []
    for i in range(m - 1):
        for j in range(n - 1):
            a, b = i * n + j, i * n + j + 1
            faces += [[a, a + n, b], [b, a + n, b + n]]
    for idx in (0, m - 1):
        ci = len(verts); verts.append(list(centers[idx]))
        for j in range(n - 1):
            a, b = idx * n + j, idx * n + j + 1
            faces.append([ci, a, b] if idx == 0 else [ci, b, a])
    mesh = trimesh.Trimesh(np.array(verts), np.array(faces), process=False)
    # orient outward relative to the loft axis
    C = np.asarray(centers)
    zc = mesh.triangles_center
    k = np.clip(np.searchsorted(-C[:, 2], -zc[:, 2]), 0, m - 1)
    out = ((zc - C[k]) * mesh.face_normals)[:, :2].sum(1)
    if (out * mesh.area_faces).sum() < 0:
        mesh.invert()
    return mesh


def body_loft_split(sections, thr_of_z, p=3.0, taper=0.0, sub=6, n_top=28, n_bot=40, round_front=0.0, k_round=10):
    """Like body_loft, but split into top/bottom meshes along a smooth line.
    thr_of_z(z) -> level (0..1) of the superellipse 'ey' above which the surface is 'top'."""
    S = catmull(sections, sub)
    z0, xc0, yb0, yt0, hw0 = S[0][:5]
    if round_front > 0:                       # rounded tip that continues the nose line (no crest)
        z1, _, yb1, yt1, hw1 = S[1][:5]
        sl_t = (yt0 - yt1) / (z0 - z1); sl_b = (yb0 - yb1) / (z0 - z1)
        tip = []
        for ph in np.linspace(np.pi / 2, 0, k_round, endpoint=False):
            dz = round_front * np.sin(ph)
            c = max(np.cos(ph), 0.05)
            yb_l = yb0 + sl_b * dz
            yt_l = yt0 + sl_t * dz
            ym = (yb_l + yt_l) / 2; hh = (yt_l - yb_l) / 2 * np.sqrt(c)
            tip.append((z0 + dz, xc0, ym - hh, ym + hh, hw0 * np.sqrt(c) * (0.35 + 0.65 * c ** 0.5)))
        S = np.vstack([np.array(tip), S])
    tops, bots, cen = [], [], []
    for z, xc, yb, yt, hw in S[:, :5]:
        a = np.arcsin(np.clip(thr_of_z(z), 0, 0.999) ** (3.0 / 2 if False else p / 2))
        for rng, cnt, store in (((a, np.pi - a), n_top, tops), ((np.pi - a, 2 * np.pi + a), n_bot, bots)):
            t = np.linspace(rng[0], rng[1], cnt)
            ex, ey = se_point(t, p)
            k = 1 - taper * np.clip(ey, 0, 1)
            store.append(np.stack([xc + hw * ex * k, (yb + yt) / 2 + ey * (yt - yb) / 2, np.full(cnt, z)], 1))
        cen.append((xc, (yb + yt) / 2, z))
    return loft_strip(tops, cen), loft_strip(bots, cen)


def smooth_closed(pts, sub):
    """Periodic Catmull-Rom through closed control polygon (N,3) -> (N*sub,3)."""
    P = np.asarray(pts, float); n = len(P); out = []
    for i in range(n):
        p0, p1, p2, p3 = P[i - 1], P[i], P[(i + 1) % n], P[(i + 2) % n]
        for t in np.linspace(0, 1, sub, endpoint=False):
            out.append(0.5 * (2 * p1 + (-p0 + p2) * t + (2 * p0 - 5 * p1 + 4 * p2 - p3) * t ** 2
                              + (-p0 + 3 * p1 - 3 * p2 + p3) * t ** 3))
    return np.array(out)


def body_loft(sections, n=40, sub=6, p=3.0, taper=0.0):
    """sections: (z, xc, yb, yt, half_w[, p]). Rounded-box cross-sections, top narrower by `taper`."""
    S = catmull(sections, sub)
    ex, ey = superellipse(n, p)
    rings = []
    for z, xc, yb, yt, hw in S[:, :5]:
        k = 1 - taper * np.clip(ey, 0, 1)
        rings.append(np.stack([xc + hw * ex * k, (yb + yt) / 2 + ey * (yt - yb) / 2, np.full(n, z)], 1))
    return loft_rings(rings)


def submesh(mesh, mask):
    idx = np.where(mask)[0]
    return mesh.submesh([idx], append=True) if len(idx) else None


def extrude_xz(poly_xz, y0, y1):
    """Extrude polygon given in (x, z) plane between heights y0..y1."""
    m = trimesh.creation.extrude_polygon(sg.Polygon(poly_xz), y1 - y0)  # along +Z
    # map (x, y, h) -> (x, h, y): polygon y is our z
    T = np.array([[1, 0, 0, 0], [0, 0, 1, y0], [0, 1, 0, 0], [0, 0, 0, 1]], float)
    m.apply_transform(T)
    m.fix_normals()
    return m


def extrude_zy(poly_zy, x0, x1):
    """Extrude polygon given in (z, y) plane between x0..x1 (side plates)."""
    m = trimesh.creation.extrude_polygon(sg.Polygon(poly_zy), x1 - x0)
    T = np.array([[0, 0, 1, x0], [0, 1, 0, 0], [1, 0, 0, 0], [0, 0, 0, 1]], float)
    m.apply_transform(T)
    m.fix_normals()
    return m


def rounded_rect(z0, z1, y0, y1, r_tf=0.0, r_tr=0.0, r_bf=0.0, r_br=0.0, k=8):
    """Rectangle in (z,y) with per-corner radii (tf=top-front at z1)."""
    def arc(cz, cy, r, a0, a1):
        a = np.linspace(a0, a1, k)
        return [(cz + r * np.cos(t), cy + r * np.sin(t)) for t in a]
    pts = []
    pts += arc(z1 - r_bf, y0 + r_bf, r_bf, -np.pi / 2, 0) if r_bf else [(z1, y0)]
    pts += arc(z1 - r_tf, y1 - r_tf, r_tf, 0, np.pi / 2) if r_tf else [(z1, y1)]
    pts += arc(z0 + r_tr, y1 - r_tr, r_tr, np.pi / 2, np.pi) if r_tr else [(z0, y1)]
    pts += arc(z0 + r_br, y0 + r_br, r_br, np.pi, 1.5 * np.pi) if r_br else [(z0, y0)]
    return pts


def airfoil(chord, thick, n=14):
    """Closed 2D section (along-chord u, normal v), leading edge at u=0."""
    u = (1 - np.cos(np.linspace(0, np.pi, n))) / 2
    t = 5 * thick * (0.2969 * np.sqrt(u) - 0.126 * u - 0.3516 * u ** 2 + 0.2843 * u ** 3 - 0.1036 * u ** 4)
    camber = 0.06 * np.sin(np.pi * u) * chord
    upper = np.stack([u * chord, camber + t * chord], 1)
    lower = np.stack([u * chord, camber - t * chord], 1)[::-1][1:-1]
    return np.vstack([upper, lower])


def wing(xs, y_of, zle_of, chord_of, ang_of, thick=0.10, roll_of=None, sub=1):
    """Spanwise loft of airfoil sections. Angle in degrees, positive = trailing edge up.
    Chord runs toward -Z (rearwards)."""
    rings = []
    for x in xs:
        c, a = chord_of(x), np.radians(ang_of(x))
        af = airfoil(c, thick)
        u, v = af[:, 0], af[:, 1]
        # rotate in (z,y): chord direction = (-cos a, sin a)
        z = zle_of(x) - u * np.cos(a) - v * np.sin(a)
        y = y_of(x) + u * np.sin(a) + v * np.cos(a)
        rings.append(np.stack([np.full_like(z, x), y, z], 1))
    return loft_rings(rings)


def smooth01(a, b, x):
    t = np.clip((x - a) / (b - a), 0, 1)
    return t * t * (3 - 2 * t)


def tube(points, r=0.03, sides=12, flat=1.0, sub=4):
    pts = catmull(points, sub) if len(points) > 2 else np.array(points, float)
    T = np.gradient(pts, axis=0)
    T /= np.linalg.norm(T, axis=1, keepdims=True)
    ref = np.array([0, 1, 0]) if abs(T[0][1]) < 0.9 else np.array([0, 0, 1])
    u = np.cross(T[0], ref); u /= np.linalg.norm(u)
    ang = np.linspace(0, 2 * np.pi, sides, endpoint=False)
    rings = []
    for i in range(len(pts)):
        if i:                                  # parallel transport: no sudden twists
            u = u - np.dot(u, T[i]) * T[i]
            u /= np.linalg.norm(u)
        v = np.cross(T[i], u)
        rings.append(pts[i] + r * (np.outer(np.cos(ang), u) + flat * np.outer(np.sin(ang), v)))
    return loft_rings(rings)


def rod(a, b, r=0.016, flat=0.45):
    return tube([a, b], r, sides=8, flat=flat)


def lathe(profile, sections=64):
    """Revolve (r, x) profile (open polyline) around the X axis -> ring mesh."""
    ang = np.linspace(0, 2 * np.pi, sections, endpoint=False)
    P = np.array(profile, float)
    verts, faces = [], []
    n = len(P)
    for a in ang:
        for r, x in P:
            verts.append([x, r * np.cos(a), r * np.sin(a)])
    for i in range(sections):
        i2 = (i + 1) % sections
        for j in range(n - 1):
            a, b = i * n + j, i * n + j + 1
            c, d = i2 * n + j, i2 * n + j + 1
            faces += [[a, c, b], [b, c, d]]
    m = trimesh.Trimesh(np.array(verts), np.array(faces), process=True)
    m.fix_normals()
    return m


def mirror_x(mesh):
    m = mesh.copy()
    m.apply_transform(np.diag([-1, 1, 1, 1]))  # trimesh fixes winding for det<0
    return m


# ------------------------------------------------------------------ layout
FRONT_Z, REAR_Z = 1.48, -1.68          # axles
TYRE_R = 0.43
FRONT_W, REAR_W = 0.44, 0.52           # tyre widths
FRONT_X, REAR_X = 0.88, 0.88           # wheel centre |x|

parts = []
def add(name, mesh, mat, both=False):
    if mesh is None:
        return
    if both:
        parts.append((name + "_L", mesh, mat))
        parts.append((name + "_R", mirror_x(mesh), mat))
    else:
        parts.append((name, mesh, mat))

# ---------------- monocoque + nose + engine cover (one loft)
# (z, xc, y_bottom, y_top, half_width)
CH = [
    (2.46, 0, 0.075, 0.200, 0.180),
    (2.30, 0, 0.095, 0.275, 0.182),
    (1.98, 0, 0.135, 0.380, 0.190),
    (1.62, 0, 0.150, 0.470, 0.205),
    (1.22, 0, 0.135, 0.545, 0.235),
    (0.82, 0, 0.100, 0.590, 0.260),
    (0.45, 0, 0.065, 0.620, 0.290),
    (0.05, 0, 0.060, 0.640, 0.310),
    (-0.35, 0, 0.060, 0.675, 0.330),
    (-0.85, 0, 0.070, 0.645, 0.275),
    (-1.30, 0, 0.100, 0.555, 0.180),
    (-1.72, 0, 0.160, 0.445, 0.105),
    (-1.98, 0, 0.200, 0.375, 0.075),
    (-2.10, 0, 0.215, 0.345, 0.055),
]
ch_top, ch_side = body_loft_split(
    CH, thr_of_z=lambda z: 0.25 + 0.50 * smooth01(0.6, 1.6, z),   # nose: narrow red stripe, white flanks
    p=2.7, taper=0.25, sub=8, n_top=32, n_bot=44, round_front=0.15)
add("chassis_top", ch_top, "red")
add("chassis_side", ch_side, "white")

# cockpit opening (dark) + driver
ck = body_loft([(0.52, 0, 0.600, 0.640, 0.10), (0.35, 0, 0.605, 0.645, 0.215),
                (0.00, 0, 0.615, 0.655, 0.235), (-0.22, 0, 0.625, 0.665, 0.17)], n=72, sub=10, p=2.6)
add("cockpit", ck, "inlet")
def sphere_patch(R, lat0, lat1, lon0, lon1, nlat, nlon):
    """UV-sphere patch; lat = elevation, lon = angle from +Z (forward) towards +X. Degrees."""
    la = np.radians(np.linspace(lat0, lat1, nlat)); lo = np.radians(np.linspace(lon0, lon1, nlon))
    L, O = np.meshgrid(la, lo, indexing="ij")
    V = np.stack([R * np.cos(L) * np.sin(O), R * np.sin(L), R * np.cos(L) * np.cos(O)], -1).reshape(-1, 3)
    F = []
    for i in range(nlat - 1):
        for j in range(nlon - 1):
            a, b = i * nlon + j, i * nlon + j + 1
            F += [[a, b, a + nlon], [b, b + nlon, a + nlon]]
    m = trimesh.Trimesh(V, np.array(F), process=True)
    if ((m.triangles_center * m.face_normals).sum(1) < 0).mean() > 0.5:
        m.invert()
    return m

HEL_C, HEL_R = np.array([0, 0.735, 0.11]), 0.165
hel = sphere_patch(HEL_R, -60, 90, -180, 180, 60, 97)
hel.apply_scale([1.0, 1.0, 1.06]); hel.apply_translation(HEL_C)
add("helmet", hel, "helmet")
def visor_patch(R, lat_c, half_h, lon_max, nlat=10, nlon=80):
    """Wrap-around visor band with rounded ends (band height shrinks smoothly near the ends)."""
    lo = np.radians(np.linspace(-lon_max, lon_max, nlon))
    u = np.abs(np.degrees(lo)) / lon_max
    hh = half_h * np.sqrt(np.clip(1 - np.clip((u - 0.80) / 0.20, 0, 1) ** 2, 0.02, 1))
    V = []
    for i in range(nlat):
        t = -1 + 2 * i / (nlat - 1)
        la = np.radians(lat_c + t * hh)
        V.append(np.stack([R * np.cos(la) * np.sin(lo), R * np.sin(la), R * np.cos(la) * np.cos(lo)], -1))
    V = np.concatenate(V)
    F = []
    for i in range(nlat - 1):
        for j in range(nlon - 1):
            a, b = i * nlon + j, i * nlon + j + 1
            F += [[a, b, a + nlon], [b, b + nlon, a + nlon]]
    m = trimesh.Trimesh(V, np.array(F), process=True)
    if ((m.triangles_center * m.face_normals).sum(1) < 0).mean() > 0.5:
        m.invert()
    return m

vis = visor_patch(HEL_R * 1.012, 10, 10, 80)
vis.apply_scale([1.0, 1.0, 1.06]); vis.apply_translation(HEL_C)
add("visor", vis, "visor")
# headrest
add("headrest", body_loft([(0.02, 0, 0.60, 0.71, 0.22), (-0.22, 0, 0.60, 0.70, 0.22)], n=24, sub=1, p=4), "red")

# ---------------- sidepods: letterbox inlet, undercut, downwash ramp (right side built at +x, mirrored)
def pod_ring(z, xin, xo, ytop, ybot, ybody):
    """Closed (x,y) loop for a sidepod section built from Bezier pieces -> smooth, no lumps.
    Order: inner-top -> top -> shoulder -> outer side -> lip -> undercut -> inner wall."""
    w = xo - xin
    pts = np.vstack([
        bez((xin, ytop - 0.02), (xin + 0.45 * w, ytop + 0.012), (xo - 0.02, ytop + 0.004), (xo, ytop - 0.085), 16),  # top
        bez((xo, ytop - 0.085), (xo + 0.012, ytop - 0.15), (xo + 0.01, ybot + 0.06), (xo - 0.025, ybot + 0.012), 10),  # side
        bez((xo - 0.025, ybot + 0.012), (xo - 0.04, ybot - 0.004), (xo - 0.06, ybot - 0.006), (xo - 0.08, ybot - 0.004), 4),  # lip
        bez((xo - 0.08, ybot - 0.004), (xin + 0.40 * w, ybot + 0.010), (xin + 0.08, ybody + 0.05), (xin, ybody), 12),  # undercut
        bez((xin, ybody), (xin, ybody + 0.3 * (ytop - ybody)), (xin, ytop - 0.3 * (ytop - ybody)), (xin, ytop - 0.02), 6),  # hidden inner wall
    ])
    return np.column_stack([pts, np.full(len(pts), z)])

POD_TOP_N = 16 + 6     # top piece + upper part of side painted red
# (z, xin, xo, ytop, ybot, ybody)
PODS = [
    (0.88, 0.24, 0.520, 0.565, 0.420, 0.405),
    (0.80, 0.24, 0.620, 0.590, 0.330, 0.300),
    (0.50, 0.23, 0.690, 0.600, 0.250, 0.160),
    (0.05, 0.22, 0.700, 0.575, 0.200, 0.08),
    (-0.45, 0.18, 0.640, 0.510, 0.170, 0.08),
    (-0.90, 0.14, 0.500, 0.420, 0.150, 0.08),
    (-1.25, 0.10, 0.340, 0.345, 0.140, 0.10),
    (-1.55, 0.08, 0.200, 0.290, 0.150, 0.13),
]
PS = catmull(PODS, 6)
rings = [pod_ring(*p) for p in PS]
pod = loft_rings(rings, cap_front=False)
md = pod.metadata
add("sidepod_top", submesh(pod, md["col"] < POD_TOP_N), "red", both=True)
add("sidepod_low", submesh(pod, md["col"] >= POD_TOP_N), "white", both=True)
r0 = rings[0]
z0, xin0, xo0, yt0, yb0, ybody0 = PS[0]
face = sg.Polygon(r0[:, :2]).buffer(-0.007, join_style=1)
_y0, _y1 = ybody0 + 0.014, yb0 + 0.050            # bottom edge rises towards the outboard side
_k = (_y1 - _y0) / (xo0 - xin0)
cut = sg.Polygon([(xin0 - 1, _y0 - _k), (xo0 + 1, _y1 + _k), (xo0 + 1, 2.0), (xin0 - 1, 2.0)])
slot = face.intersection(cut).buffer(-0.016, join_style=1).buffer(0.016, join_style=1).simplify(0.0003)
slot = sg.polygon.orient(slot, 1.0)
recessed_inlet("sidepod_inlet", r0[:, :2], slot, z0, 0.10, "red", wall_mat="red", both=True)
# inlet surround lip
lip = tube([(0.25, 0.575, 0.895), (0.40, 0.578, 0.905), (0.54, 0.560, 0.895)], r=0.014, sides=8)
# (inlet lip removed: smooth pod edge reads better)

# ---------------- floor (planform with edge, cut-outs ahead of rear tyres) + diffuser
floor_pts = [(0.0, 1.00), (0.28, 0.95), (0.55, 0.78), (0.72, 0.62), (0.80, 0.40), (0.82, -0.55),
             (0.80, -1.00), (0.66, -1.22), (0.56, -1.32), (0.52, -1.90), (0.0, -1.90)]
fp = [(x, z) for x, z in floor_pts] + [(-x, z) for x, z in floor_pts[::-1][1:-1]]
add("floor", extrude_xz(fp, 0.035, 0.055), "carbon")
edge = tube([(0.80, 0.07, 0.40), (0.825, 0.075, -0.20), (0.815, 0.08, -0.80), (0.70, 0.08, -1.15)],
            r=0.03, sides=8, flat=0.35)
add("floor_edge", edge, "carbon", both=True)
# diffuser: inclined roof + strakes
diff = extrude_zy([(-1.40, 0.055), (-1.90, 0.055), (-2.07, 0.27), (-1.90, 0.27)], -0.50, 0.50)
add("diffuser", diff, "carbon")
for x in (0.18, 0.36, 0.50):
    add(f"diff_strake{int(x*100)}", extrude_zy([(-1.45, 0.04), (-2.05, 0.04), (-2.07, 0.28), (-1.90, 0.27)],
                                               x - 0.006, x + 0.006), "carbon", both=True)

# ---------------- front wing (4 elements, curling up outboard) + endplates + nose join
SPAN = np.concatenate([-np.linspace(0.90, 0, 16)[:-1], np.linspace(0, 0.90, 16)])
def fw_element(y0, rise, zle, sweep, chord, ang, ang_out, ch_out=0.0):
    return wing(SPAN,
                y_of=lambda x: y0 + rise * smooth01(0.30, 0.90, abs(x)),
                zle_of=lambda x: zle - 0.03 * smooth01(0.20, 0.90, abs(x)),
                chord_of=lambda x: chord + ch_out * smooth01(0.35, 0.9, abs(x)),
                ang_of=lambda x: ang + (ang_out - ang) * smooth01(0.30, 0.90, abs(x)),
                thick=0.12)
add("fw_element1", fw_element(0.070, 0.015, 2.58, 0.12, 0.30, 3, 6), "white")
add("fw_element2", fw_element(0.110, 0.035, 2.33, 0.12, 0.15, 14, 20), "white")
for k, args in (("3", (0.140, 0.065, 2.24, 0.12, 0.13, 22, 32, 0.02)),
                ("4", (0.170, 0.095, 2.16, 0.12, 0.11, 30, 42, 0.03))):
    e = fw_element(*args)
    outb = np.abs(e.triangles_center[:, 0]) > 0.30
    add(f"fw_element{k}_outer", submesh(e, outb), "navy")
    add(f"fw_element{k}_inner", submesh(e, ~outb), "white")
ep = rounded_rect(2.20, 2.60, 0.03, 0.25, r_tf=0.13, r_tr=0.04, r_bf=0.03)
add("fw_endplate", extrude_zy(ep, 0.895, 0.913), "white", both=True)
add("fw_footplate", extrude_xz([(0.78, 2.60), (0.913, 2.60), (0.913, 2.20), (0.78, 2.24)], 0.03, 0.045), "white", both=True)

# ---------------- airbox / roll hoop + engine cover spine + fin + T-cam
AB = [(-0.08, 0, 0.560, 1.010, 0.150), (-0.30, 0, 0.570, 1.025, 0.160), (-0.62, 0, 0.560, 0.950, 0.135),
      (-1.00, 0, 0.520, 0.800, 0.095), (-1.45, 0, 0.420, 0.640, 0.065), (-1.85, 0, 0.330, 0.480, 0.040)]
ab_rings = body_rings(AB, n=40, sub=6, p=2.4, taper=0.35)
ab = loft_rings(ab_rings, cap_front=False)
zc = ab.triangles_center[:, 2]
add("airbox_head", submesh(ab, zc > -0.62), "navy")
add("airbox_spine", submesh(ab, zc <= -0.62), "red")
ab_slot_ring = body_rings([(0, 0, 0.775, 0.990, 0.118), (-0.1, 0, 0.775, 0.990, 0.118)], n=64, sub=1, p=2.4, taper=0.35)[0]
ab_slot = sg.polygon.orient(sg.Polygon(ab_slot_ring[:, :2]), 1.0)
recessed_inlet("airbox_inlet", ab_rings[0][:, :2], ab_slot, ab_rings[0][0, 2], 0.11, "navy", wall_mat="navy")
fin = extrude_zy([(-0.75, 0.86), (-1.90, 0.52), (-1.99, 0.52), (-1.95, 0.76), (-1.0, 0.95)], -0.006, 0.006)
add("shark_fin", fin, "red")
add("tcam", trimesh.creation.box((0.16, 0.035, 0.05)).apply_translation((0, 1.045, -0.22)), "camera")
add("tcam_post", trimesh.creation.box((0.03, 0.03, 0.03)).apply_translation((0, 1.02, -0.22)), "carbon")

# ---------------- halo
def halo_pts():
    c = np.array([0, 0.835, 0.10]); rx, rz = 0.265, 0.30
    pts = [(0, 0.585, 0.66), (0, 0.700, 0.585), (0, 0.790, 0.495)]
    for th in np.linspace(0, 100, 8):
        a = np.radians(th)
        pts.append(c + [rx * np.sin(a), 0, rz * np.cos(a)])
    # tail sweeps back and inward, disappearing into the side of the airbox (no legs to the body)
    pts += [(0.235, 0.836, -0.085), (0.195, 0.836, -0.150), (0.150, 0.834, -0.215), (0.110, 0.832, -0.290)]
    return pts
def oval_tube(points, r_wide, r_thin, sides=28, sub=10):
    pts = catmull(points, sub)
    T = np.gradient(pts, axis=0); T /= np.linalg.norm(T, axis=1, keepdims=True)
    ang = np.linspace(0, 2 * np.pi, sides, endpoint=False)
    rings = []
    for p, t in zip(pts, T):
        a = abs(t[1]) ** 2                             # 0 on the hoop, ~1 on the pillar
        w = (1 - a) * np.array([0, 1, 0]) + a * np.array([0, 0, 1])
        thin = w - np.dot(w, t) * t; thin /= np.linalg.norm(thin)
        wide = np.cross(t, thin)
        rings.append(p + np.outer(np.cos(ang) * r_wide, wide) + np.outer(np.sin(ang) * r_thin, thin))
    return loft_rings(rings)
_hp = np.array(halo_pts()[3:], float)                       # hoop + tail (one side), starts at front centre
_hoop = np.vstack([(_hp * [-1, 1, 1])[::-1], _hp[1:]])       # one continuous hoop: left tail -> front -> right tail
add("halo_hoop", oval_tube(_hoop, r_wide=0.070, r_thin=0.033), "carbon")
add("halo_pillar", oval_tube([(0, 0.585, 0.66), (0, 0.700, 0.585), (0, 0.790, 0.495), (0, 0.818, 0.440), (0, 0.832, 0.405)],
                             r_wide=0.068, r_thin=0.036), "carbon")

# ---------------- mirrors (on stalks off the chassis, ahead of sidepods)
mir = body_loft([(0.80, 0.47, 0.705, 0.775, 0.085), (0.72, 0.47, 0.700, 0.780, 0.090)], n=20, sub=1, p=3)
add("mirror", mir, "navy", both=True)
add("mirror_glass", body_loft([(0.715, 0.47, 0.708, 0.772, 0.075), (0.712, 0.47, 0.708, 0.772, 0.075)], n=20, sub=1, p=3), "visor", both=True)
add("mirror_stalk", rod((0.27, 0.60, 0.76), (0.44, 0.72, 0.76), 0.012, 0.6), "carbon", both=True)
add("mirror_stalk2", rod((0.47, 0.585, 0.72), (0.47, 0.705, 0.75), 0.010, 0.6), "carbon", both=True)

# ---------------- rear wing: spoon mainplane + DRS flap curling into rounded tips, swan-neck pylon, beam wing
RS = np.concatenate([-np.linspace(0.50, 0, 16)[:-1], np.linspace(0, 0.50, 16)])
def rw(y0, zle, chord, ang, drop):
    return wing(RS,
                y_of=lambda x: y0 - drop * smooth01(0.30, 0.50, abs(x)) ** 1.5,
                zle_of=lambda x: zle + 0.05 * smooth01(0.28, 0.5, abs(x)),
                chord_of=lambda x: chord,
                ang_of=lambda x: ang,
                thick=0.14)
add("rw_mainplane", rw(0.86, -2.02, 0.33, 8, 0.10), "white")
add("rw_flap", rw(0.96, -2.30, 0.20, 32, 0.12), "white")
rep = rounded_rect(-2.56, -2.0, 0.40, 1.03, r_tf=0.22, r_tr=0.08, r_bf=0.10, r_br=0.05)
add("rw_endplate", extrude_zy(rep, 0.488, 0.506), "white", both=True)
add("beam_wing", wing(np.linspace(-0.42, 0.42, 9), lambda x: 0.34, lambda x: -2.04, lambda x: 0.16,
                      lambda x: 14, thick=0.10), "carbon")
add("beam_wing2", wing(np.linspace(-0.42, 0.42, 9), lambda x: 0.40, lambda x: -2.21, lambda x: 0.12,
                       lambda x: 30, thick=0.10), "carbon")
pylon = extrude_zy([(-1.92, 0.36), (-2.04, 0.36), (-2.16, 0.95), (-2.06, 0.98), (-1.99, 0.70)], -0.012, 0.012)
add("rw_pylon", pylon, "carbon")
RL_C = np.array([0.0, 0.205, -2.135])            # centre of the light face (faces -Z, backwards)
add("rain_light_housing", trimesh.creation.box((0.110, 0.165, 0.050)).apply_translation(RL_C + [0, 0, 0.022]), "carbon")
add("rain_light_mount", trimesh.creation.box((0.050, 0.040, 0.060)).apply_translation(RL_C + [0, 0.095, 0.045]), "carbon")
add("rain_light_lens", trimesh.creation.box((0.092, 0.145, 0.006)).apply_translation(RL_C + [0, 0, -0.004]), "lens")
def led_grid(dz):
    out = []
    for i in range(5):
        for j in range(3):
            led = trimesh.creation.cylinder(radius=0.0115, height=0.006, sections=20)
            led.apply_translation(RL_C + [(j - 1) * 0.027, (2 - i) * 0.026, dz])
            out.append(led)
    return trimesh.util.concatenate(out)
# "off" LEDs are always there; the glowing "on" set sits just in front of them.
# In the game toggle the visibility of the node `rain_light_leds_on` to switch the light.
add("rain_light_leds_off", led_grid(-0.008), "led_off")
import os
if os.environ.get("BRAKE_LIGHT", "on") == "on":
    add("rain_light_leds_on", led_grid(-0.0105), "led")

# ---------------- suspension
def susp(axz, hubx, ch_pts, up_y, lo_y, ch_up, ch_lo, front=True):
    hub_up = (hubx, up_y, axz)
    hub_lo = (hubx, lo_y, axz)
    out = []
    for cy, hub in ((ch_up, hub_up), (ch_lo, hub_lo)):
        for dz in ch_pts:
            out.append(rod((0.16 if front else 0.12, cy, axz + dz), hub, 0.018))
    # pushrod/pullrod and track rod
    out.append(rod(hub_lo, (0.15 if front else 0.10, ch_up + 0.06, axz + (0.05 if front else -0.05)), 0.014))
    out.append(rod((hubx - 0.02, (up_y + lo_y) / 2, axz + (0.10 if front else -0.10)),
                   (0.16 if front else 0.12, (ch_up + ch_lo) / 2, axz + (0.12 if front else -0.12)), 0.012))
    return out

for i, m in enumerate(susp(FRONT_Z, FRONT_X - FRONT_W / 2 - 0.05, (0.26, -0.24), 0.50, 0.22, 0.44, 0.20)):
    add(f"susp_front{i}", m, "carbon", both=True)
for i, m in enumerate(susp(REAR_Z, REAR_X - REAR_W / 2 - 0.05, (0.20, -0.22), 0.52, 0.22, 0.40, 0.20, front=False)):
    add(f"susp_rear{i}", m, "carbon", both=True)
add("driveshaft", rod((0.08, 0.37, REAR_Z), (REAR_X - REAR_W / 2 - 0.04, 0.37, REAR_Z), 0.022, 1.0), "carbon", both=True)

# ---------------- wheels (local to hub)
def wheel(width, rim_r=0.235, outer_sign=1):
    hw = width / 2
    R = TYRE_R
    sh = 0.065                                   # shoulder radius
    prof = [(rim_r - 0.005, -hw + 0.02)]
    prof += [(rim_r + 0.02, -hw)]
    a = np.linspace(np.pi, np.pi / 2, 7)
    prof += [(R - sh + sh * np.sin(t), -hw + sh - sh * np.cos(t) * -1 * -1) for t in a][0:0]
    # sidewall bulge -> shoulder -> tread -> shoulder -> sidewall
    for t in np.linspace(0, np.pi / 2, 7):
        prof.append((R - sh + sh * np.sin(t), -hw + sh - sh * np.cos(t)))
    for t in np.linspace(np.pi / 2, np.pi, 7)[1:]:
        prof.append((R - sh + sh * np.sin(t), hw - sh - sh * np.cos(t)))
    prof += [(rim_r + 0.02, hw), (rim_r - 0.005, hw - 0.02)]
    tyre = lathe(prof, 72)
    tyre.faces = tyre.faces  # outward by fix_normals
    s_out = outer_sign * (hw + 0.003)
    stripe = lathe([(0.300, s_out), (0.318, s_out)], 72)
    stripe2 = lathe([(0.300, -s_out), (0.318, -s_out)], 72)
    rim = lathe([(rim_r - 0.004, -hw + 0.02), (rim_r - 0.004, hw - 0.02)], 64)
    lip = lathe([(rim_r - 0.004, outer_sign * (hw - 0.02)), (rim_r - 0.025, outer_sign * (hw - 0.025))], 64)
    cover = lathe([(rim_r - 0.025, outer_sign * (hw - 0.03)), (0.07, outer_sign * (hw - 0.045)),
                   (0.045, outer_sign * (hw - 0.03)), (0.0, outer_sign * (hw - 0.03))], 64)
    inner = lathe([(rim_r - 0.01, -outer_sign * (hw - 0.03)), (0.0, -outer_sign * (hw - 0.05))], 48)
    drum = trimesh.creation.cylinder(radius=0.17, height=0.12, sections=32)
    drum.apply_transform(trimesh.transformations.rotation_matrix(np.pi / 2, [0, 1, 0]))
    drum.apply_translation([-outer_sign * (hw + 0.02), 0, 0])
    def face(m, sx):          # make disc-like part face toward +sx along X
        if (m.face_normals[:, 0] * m.area_faces).sum() * sx < 0:
            m.invert()
        return m
    def inward(m):            # barrel normals toward the axle
        rc = m.triangles_center[:, 1:]; nn = m.face_normals[:, 1:]
        if ((rc * nn).sum(1) * m.area_faces).sum() > 0:
            m.invert()
        return m
    stripe, stripe2 = face(stripe, outer_sign), face(stripe2, -outer_sign)
    lip, cover, inner = face(lip, outer_sign), face(cover, outer_sign), face(inner, -outer_sign)
    rim = inward(rim)
    return [("tyre", tyre, "tyre"), ("stripe_out", stripe, "stripe"), ("stripe_in", stripe2, "stripe"),
            ("rim", rim, "rim"), ("rim_lip", lip, "rim"), ("cover", cover, "rim"),
            ("inner", inner, "carbon"), ("brake_drum", drum, "carbon")]

wheels = {}
for key, (az, wdt, wx) in {"F": (FRONT_Z, FRONT_W, FRONT_X), "R": (REAR_Z, REAR_W, REAR_X)}.items():
    for sx, side in ((1, "L"), (-1, "R")):
        wheels[f"wheel_{key}{side}"] = ((sx * wx, TYRE_R, az), wheel(wdt, outer_sign=sx))

# ------------------------------------------------------------------ assemble
def pbr(mat):
    d = MAT[mat]
    return PBRMaterial(name=mat, baseColorFactor=[*d["c"], 1.0],
                       metallicFactor=d["m"], roughnessFactor=d["r"],
                       emissiveFactor=list(d["e"]) if "e" in d else None)

def finalize(mesh, mat):
    mesh = trimesh.Trimesh(mesh.vertices, mesh.faces, process=True)
    mesh = trimesh.graph.smooth_shade(mesh, angle=np.radians(38))
    mesh.visual = trimesh.visual.TextureVisuals(material=pbr(mat))
    return mesh

KZ = 0.74          # toy look: squash body length
FW_SHIFT = 0.02    # keep front wing clear of the big front tyres
BODY_LIFT = 0.0
KX, KY = 1.10, 1.18  # chunkier, taller body


def build_scene():
    scene = trimesh.Scene()
    scene.graph.update(frame_to="car", frame_from=scene.graph.base_frame)
    scene.graph.update(frame_to="body", frame_from="car")
    for name, m, mat in parts:
        m = m.copy()
        m.apply_transform(np.diag([KX, KY, KZ, 1]))
        if name.startswith("fw_"):
            m.apply_translation([0, 0, FW_SHIFT])
        m.apply_translation([0, BODY_LIFT, 0])
        scene.add_geometry(finalize(m, mat), node_name=name, geom_name=name, parent_node_name="body")
    for wname, (pos, wp) in wheels.items():
        scene.graph.update(frame_to=wname, frame_from="car",
                           matrix=trimesh.transformations.translation_matrix((pos[0], pos[1], pos[2] * KZ)))
        for pname, m, mat in wp:
            nm = f"{wname}_{pname}"
            scene.add_geometry(finalize(m, mat), node_name=nm, geom_name=nm, parent_node_name=wname)
    return scene

if __name__ == "__main__":
    import sys
    out = sys.argv[1] if len(sys.argv) > 1 else "out"
    sc = build_scene()
    sc.export(f"{out}/race_car.glb")
    print("bounds", sc.bounds.round(3), "tris", sum(len(g.faces) for g in sc.geometry.values()))

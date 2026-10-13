"""Tiny numpy z-buffer renderer for previews."""
import sys
import numpy as np
import trimesh
from PIL import Image

def look_at(eye, target, up=(0, 1, 0)):
    eye, target, up = map(lambda v: np.array(v, float), (eye, target, up))
    f = target - eye; f /= np.linalg.norm(f)
    r = np.cross(f, up); r /= np.linalg.norm(r)
    u = np.cross(r, f)
    return eye, r, u, f

def render(meshes, eye, target, W=1200, H=800, fov=32, ss=2, bg=(46, 64, 108)):
    W2, H2 = W * ss, H * ss
    eye, r, u, f = look_at(eye, target)
    focal = (H2 / 2) / np.tan(np.radians(fov) / 2)
    img = np.zeros((H2, W2, 3), float); img[:] = np.array(bg) / 255
    zb = np.full((H2, W2), np.inf)
    light = np.array([0.4, 0.85, 0.35]); light /= np.linalg.norm(light)
    # ground shadow-ish disc
    for mesh, col in meshes:
        v = mesh.vertices - eye
        cam = np.stack([v @ r, v @ u, v @ f], 1)
        px = W2 / 2 + focal * cam[:, 0] / cam[:, 2]
        py = H2 / 2 - focal * cam[:, 1] / cam[:, 2]
        n = mesh.vertex_normals
        for tri in mesh.faces:
            z = cam[tri, 2]
            if (z <= 0.05).any():
                continue
            xs, ys = px[tri], py[tri]
            x0, x1 = int(max(xs.min(), 0)), int(min(xs.max() + 1, W2))
            y0, y1 = int(max(ys.min(), 0)), int(min(ys.max() + 1, H2))
            if x0 >= x1 or y0 >= y1:
                continue
            gx, gy = np.meshgrid(np.arange(x0, x1) + 0.5, np.arange(y0, y1) + 0.5)
            (ax, bx, cx), (ay, by, cy) = xs, ys
            den = (by - cy) * (ax - cx) + (cx - bx) * (ay - cy)
            if abs(den) < 1e-9:
                continue
            w0 = ((by - cy) * (gx - cx) + (cx - bx) * (gy - cy)) / den
            w1 = ((cy - ay) * (gx - cx) + (ax - cx) * (gy - cy)) / den
            w2 = 1 - w0 - w1
            ins = (w0 >= 0) & (w1 >= 0) & (w2 >= 0)
            if not ins.any():
                continue
            zz = 1 / (w0 / z[0] + w1 / z[1] + w2 / z[2])
            sub = zb[y0:y1, x0:x1]
            upd = ins & (zz < sub)
            if not upd.any():
                continue
            nn = (w0[..., None] * n[tri[0]] + w1[..., None] * n[tri[1]] + w2[..., None] * n[tri[2]])
            nn /= np.linalg.norm(nn, axis=-1, keepdims=True) + 1e-9
            if (nn @ (-f)).mean() < 0 and False:
                pass
            diff = np.clip(nn @ light, 0, 1)
            vdir = -f
            h = light + vdir; h /= np.linalg.norm(h)
            spec = np.clip(nn @ h, 0, 1) ** 40 * 0.35
            rim = (1 - np.abs(nn @ vdir)) ** 3 * 0.15
            shade = 0.32 + 0.68 * diff
            if getattr(mesh, "metadata", {}).get("emissive"):
                shade = np.full_like(shade, 1.15); spec = spec * 0
            c = np.clip(col * shade[..., None] + (spec + rim)[..., None], 0, 1)
            sub[upd] = zz[upd]
            img[y0:y1, x0:x1][upd] = c[upd]
    im = Image.fromarray((img * 255).astype(np.uint8))
    return im.resize((W, H), Image.LANCZOS)

def scene_meshes(path):
    sc = trimesh.load(path)
    out = []
    for node in sc.graph.nodes_geometry:
        T, gname = sc.graph[node]
        g = sc.geometry[gname].copy(); g.apply_transform(T)
        col = np.array(g.visual.material.baseColorFactor[:3], float)
        if col.max() > 1: col = col / 255
        if getattr(g.visual.material, "emissiveFactor", None) is not None and np.max(g.visual.material.emissiveFactor) > 0:
            g.metadata["emissive"] = True
        out.append((g, col))
    return out

if __name__ == "__main__":
    glb, outp = sys.argv[1], sys.argv[2]
    ms = scene_meshes(glb)
    a = render(ms, (-3.3, 2.1, 5.6), (0.1, 0.25, -0.05), W=940, H=576, fov=33)
    b = render(ms, (-4.0, 5.6, -7.4), (0.25, 0.3, -0.2), W=592, H=462, fov=24)
    ref1 = Image.open(sys.argv[3]).convert("RGB").resize((940, 576))
    ref2 = Image.open(sys.argv[4]).convert("RGB").resize((592, 462))
    sheet = Image.new("RGB", (940 + 592, 576 + 462), (30, 30, 30))
    sheet.paste(ref1, (0, 0)); sheet.paste(a, (0, 576))
    sheet.paste(ref2, (940, 0)); sheet.paste(b, (940, 576))
    sheet.save(outp)
    if len(sys.argv) > 5:
        top = render(ms, (0.01, 10, 0.2), (0, 0, 0), W=700, H=700, fov=36)
        side = render(ms, (-9, 0.45, 0.0), (0, 0.45, 0.0), W=1000, H=300, fov=36)
        top.save(sys.argv[5] + "_top.png"); side.save(sys.argv[5] + "_side.png")

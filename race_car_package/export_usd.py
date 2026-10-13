"""Export race_car.glb hierarchy to USDZ (RealityKit / AR Quick Look) and OBJ."""
import sys
import numpy as np
import trimesh
from pxr import Usd, UsdGeom, UsdShade, Sdf, Gf, UsdUtils

out = sys.argv[1]
sc = trimesh.load(f"{out}/race_car.glb")

usda = f"{out}/race_car.usdc"
stage = Usd.Stage.CreateNew(usda)
UsdGeom.SetStageUpAxis(stage, UsdGeom.Tokens.y)
UsdGeom.SetStageMetersPerUnit(stage, 1.0)
root = UsdGeom.Xform.Define(stage, "/car")
stage.SetDefaultPrim(root.GetPrim())

mats = {}
def material(m):
    name = m.name or "mat"
    if name in mats:
        return mats[name]
    path = f"/car/Materials/{name}"
    mat = UsdShade.Material.Define(stage, path)
    sh = UsdShade.Shader.Define(stage, path + "/PBR")
    sh.CreateIdAttr("UsdPreviewSurface")
    c = np.array(m.baseColorFactor[:3], float)
    if c.max() > 1: c /= 255
    sh.CreateInput("diffuseColor", Sdf.ValueTypeNames.Color3f).Set(Gf.Vec3f(*c))
    sh.CreateInput("metallic", Sdf.ValueTypeNames.Float).Set(float(m.metallicFactor or 0))
    sh.CreateInput("roughness", Sdf.ValueTypeNames.Float).Set(float(m.roughnessFactor or 0.5))
    if getattr(m, "emissiveFactor", None) is not None and np.max(m.emissiveFactor) > 0:
        e = np.array(m.emissiveFactor[:3], float)
        sh.CreateInput("emissiveColor", Sdf.ValueTypeNames.Color3f).Set(Gf.Vec3f(*e))
    mat.CreateSurfaceOutput().ConnectToSource(sh.ConnectableAPI(), "surface")
    mats[name] = mat
    return mat

# build xform hierarchy following glTF graph
G = sc.graph
paths = {G.base_frame: None}
def prim_path(node):
    if node in paths and paths[node]:
        return paths[node]
    parent = G.transforms.parents.get(node)
    if parent is None or parent == G.base_frame:
        p = "/car" if node == "car" else f"/car/{node}"
    else:
        p = f"{prim_path(parent)}/{node}"
    paths[node] = p
    return p

for node in G.nodes:
    if node == G.base_frame:
        continue
    p = prim_path(node)
    parent = G.transforms.parents.get(node)
    local = G.transforms.edge_data.get((parent, node), {}).get("matrix")
    gname = G.transforms.node_data.get(node, {}).get("geometry")
    if gname:
        g = sc.geometry[gname]
        mesh = UsdGeom.Mesh.Define(stage, p)
        mesh.CreatePointsAttr([Gf.Vec3f(*v) for v in g.vertices])
        mesh.CreateFaceVertexCountsAttr([3] * len(g.faces))
        mesh.CreateFaceVertexIndicesAttr(g.faces.flatten().tolist())
        mesh.CreateNormalsAttr([Gf.Vec3f(*n) for n in g.vertex_normals])
        mesh.SetNormalsInterpolation(UsdGeom.Tokens.vertex)
        mesh.CreateSubdivisionSchemeAttr(UsdGeom.Tokens.none)
        mesh.CreateExtentAttr([Gf.Vec3f(*g.bounds[0]), Gf.Vec3f(*g.bounds[1])])
        UsdShade.MaterialBindingAPI.Apply(mesh.GetPrim()).Bind(material(g.visual.material))
        xf = mesh
    elif p != "/car":
        xf = UsdGeom.Xform.Define(stage, p)
    else:
        continue
    if local is not None and not np.allclose(local, np.eye(4)):
        xf.AddTransformOp().Set(Gf.Matrix4d(np.array(local).T.tolist()))

stage.GetRootLayer().Save()
UsdUtils.CreateNewARKitUsdzPackage(usda, f"{out}/race_car.usdz")
sc.export(f"{out}/race_car.obj")
print("ok", len(mats), "materials")

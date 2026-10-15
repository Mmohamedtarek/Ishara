"""
Base holder (anchor) for the connector end of a flex sensor on the Ishara glove. Units: mm.
X = across the hand, Y = along the sensor, Z = height.

  body:    10 (W) x 20 (L) x 5.5 (H), rounded corners, chamfered top
  pocket:  7.5 x 3.2 through the whole length, centred, for the sensor's end, the 2 crimp pins,
           the solder joints and heat shrink; 0.3 mm flared entries at both ends
  sewing:  no holes (the 1.25 mm side walls have no room); sew over the body, see the README
"""
import sys
import numpy as np
import trimesh
from manifold3d import CrossSection, Manifold

W, L, H = 10.0, 20.0, 5.5
CORNER_R, TOP_CHAMFER = 0.5, 0.6
POCKET_W, POCKET_H = 7.5, 3.2
POCKET_Z = (H - POCKET_H) / 2
FLARE, FLARE_D = 0.3, 0.8
HOLE_D = 1.2


def rrect(w, l, r):
    return CrossSection.square([w - 2 * r, l - 2 * r], center=True).offset(r, join_type=1, circular_segments=48)


def box(x0, x1, y0, y1, z0, z1):
    x0, x1 = sorted((x0, x1)); y0, y1 = sorted((y0, y1)); z0, z1 = sorted((z0, z1))
    return Manifold.cube([x1 - x0, y1 - y0, z1 - z0]).translate([x0, y0, z0])


def body():
    lower = Manifold.extrude(rrect(W, L, CORNER_R), H - TOP_CHAMFER)
    top = Manifold.extrude(rrect(W - 2 * TOP_CHAMFER, L - 2 * TOP_CHAMFER, CORNER_R - TOP_CHAMFER / 2), 0.01) \
        .translate([0, 0, H - 0.01])
    return Manifold.batch_hull([lower, top])


def pocket():
    z0, z1 = POCKET_Z, POCKET_Z + POCKET_H
    c = box(-POCKET_W / 2, POCKET_W / 2, -L / 2 - 1, L / 2 + 1, z0, z1)
    for sign in (-1, 1):
        face = sign * L / 2
        outer = box(-POCKET_W / 2 - FLARE, POCKET_W / 2 + FLARE, face - 0.005, face + 0.005, z0 - FLARE, z1 + FLARE)
        inner = box(-POCKET_W / 2, POCKET_W / 2, face - sign * FLARE_D - 0.005, face - sign * FLARE_D + 0.005, z0, z1)
        cap = box(-POCKET_W / 2 - FLARE, POCKET_W / 2 + FLARE, face, face + sign * 1.0, z0 - FLARE, z1 + FLARE)
        c = c + Manifold.batch_hull([outer, inner]) + cap
    return c



def save(m, path):
    assert m.status().name == "NoError", m.status()
    mesh = m.to_mesh()
    t = trimesh.Trimesh(vertices=np.asarray(mesh.vert_properties)[:, :3], faces=np.asarray(mesh.tri_verts), process=True)
    t.merge_vertices(); t.remove_unreferenced_vertices()
    assert t.is_watertight and t.is_winding_consistent, path
    t.export(path)
    return t


if __name__ == "__main__":
    out = sys.argv[1] if len(sys.argv) > 1 else "."
    name = f"{out}/ishara_flex_anchor_10x20x5.5.stl"
    t = save(body() - pocket(), name)
    print(name, "size", np.round(t.bounds[1] - t.bounds[0], 2), "volume", round(t.volume, 1), "mm3")

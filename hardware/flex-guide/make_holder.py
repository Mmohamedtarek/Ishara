"""
Flex sensor guide for the Ishara glove (one piece per guide on the back of a finger).
Units: mm.  X = across the finger, Y = along the finger (sensor direction), Z = height.

  outside: 14 (W) x L x 4 (H), rounded corners, chamfered top
  slot:    7.0 x 1.0 through the whole length (the flex sensor is 6.35 x 0.43 mm, so it slides freely)
           centred in X, floor 1.5 mm under it, roof 1.5 mm over it; 0.5 mm flared entries so the
           sensor's edges never rub on a sharp corner
  holes:   4 x 1.2 mm vertical holes in the side walls, for sewing it to the glove (optional)
"""
import sys
import numpy as np
import trimesh
from manifold3d import CrossSection, Manifold

W, H = 14.0, 4.0
SLOT_W, SLOT_H, SLOT_Z = 7.0, 1.0, 1.5      # slot floor at z = 1.5
FLARE, FLARE_D = 0.5, 0.8                   # entry flare: 0.5 mm wider/higher at the face, over 0.8 mm
CORNER_R, TOP_CHAMFER = 1.5, 0.6
HOLE_D = 1.2


def rrect(w, l, r):
    return CrossSection.square([w - 2 * r, l - 2 * r], center=True).offset(r, join_type=1, circular_segments=48)


def body(L):
    lower = Manifold.extrude(rrect(W, L, CORNER_R), H - TOP_CHAMFER)
    top = Manifold.extrude(rrect(W - 2 * TOP_CHAMFER, L - 2 * TOP_CHAMFER, CORNER_R - TOP_CHAMFER / 2), 0.01) \
        .translate([0, 0, H - 0.01])
    return Manifold.batch_hull([lower, top])


def box(x0, x1, y0, y1, z0, z1):
    x0, x1 = sorted((x0, x1)); y0, y1 = sorted((y0, y1)); z0, z1 = sorted((z0, z1))
    return Manifold.cube([x1 - x0, y1 - y0, z1 - z0]).translate([x0, y0, z0])


def slot(L):
    s = box(-SLOT_W / 2, SLOT_W / 2, -L / 2 - 1, L / 2 + 1, SLOT_Z, SLOT_Z + SLOT_H)
    for sign in (-1, 1):
        face = sign * L / 2
        outer = box(-SLOT_W / 2 - FLARE, SLOT_W / 2 + FLARE, face - 0.005, face + 0.005,
                    SLOT_Z - FLARE, SLOT_Z + SLOT_H + FLARE)
        inner = box(-SLOT_W / 2, SLOT_W / 2, face - sign * FLARE_D - 0.005, face - sign * FLARE_D + 0.005,
                    SLOT_Z, SLOT_Z + SLOT_H)
        cap = box(-SLOT_W / 2 - FLARE, SLOT_W / 2 + FLARE, face, face + sign * 1.0,
                  SLOT_Z - FLARE, SLOT_Z + SLOT_H + FLARE)
        s = s + Manifold.batch_hull([outer, inner]) + cap
    return s


def holes(L):
    out = Manifold()
    x = (W / 2 + SLOT_W / 2) / 2                        # middle of each side wall
    for sx in (-1, 1):
        for sy in (-1, 1):
            c = Manifold.cylinder(H + 2, HOLE_D / 2, HOLE_D / 2, 32).translate([sx * x, sy * (L / 2 - 2.5), -1])
            out = out + c
    return out


def make(L, with_holes):
    m = body(L) - slot(L)
    if with_holes:
        m = m - holes(L)
    return m


def save(m, path):
    mesh = m.to_mesh()
    t = trimesh.Trimesh(vertices=np.asarray(mesh.vert_properties)[:, :3], faces=np.asarray(mesh.tri_verts), process=True)
    t.merge_vertices(); t.remove_unreferenced_vertices()
    assert m.status().name == "NoError", m.status()
    assert t.is_watertight and t.is_winding_consistent, path
    t.export(path)
    return t


if __name__ == "__main__":
    out = sys.argv[1] if len(sys.argv) > 1 else "."
    for L in (12.0,):
        for holes_on in (True, False):
            name = f"{out}/ishara_flex_guide_14x{int(L)}x4{'_sew' if holes_on else ''}.stl"
            t = save(make(L, holes_on), name)
            b = t.bounds
            print(name, "size", np.round(b[1] - b[0], 2), "volume", round(t.volume, 1), "mm3", "watertight", t.is_watertight)

"""
Base holder (anchor) for the connector end of a flex sensor on the Ishara glove. Units: mm.
X = across the hand, Y = along the sensor (finger side at -Y, wires leave at +Y), Z = height.

  body:    14 (W) x 20 (L) x 5.5 (H), rounded, chamfered top, on a 24 x 16 x 1.5 sewing flange
  slot:    7.0 x 1.0 for the sensor's stiff end, y = -10 .. -2, floor at z = 1.5, flared entry
  pocket:  9.0 x 3.2 for the 2 crimp pins, the solder joints and heat shrink, y = -2 .. +10,
           open at the back so the wires leave
  window:  6 x 7 opening in the roof over the pocket, to check the joints and fill with hot glue
  holes:   4 x 1.2 mm in the flange, for sewing it to the glove
"""
import sys
import numpy as np
import trimesh
from manifold3d import CrossSection, Manifold

W, L, H = 14.0, 20.0, 5.5
CORNER_R, TOP_CHAMFER = 1.5, 0.6
FL_W, FL_L, FL_H, FL_R = 24.0, 16.0, 1.5, 3.0
SLOT_W, SLOT_H, SLOT_Z = 7.0, 1.0, 1.5
SPLIT_Y = -2.0                                   # slot ends, pocket starts
POCKET_W, POCKET_Z0, POCKET_Z1 = 9.0, 1.0, 4.2
WIN_W, WIN_Y0, WIN_Y1 = 6.0, 0.0, 7.0
FLARE, FLARE_D = 0.5, 0.8
HOLE_D, HOLE_X, HOLE_Y = 1.2, 9.5, 5.0


def rrect(w, l, r):
    return CrossSection.square([w - 2 * r, l - 2 * r], center=True).offset(r, join_type=1, circular_segments=48)


def box(x0, x1, y0, y1, z0, z1):
    x0, x1 = sorted((x0, x1)); y0, y1 = sorted((y0, y1)); z0, z1 = sorted((z0, z1))
    return Manifold.cube([x1 - x0, y1 - y0, z1 - z0]).translate([x0, y0, z0])


def body():
    lower = Manifold.extrude(rrect(W, L, CORNER_R), H - TOP_CHAMFER)
    top = Manifold.extrude(rrect(W - 2 * TOP_CHAMFER, L - 2 * TOP_CHAMFER, CORNER_R - TOP_CHAMFER / 2), 0.01) \
        .translate([0, 0, H - 0.01])
    flange = Manifold.extrude(rrect(FL_W, FL_L, FL_R), FL_H)
    return Manifold.batch_hull([lower, top]) + flange


def cuts():
    face = -L / 2
    c = box(-SLOT_W / 2, SLOT_W / 2, face - 1, SPLIT_Y + 0.5, SLOT_Z, SLOT_Z + SLOT_H)
    outer = box(-SLOT_W / 2 - FLARE, SLOT_W / 2 + FLARE, face - 0.005, face + 0.005,
                SLOT_Z - FLARE, SLOT_Z + SLOT_H + FLARE)
    inner = box(-SLOT_W / 2, SLOT_W / 2, face + FLARE_D - 0.005, face + FLARE_D + 0.005,
                SLOT_Z, SLOT_Z + SLOT_H)
    c = c + Manifold.batch_hull([outer, inner]) + box(-SLOT_W / 2 - FLARE, SLOT_W / 2 + FLARE, face, face - 1,
                                                      SLOT_Z - FLARE, SLOT_Z + SLOT_H + FLARE)
    c = c + box(-POCKET_W / 2, POCKET_W / 2, SPLIT_Y, L / 2 + 1, POCKET_Z0, POCKET_Z1)
    c = c + box(-WIN_W / 2, WIN_W / 2, WIN_Y0, WIN_Y1, POCKET_Z1 - 0.1, H + 1)
    for sx in (-1, 1):
        for sy in (-1, 1):
            c = c + Manifold.cylinder(FL_H + 2, HOLE_D / 2, HOLE_D / 2, 32).translate([sx * HOLE_X, sy * HOLE_Y, -1])
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
    name = f"{out}/ishara_flex_anchor_14x20x5.5.stl"
    t = save(body() - cuts(), name)
    print(name, "size", np.round(t.bounds[1] - t.bounds[0], 2), "volume", round(t.volume, 1), "mm3")

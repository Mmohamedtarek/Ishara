# Flex sensor guide

A 3D-printed guide that holds a flex sensor on the back of a finger while letting it slide as the finger bends. About 3 per finger.

| | |
|---|---|
| Outside | 14 mm wide × 12 mm long (along the finger) × 4 mm high, rounded corners |
| Slot | 7.0 × 1.0 mm through the whole length, 1.5 mm floor and roof. Flex sensor: 6.35 × 0.43 mm |
| Slot entries | flared to 8 × 2 mm over 0.8 mm, so the sensor's edges don't rub on a sharp corner |
| `_sew` version | 4 × 1.2 mm holes in the side walls for sewing it to the glove |

![preview](preview.png)

**Printing:** PLA or PETG (resin if available, for an accurate slot), 100 % infill, printed standing on an end face (slot vertical) so the slot needs no support. Print one first and check the sensor slides; if the slot comes out tight, regenerate with `SLOT_W, SLOT_H = 7.3, 1.3`.

**Regenerate:** `python make_holder.py .` (needs `manifold3d`, `trimesh` and `numpy`). Every size is a constant at the top of the script; the length is in the `for L in (12.0,)` loop.

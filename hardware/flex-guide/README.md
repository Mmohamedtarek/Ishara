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

# Anchor (base holder at the pins)

Holds the sensor's connector end fixed on the back of the hand, before the knuckle, so the sensor slides in the finger guides while its pins don't move. One per finger.

| | X (width) | Y (length) | Z (height) |
|---|---|---|---|
| Body | 10 | 20 | 5.5 |
| Opening, through the whole length, the same at both ends | 7.5 | 20 | 3.2 (z = 1.15 to 4.35) |
| Opening at the end faces (flared over 0.8 mm) | 8.1 | | 3.8 |
| Side walls / floor / roof | 1.25 each | | 1.15 / 1.15 |

Corners rounded 0.5 mm (smaller than the guides' 1.5 so the flared opening doesn't cut through them), top edge chamfered 0.6 mm. All in mm.

![anchor preview](anchor_preview.png)

**Sewing:** the 1.25 mm side walls leave no room for holes. Sew over the body: 2 or 3 stitches across the top at each end, pulled tight around it.

**Locking the pins:** once the sensor is in and tested, fill the opening with hot glue from the wire end, so bending pulls on the holder, not on the pins.

The opening size is from the sensor's typical crimp size, not measured on our sensors; measure the end with its solder joints and heat shrink before printing, and change `POCKET_W` / `POCKET_H` if needed.

**Printing:** standing on an end face (opening vertical), no support, 100 % infill. 5 plus 2 spares.

**Regenerate:** `python make_anchor.py .`

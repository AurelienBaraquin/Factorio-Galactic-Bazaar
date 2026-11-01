"""Deterministic PNG writing and RGBA image operations on numpy arrays (Blender's bundled numpy).

Images are float arrays of shape (height, width, 4), rows from the top, straight (not
premultiplied) alpha, values in [0, 1] in the sRGB encoding the render was saved in.
"""
import struct
import zlib

import numpy as np


def _chunk(kind, payload):
    body = kind + payload
    return struct.pack(">I", len(payload)) + body + struct.pack(">I", zlib.crc32(body) & 0xFFFFFFFF)


def _filtered_rows(raw):
    """Each row filtered with the PNG filter (0-4) that minimises the sum of absolute bytes."""
    data = raw.astype(np.int16)
    height, row_bytes = data.shape
    bpp = 4
    left = np.zeros_like(data)
    left[:, bpp:] = data[:, :-bpp]
    up = np.zeros_like(data)
    up[1:] = data[:-1]
    up_left = np.zeros_like(data)
    up_left[1:, bpp:] = data[:-1, :-bpp]
    p = left + up - up_left
    pa, pb, pc = np.abs(p - left), np.abs(p - up), np.abs(p - up_left)
    paeth = np.where((pa <= pb) & (pa <= pc), left, np.where(pb <= pc, up, up_left))
    candidates = [
        data,
        data - left,
        data - up,
        data - ((left + up) // 2),
        data - paeth,
    ]
    candidates = [np.mod(c, 256).astype(np.uint8) for c in candidates]
    scores = np.stack([np.abs(c.astype(np.int8).astype(np.int32)).sum(axis=1) for c in candidates])
    best = scores.argmin(axis=0)
    out = bytearray()
    for y in range(height):
        out.append(int(best[y]))
        out += candidates[best[y]][y].tobytes()
    return bytes(out)


def to_bytes(image):
    """Float RGBA image to uint8, colour zeroed where fully transparent (smaller, reproducible)."""
    rgba = np.clip(np.rint(image * 255.0), 0, 255).astype(np.uint8)
    rgba[rgba[..., 3] == 0] = 0
    return rgba


def write(path, image):
    """Writes an RGBA PNG, 8 bits per channel, maximum zlib compression."""
    rgba = to_bytes(image)
    height, width = rgba.shape[:2]
    header = struct.pack(">IIBBBBB", width, height, 8, 6, 0, 0, 0)
    idat = zlib.compress(_filtered_rows(rgba.reshape(height, width * 4)), 9)
    with open(path, "wb") as handle:
        handle.write(b"\x89PNG\r\n\x1a\n")
        handle.write(_chunk(b"IHDR", header))
        handle.write(_chunk(b"IDAT", idat))
        handle.write(_chunk(b"IEND", b""))


def alpha_bbox(images, threshold=1.0 / 255.0):
    """(left, top, right, bottom), right/bottom exclusive, of the pixels any image covers."""
    mask = np.zeros(images[0].shape[:2], dtype=bool)
    for image in images:
        mask |= image[..., 3] >= threshold
    rows = np.flatnonzero(mask.any(axis=1))
    cols = np.flatnonzero(mask.any(axis=0))
    if rows.size == 0:
        return 0, 0, 1, 1
    return int(cols[0]), int(rows[0]), int(cols[-1]) + 1, int(rows[-1]) + 1


def downsample(image, factor):
    """Box filter by an integer factor, averaging premultiplied colour."""
    height, width = image.shape[:2]
    blocks = image.reshape(height // factor, factor, width // factor, factor, 4)
    alpha = blocks[..., 3]
    colour = (blocks[..., :3] * alpha[..., None]).mean(axis=(1, 3))
    mean_alpha = alpha.mean(axis=(1, 3))
    out = np.zeros((height // factor, width // factor, 4))
    safe = np.where(mean_alpha > 0, mean_alpha, 1.0)
    out[..., :3] = colour / safe[..., None]
    out[..., 3] = mean_alpha
    return out


def sheet(frames, line_length):
    """Frames of equal size laid out left to right, `line_length` per row."""
    height, width = frames[0].shape[:2]
    rows = (len(frames) + line_length - 1) // line_length
    out = np.zeros((rows * height, line_length * width, 4))
    for index, frame in enumerate(frames):
        row, col = divmod(index, line_length)
        out[row * height:(row + 1) * height, col * width:(col + 1) * width] = frame
    return out


def mipmapped_icon(image, size, levels):
    """An icon file with `levels` mipmaps: size, size/2, ... side by side, aligned top-left."""
    width = sum(size >> level for level in range(levels))
    out = np.zeros((size, width, 4))
    x = 0
    for level in range(levels):
        edge = size >> level
        scaled = downsample(image, image.shape[0] // edge)
        out[:edge, x:x + edge] = scaled
        x += edge
    return out

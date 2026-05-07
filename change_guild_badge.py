"""
Guild Badge Changer
-------------------
Changes the Dragon-grade guild badge (the icon above your character's head).

HOW TO USE:
  1. Set IMAGE_PATH below to your new image (PNG, JPG, etc.)
  2. Close the game client
  3. Run this script:  python change_guild_badge.py
  4. Open the game and relog
"""

import struct, zlib, shutil, sys
from PIL import Image
import numpy as np

# ============================================================
#  CHANGE THIS to the path of your new image
# ============================================================
IMAGE_PATH = r'C:\Users\Admin\Downloads\Untitled design(11).png'
# ============================================================

PAK_PATH   = r'C:\DragonNest\DNClient\Resource20.pak'
TARGET     = 'guildflag11.dds'
W, H       = 96, 72   # badge dimensions (do not change)


def to_rgb565(r, g, b):
    return ((int(r) & 0xF8) << 8) | ((int(g) & 0xFC) << 3) | (int(b) >> 3)

def from_rgb565(v):
    return ((v>>11)&31)*255//31, ((v>>5)&63)*255//63, (v&31)*255//31

def encode_dxt5(img_rgba):
    pixels = np.array(img_rgba, dtype=np.uint8)
    result = bytearray()
    for by in range(0, H, 4):
        for bx in range(0, W, 4):
            block = np.zeros((16, 4), dtype=np.uint8)
            for py in range(4):
                for px in range(4):
                    yi, xi = min(by+py, H-1), min(bx+px, W-1)
                    block[py*4+px] = pixels[yi, xi]

            # Alpha block
            alphas = block[:, 3].astype(int)
            a0, a1 = int(alphas.max()), int(alphas.min())
            if a0 == a1:
                alpha_bytes = bytes([a0, 0, 0, 0, 0, 0, 0, 0])
            else:
                at = [a0, a1,
                      (6*a0+a1)//7, (5*a0+2*a1)//7,
                      (4*a0+3*a1)//7, (3*a0+4*a1)//7,
                      (2*a0+5*a1)//7, (a0+6*a1)//7]
                packed = 0
                for i, a in enumerate(alphas):
                    idx = min(range(8), key=lambda k: abs(a - at[k]))
                    packed |= idx << (i * 3)
                alpha_bytes = bytes([a0, a1]) + packed.to_bytes(6, 'little')

            # Color block (4-color mode, c0 > c1)
            rgb = block[:, :3].astype(int)
            lum = (rgb[:,0]*299 + rgb[:,1]*587 + rgb[:,2]*114) // 1000
            max_i, min_i = int(lum.argmax()), int(lum.argmin())
            r0,g0,b0 = int(rgb[max_i,0]), int(rgb[max_i,1]), int(rgb[max_i,2])
            r1,g1,b1 = int(rgb[min_i,0]), int(rgb[min_i,1]), int(rgb[min_i,2])
            c0 = to_rgb565(r0, g0, b0)
            c1 = to_rgb565(r1, g1, b1)
            if c0 == c1:
                c0 = min(c0 + 1, 0xFFFF)
            elif c0 < c1:
                c0, c1 = c1, c0
            cr0, cr1 = from_rgb565(c0), from_rgb565(c1)
            colors = [cr0, cr1,
                      tuple((2*a+b)//3 for a,b in zip(cr0,cr1)),
                      tuple((a+2*b)//3 for a,b in zip(cr0,cr1))]
            c_idx = 0
            for i, pix in enumerate(rgb):
                pr,pg,pb = int(pix[0]),int(pix[1]),int(pix[2])
                dists = [abs(pr-c[0])+abs(pg-c[1])+abs(pb-c[2]) for c in colors]
                c_idx |= dists.index(min(dists)) << (i*2)
            result += alpha_bytes
            result += struct.pack('<HHI', c0, c1, c_idx)
    return bytes(result)


def build_dds(img_path):
    img = Image.open(img_path).convert('RGBA').resize((W, H), Image.LANCZOS)
    dxt5 = encode_dxt5(img)
    header = bytearray(128)
    header[0:4] = b'DDS '
    struct.pack_into('<I', header, 4, 124)
    struct.pack_into('<I', header, 8, 0x001007)
    struct.pack_into('<I', header, 12, H)
    struct.pack_into('<I', header, 16, W)
    struct.pack_into('<I', header, 20, W*H)
    struct.pack_into('<I', header, 28, 1)
    struct.pack_into('<I', header, 76, 32)
    struct.pack_into('<I', header, 80, 0x04)
    header[84:88] = b'DXT5'
    struct.pack_into('<I', header, 108, 0x1000)
    return bytes(header) + dxt5


def patch_pak(pak_path, target, dds_bytes):
    comp_data = zlib.compress(dds_bytes, level=9)
    comp_size = len(comp_data)
    uncomp_size = len(dds_bytes)

    pak = bytearray(open(pak_path, 'rb').read())
    fc  = struct.unpack_from('<I', pak, 260)[0]
    to_ = struct.unpack_from('<I', pak, 264)[0]
    es  = (len(pak) - to_) // fc

    found_idx = -1
    for i in range(fc):
        base = to_ + i * es
        name = pak[base:base+256].split(b'\x00')[0].decode('utf-8', 'replace').replace('\\', '/')
        if target.lower() in name.lower():
            found_idx = i
            meta = base + 256
            old_comp   = struct.unpack_from('<I', pak, meta)[0]
            old_offset = struct.unpack_from('<I', pak, meta+12)[0]
            break

    if found_idx == -1:
        raise RuntimeError(f"'{target}' not found in pak!")

    if comp_size <= old_comp:
        pak[old_offset:old_offset+comp_size] = comp_data
        pak[old_offset+comp_size:old_offset+old_comp] = b'\x00' * (old_comp - comp_size)
        new_offset = old_offset
        final_to_  = to_
    else:
        # Insert before table to avoid breaking entry-size calculation
        new_offset = to_
        final_to_  = to_ + comp_size
        new_pak = bytearray(pak[:to_]) + bytearray(comp_data) + bytearray(pak[to_:])
        struct.pack_into('<I', new_pak, 264, final_to_)
        pak = new_pak

    entry_base = final_to_ + found_idx * es
    m = entry_base + 256
    struct.pack_into('<I', pak, m,    comp_size)
    struct.pack_into('<I', pak, m+4,  uncomp_size)
    struct.pack_into('<I', pak, m+8,  comp_size)
    struct.pack_into('<I', pak, m+12, new_offset)

    # Backup then write
    shutil.copy2(pak_path, pak_path + '.bak_badge')
    open(pak_path, 'wb').write(pak)
    return comp_size, old_comp


if __name__ == '__main__':
    sys.stdout.reconfigure(encoding='utf-8', errors='replace')
    print(f"Image : {IMAGE_PATH}")
    print(f"Target: {TARGET} in {PAK_PATH}")
    print("Encoding...")
    dds = build_dds(IMAGE_PATH)
    print(f"  DDS built: {len(dds)} bytes")
    comp, slot = patch_pak(PAK_PATH, TARGET, dds)
    print(f"  Compressed: {comp} bytes  (slot: {slot})")
    print("Done! Start the game and relog to see the new badge.")

# Del Fierro Dragon Nest Patches

Client-side texture patches for the Del Fierro private Dragon Nest server.

---

## Guild Badge Changer (`change_guild_badge.py`)

Changes the **Dragon-grade guild badge** (golden icon shown above your character's head when you hold rank 1 in guild reputation season).

### Requirements
- Python 3.x
- Pillow: `pip install Pillow`
- numpy: `pip install numpy`

### How to Use

1. Open `change_guild_badge.py` and set `IMAGE_PATH` to your image file:
   ```python
   IMAGE_PATH = r'C:\path\to\your\image.png'
   ```

2. Set `PAK_PATH` to your Dragon Nest client folder:
   ```python
   PAK_PATH = r'C:\DragonNest\DNClient\Resource20.pak'
   ```

3. **Close the game client.**

4. Run the script:
   ```
   python change_guild_badge.py
   ```

5. Launch the game and relog — the badge above your head will show your custom image.

### Notes
- The badge texture is `guildflag11.dds` inside `Resource20.pak`
- Dimensions: 96×72 pixels (image is auto-resized)
- A backup of the pak is saved as `Resource20.pak.bak_badge` before each change
- Supports PNG, JPG, and any format PIL can open

---

## Item IDs

| Item | ID |
|------|----|
| Dragon Grade Guild Badge | `536881441` |

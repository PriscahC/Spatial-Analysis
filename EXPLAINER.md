# Drone Orthomosaic & NDVI Pipeline — Replication Guide
> Step-by-step guide to reproduce the Lima Labs NDVI pipeline on any farm dataset.  
> Tested on: Ubuntu 22.04 · 4 vCPU · 8GB RAM · 15GB Swap · Docker 29.2.1 · GDAL 3.8.4

---

## Table of Contents
1. [Prerequisites](#1-prerequisites)
2. [System Setup](#2-system-setup)
3. [Add Swap Space](#3-add-swap-space)
4. [Install Docker](#4-install-docker)
5. [Set Up Python Environment](#5-set-up-python-environment)
6. [Configure rclone for Google Drive](#6-configure-rclone-for-google-drive)
7. [Understand Your Dataset](#7-understand-your-dataset)
8. [Download a Subset of Images](#8-download-a-subset-of-images)
9. [Organize Files by Band](#9-organize-files-by-band)
10. [Pull ODM Docker Image](#10-pull-odm-docker-image)
11. [Run ODM — RGB Orthomosaic](#11-run-odm--rgb-orthomosaic)
12. [Run ODM — NIR Orthomosaic](#12-run-odm--nir-orthomosaic)
13. [Run ODM — Red Orthomosaic](#13-run-odm--red-orthomosaic)
14. [NDVI Calculation & Colormap Script](#14-ndvi-calculation--colormap-script)
15. [Export as Cloud Optimized GeoTIFF](#15-export-as-cloud-optimized-geotiff-included-in-script)
16. [Upload Outputs to Google Drive](#16-upload-outputs-to-google-drive)
17. [Troubleshooting](#17-troubleshooting)
18. [Adapting for Other Farms](#18-adapting-for-other-farms)

---

## 1. Prerequisites

| Requirement | Minimum | Notes |
|---|---|---|
| RAM | 8GB | Add 16GB swap — see Step 3 |
| Disk | 50GB free | Raw images + outputs can exceed 30GB |
| CPU | 4 vCPU | More cores = faster ODM processing |
| OS | Ubuntu 22.04 | Other Debian-based distros should work |
| Internet | Stable | For downloading dataset from Google Drive |

---

## 2. System Setup

Connect to your server via SSH:
```bash
ssh root@your_server_ip
```

Update the system and install core dependencies:
```bash
sudo apt update && sudo apt upgrade -y
sudo apt install -y python3-pip python3-venv python3-full gdal-bin libgdal-dev curl unzip
```

Verify GDAL is installed:
```bash
gdal_translate --version
# Expected output: GDAL 3.x.x, released YYYY/MM/DD
```

---

## 3. Add Swap Space

> **Critical for 8GB RAM systems.** ODM's dense reconstruction stage is memory-intensive.
> Skip this step only if you have 32GB+ RAM.

```bash
sudo fallocate -l 16G /swapfile
sudo chmod 600 /swapfile
sudo mkswap /swapfile
sudo swapon /swapfile

# Make swap permanent across reboots
echo '/swapfile none swap sw 0 0' | sudo tee -a /etc/fstab

# Verify — should show ~16G swap
free -h
```

---

## 4. Install Docker

```bash
curl -fsSL https://get.docker.com -o get-docker.sh
sudo sh get-docker.sh
sudo usermod -aG docker $USER
newgrp docker

# Verify
docker --version
# Expected: Docker version 29.x.x
```

---

## 5. Set Up Python Environment

```bash
# Create project directory
mkdir -p ~/farm_project/{dataset,outputs}
mkdir -p ~/farm_project/dataset/{rgb,ms_nir,ms_red,ms_green,ms_re,raw}

# Create and activate virtual environment
python3 -m venv ~/farm_project/venv
source ~/farm_project/venv/bin/activate

# Install required Python libraries
pip install rasterio numpy matplotlib gdown

# Verify
python3 -c "import rasterio, numpy, matplotlib; print('All libraries OK')"
```

> **Note:** Activate the venv every time you open a new SSH session:
> ```bash
> source ~/farm_project/venv/bin/activate
> ```

---

## 6. Configure rclone for Google Drive

Install rclone:
```bash
curl https://rclone.org/install.sh | sudo bash
rclone --version
```

Configure Google Drive remote:
```bash
rclone config
```

Follow these prompts:
```
n          # New remote
gdrive     # Name it "gdrive"
drive      # Select Google Drive
           # Leave client_id blank → Enter
           # Leave client_secret blank → Enter
1          # scope: full access (read + write)
           # Leave root_folder_id blank → Enter
           # Leave service_account_file blank → Enter
n          # No advanced config
n          # No auto config (VM has no browser)
```

This gives you a URL. **On your local machine**, install rclone and run:
```bash
# On your LOCAL machine (not the server):
rclone authorize "drive" "eyJzY29wZSI6ImRyaXZlIn0"
```

A browser will open — sign into Google and allow access. Copy the token printed in your local terminal and paste it back into the server terminal at the `config_token>` prompt.

```
n          # Not a Shared Drive
y          # Keep this remote
q          # Quit config
```

Test the connection:
```bash
rclone lsd "gdrive:"
# Should list your Google Drive folders
```

---

## 7. Understand Your Dataset

### Expected DJI Multispectral File Naming Convention
```
DJI_YYYYMMDDHHMMSS_XXXX_D.JPG        ← RGB image
DJI_YYYYMMDDHHMMSS_XXXX_MS_G.TIF     ← Green band
DJI_YYYYMMDDHHMMSS_XXXX_MS_NIR.TIF   ← Near Infrared band  ← needed for NDVI
DJI_YYYYMMDDHHMMSS_XXXX_MS_R.TIF     ← Red band            ← needed for NDVI
DJI_YYYYMMDDHHMMSS_XXXX_MS_RE.TIF    ← Red Edge band
```

Where `XXXX` is the 4-digit image sequence number.

### Other files in the dataset (navigation data — not required for basic processing):
```
*.nav   ← GNSS navigation data (for PPK correction)
*.obs   ← GNSS observation data
*.bin   ← Raw IMU/GNSS binary data
*.MRK  ← DJI timestamp marker file
```

### Check what's in your Drive folder:
```bash
# List all files
rclone ls "gdrive:Farm A" --drive-shared-with-me | head -30

# Count image sets
rclone ls "gdrive:Farm A" --drive-shared-with-me | grep "_D.JPG" | wc -l

# Total file count
rclone ls "gdrive:Farm A" --drive-shared-with-me | wc -l
```

> **Replace "Farm A"** with the actual folder name in your Drive.

---

## 8. Download a Subset of Images

### How many image sets to use?

| RAM | Safe image sets | Notes |
|---|---|---|
| 8GB + 16GB swap | 100–164 | Used in this project |
| 16GB | 200–300 | Comfortable range |
| 32GB+ | 400+ | Can use full dataset |

### Select evenly-spaced images across the flight:
```bash
# List all JPGs sorted by filename (flight order)
rclone ls "gdrive:Farm A" --drive-shared-with-me | grep "_D.JPG" | awk '{print $2}' | sort > /tmp/all_jpgs.txt

# See total count
wc -l /tmp/all_jpgs.txt

# Pick every Nth image to get ~100-150 sets
# If you have 401 images, every 4th = ~100 sets
awk 'NR%4==0' /tmp/all_jpgs.txt > /tmp/selected.txt
wc -l /tmp/selected.txt
```

### Build rclone filter and download:
```bash
# Extract 4-digit image numbers
awk -F'_' '{print $(NF-1)}' /tmp/selected.txt > /tmp/selected_nums.txt

# Build filter file (NIR + Red + JPG only — skips Green and RedEdge)
while read num; do
  echo "+ *_${num}_D.JPG"
  echo "+ *_${num}_MS_NIR.TIF"
  echo "+ *_${num}_MS_R.TIF"
done < /tmp/selected_nums.txt > /tmp/rclone_filter.txt

# Exclude everything else
echo "- *" >> /tmp/rclone_filter.txt

# Verify filter (should be: selected_count × 3 + 1 lines)
wc -l /tmp/rclone_filter.txt

# Download
rclone copy "gdrive:Farm A" ~/farm_project/dataset/raw/ \
  --drive-shared-with-me \
  --filter-from /tmp/rclone_filter.txt \
  --progress \
  --transfers 4

# Confirm download counts (all three should be equal)
echo "JPGs:  $(ls ~/farm_project/dataset/raw/ | grep '_D.JPG' | wc -l)"
echo "NIR:   $(ls ~/farm_project/dataset/raw/ | grep '_MS_NIR.TIF' | wc -l)"
echo "Red:   $(ls ~/farm_project/dataset/raw/ | grep '_MS_R.TIF' | wc -l)"
```

---

## 9. Organize Files by Band

```bash
# Sort files into band-specific folders
mv ~/farm_project/dataset/raw/*_D.JPG       ~/farm_project/dataset/rgb/
mv ~/farm_project/dataset/raw/*_MS_NIR.TIF  ~/farm_project/dataset/ms_nir/
mv ~/farm_project/dataset/raw/*_MS_R.TIF    ~/farm_project/dataset/ms_red/

# ODM requires images inside an "images/" subfolder
mkdir -p ~/farm_project/dataset/rgb/images
mkdir -p ~/farm_project/dataset/ms_nir/images
mkdir -p ~/farm_project/dataset/ms_red/images

mv ~/farm_project/dataset/rgb/*.JPG         ~/farm_project/dataset/rgb/images/
mv ~/farm_project/dataset/ms_nir/*.TIF      ~/farm_project/dataset/ms_nir/images/
mv ~/farm_project/dataset/ms_red/*.TIF      ~/farm_project/dataset/ms_red/images/

# Verify
echo "RGB images:  $(ls ~/farm_project/dataset/rgb/images/ | wc -l)"
echo "NIR images:  $(ls ~/farm_project/dataset/ms_nir/images/ | wc -l)"
echo "Red images:  $(ls ~/farm_project/dataset/ms_red/images/ | wc -l)"
```

---

## 10. Pull ODM Docker Image

```bash
# Use version 3.3.0 — avoids a DJI EXIF bug present in 3.5.6
docker pull opendronemap/odm:3.3.0

# Verify
docker images | grep odm
```

> **Why 3.3.0?** ODM 3.5.6 has a bug with DJI drone EXIF metadata that causes an
> `IndexError: list index out of range` crash during dataset loading. Version 3.3.0 handles
> DJI files correctly.

---

## 11. Run ODM — RGB Orthomosaic

```bash
nohup docker run --rm \
  -v ~/farm_project/dataset/rgb:/datasets/code \
  opendronemap/odm:3.3.0 \
  --project-path /datasets code \
  --orthophoto-resolution 5 \
  --feature-quality medium \
  --pc-quality medium \
  --auto-boundary \
  --skip-3dmodel \
  --max-concurrency 4 > ~/farm_project/odm_rgb.log 2>&1 &

echo "ODM RGB PID: $!"

# Monitor progress
tail -f ~/farm_project/odm_rgb.log
```

### Key log milestones to watch for:
```
[INFO] Running dataset stage          ← Loading images (fast)
[INFO] Running opensfm stage          ← Feature matching + SfM (slow, 20-40 min)
[INFO] Running openmvs stage          ← Dense reconstruction (slowest, 20-40 min)
[INFO] Running odm_orthophoto stage   ← Almost done!
[INFO] ODM app finished               ← Complete ✅
```

Check if still running:
```bash
docker ps
```

Expected output location:
```
~/farm_project/dataset/rgb/odm_orthophoto/odm_orthophoto.tif
```

Verify:
```bash
ls -lh ~/farm_project/dataset/rgb/odm_orthophoto/
```

---

## 12. Run ODM — NIR Orthomosaic

```bash
nohup docker run --rm \
  -v ~/farm_project/dataset/ms_nir:/datasets/code \
  opendronemap/odm:3.3.0 \
  --project-path /datasets code \
  --orthophoto-resolution 5 \
  --feature-quality medium \
  --pc-quality medium \
  --auto-boundary \
  --skip-3dmodel \
  --max-concurrency 4 > ~/farm_project/odm_nir.log 2>&1 &

echo "ODM NIR PID: $!"
tail -f ~/farm_project/odm_nir.log
```

Expected output:
```
~/farm_project/dataset/ms_nir/odm_orthophoto/odm_orthophoto.tif
```

---

## 13. Run ODM — Red Orthomosaic

```bash
nohup docker run --rm \
  -v ~/farm_project/dataset/ms_red:/datasets/code \
  opendronemap/odm:3.3.0 \
  --project-path /datasets code \
  --orthophoto-resolution 5 \
  --feature-quality medium \
  --pc-quality medium \
  --auto-boundary \
  --skip-3dmodel \
  --max-concurrency 4 > ~/farm_project/odm_red.log 2>&1 &

echo "ODM Red PID: $!"
tail -f ~/farm_project/odm_red.log
```

Expected output:
```
~/farm_project/dataset/ms_red/odm_orthophoto/odm_orthophoto.tif
```

> **Run jobs sequentially** on 8GB RAM systems — running two ODM jobs simultaneously will
> exhaust memory. Wait for each job to fully finish before starting the next.

---

## 14. NDVI Calculation & Colormap Script

Save this script as `~/farm_project/process_ndvi.py`:

```bash
cat > ~/farm_project/process_ndvi.py << 'PYEOF'
import rasterio
import numpy as np
import matplotlib.pyplot as plt
import subprocess
import os

# ── PATHS — update these for each farm ──────────────────────────────────────
NIR_ORTHO  = os.path.expanduser("~/farm_project/dataset/ms_nir/odm_orthophoto/odm_orthophoto.tif")
RED_ORTHO  = os.path.expanduser("~/farm_project/dataset/ms_red/odm_orthophoto/odm_orthophoto.tif")
RGB_ORTHO  = os.path.expanduser("~/farm_project/dataset/rgb/odm_orthophoto/odm_orthophoto.tif")
OUTPUT_DIR = os.path.expanduser("~/farm_project/outputs")
os.makedirs(OUTPUT_DIR, exist_ok=True)

# ── STEP 1: Read NIR and Red bands ───────────────────────────────────────────
print("Reading NIR orthomosaic...")
with rasterio.open(NIR_ORTHO) as src:
    nir     = src.read(1).astype(np.float32)
    profile = src.profile
    print(f"  Shape: {nir.shape} | CRS: {src.crs} | Resolution: {src.res}")

print("Reading Red orthomosaic...")
with rasterio.open(RED_ORTHO) as src:
    red = src.read(1).astype(np.float32)
    print(f"  Shape: {red.shape}")

# ── STEP 2: Align shapes if needed ──────────────────────────────────────────
if nir.shape != red.shape:
    print(f"Shape mismatch — reprojecting Red to match NIR...")
    from rasterio.warp import reproject, Resampling
    red_resampled = np.empty(nir.shape, dtype=np.float32)
    with rasterio.open(NIR_ORTHO) as nir_src:
        with rasterio.open(RED_ORTHO) as red_src:
            reproject(
                source=rasterio.band(red_src, 1),
                destination=red_resampled,
                src_transform=red_src.transform,
                src_crs=red_src.crs,
                dst_transform=nir_src.transform,
                dst_crs=nir_src.crs,
                resampling=Resampling.bilinear
            )
    red = red_resampled
    print("  Reprojection done.")

# ── STEP 3: Calculate NDVI ───────────────────────────────────────────────────
print("Calculating NDVI...")
np.seterr(divide='ignore', invalid='ignore')
mask = (red + nir) == 0
ndvi = np.where(mask, np.nan, (nir - red) / (nir + red))
ndvi = np.clip(ndvi, -1, 1)
print(f"  Min: {np.nanmin(ndvi):.4f} | Max: {np.nanmax(ndvi):.4f} | Mean: {np.nanmean(ndvi):.4f}")

# ── STEP 4: Save raw NDVI GeoTIFF ────────────────────────────────────────────
ndvi_path = os.path.join(OUTPUT_DIR, "ndvi_raw.tif")
profile.update(dtype=rasterio.float32, count=1, compress='lzw', nodata=np.nan)
with rasterio.open(ndvi_path, 'w', **profile) as dst:
    dst.write(ndvi.astype(np.float32), 1)
print(f"Raw NDVI saved: {ndvi_path}")

# ── STEP 5: Apply RdYlGn thermal colormap ────────────────────────────────────
print("Applying colormap...")
ndvi_norm = (ndvi + 1) / 2.0
ndvi_norm = np.nan_to_num(ndvi_norm, nan=0)
cmap      = plt.cm.RdYlGn
colored   = cmap(ndvi_norm)
rgb_arr   = (colored[:, :, :3] * 255).astype(np.uint8)

colored_path = os.path.join(OUTPUT_DIR, "ndvi_colored.tif")
profile.update(dtype=rasterio.uint8, count=3, compress='lzw', nodata=None)
with rasterio.open(colored_path, 'w', **profile) as dst:
    dst.write(rgb_arr[:, :, 0], 1)
    dst.write(rgb_arr[:, :, 1], 2)
    dst.write(rgb_arr[:, :, 2], 3)
print(f"Colored NDVI saved: {colored_path}")

# ── STEP 6: Save preview PNG ─────────────────────────────────────────────────
print("Saving preview PNG...")
preview_path = os.path.join(OUTPUT_DIR, "ndvi_preview.png")
fig, axes = plt.subplots(1, 2, figsize=(18, 8))

axes[0].imshow(rgb_arr)
axes[0].set_title("NDVI Thermal Colormap (RdYlGn)", fontsize=14)
axes[0].axis('off')

im = axes[1].imshow(ndvi, cmap='RdYlGn', vmin=-1, vmax=1)
plt.colorbar(im, ax=axes[1], label='NDVI Value', fraction=0.03)
axes[1].set_title("NDVI Values (−1 to 1)", fontsize=14)
axes[1].axis('off')

plt.suptitle("NDVI Analysis", fontsize=16, fontweight='bold')
plt.tight_layout()
plt.savefig(preview_path, dpi=150, bbox_inches='tight')
plt.close()
print(f"Preview saved: {preview_path}")

# ── STEP 7: Export Cloud Optimized GeoTIFFs ──────────────────────────────────
print("Exporting COGs...")

subprocess.run(["gdal_translate", ndvi_path,
    os.path.join(OUTPUT_DIR, "ndvi_cog.tif"),
    "-of", "COG", "-co", "COMPRESS=LZW",
    "-co", "OVERVIEW_RESAMPLING=AVERAGE"], check=True)
print("  ndvi_cog.tif done")

subprocess.run(["gdal_translate", colored_path,
    os.path.join(OUTPUT_DIR, "ndvi_colored_cog.tif"),
    "-of", "COG", "-co", "COMPRESS=JPEG", "-co", "QUALITY=85",
    "-co", "OVERVIEW_RESAMPLING=AVERAGE"], check=True)
print("  ndvi_colored_cog.tif done")

subprocess.run(["gdal_translate", RGB_ORTHO,
    os.path.join(OUTPUT_DIR, "rgb_orthomosaic_cog.tif"),
    "-of", "COG", "-co", "COMPRESS=JPEG", "-co", "QUALITY=85",
    "-co", "OVERVIEW_RESAMPLING=AVERAGE"], check=True)
print("  rgb_orthomosaic_cog.tif done")

print("\n✅ All outputs ready:")
os.system(f"ls -lh {OUTPUT_DIR}")
PYEOF

echo "Script saved successfully."
```

Run the script:
```bash
source ~/farm_project/venv/bin/activate
python3 ~/farm_project/process_ndvi.py
```

### Expected output:
```
Reading NIR orthomosaic...
  Shape: (XXXX, XXXX) | CRS: EPSG:XXXXX | Resolution: (X.X, X.X)
Reading Red orthomosaic...
  Shape: (XXXX, XXXX)
Calculating NDVI...
  Min: -0.XXXX | Max: 0.XXXX | Mean: 0.XXXX
Raw NDVI saved: ~/farm_project/outputs/ndvi_raw.tif
Applying colormap...
Colored NDVI saved: ~/farm_project/outputs/ndvi_colored.tif
Saving preview PNG...
Preview saved: ~/farm_project/outputs/ndvi_preview.png
Exporting COGs...
  ndvi_cog.tif done
  ndvi_colored_cog.tif done
  rgb_orthomosaic_cog.tif done

✅ All outputs ready:
```

---

## 15. Export as Cloud Optimized GeoTIFF (included in script)

The script in Step 14 handles COG export automatically. If you need to run it manually on any GeoTIFF:

```bash
# Lossless COG (for analysis rasters — NDVI float, elevation, etc.)
gdal_translate input.tif output_cog.tif \
  -of COG \
  -co COMPRESS=LZW \
  -co OVERVIEW_RESAMPLING=AVERAGE

# Lossy COG (for visual rasters — RGB, colored NDVI)
gdal_translate input.tif output_cog.tif \
  -of COG \
  -co COMPRESS=JPEG \
  -co QUALITY=85 \
  -co OVERVIEW_RESAMPLING=AVERAGE
```

---

## 16. Upload Outputs to Google Drive

```bash
# Upload all outputs to a new folder in Google Drive
rclone copy ~/farm_project/outputs/ "gdrive:Farm_Outputs/FarmA/" --progress

# Upload RGB orthomosaic too
rclone copy ~/farm_project/dataset/rgb/odm_orthophoto/odm_orthophoto.tif \
  "gdrive:Farm_Outputs/FarmA/" --progress
```

---

## 17. Troubleshooting

### ODM crashes with `IndexError: list index out of range`
**Cause:** ODM 3.5.6 has a DJI EXIF parsing bug.  
**Fix:** Use ODM 3.3.0 instead:
```bash
docker pull opendronemap/odm:3.3.0
# Replace "opendronemap/odm:latest" with "opendronemap/odm:3.3.0" in all docker run commands
```

### ODM crashes or freezes mid-processing
**Cause:** Out of memory.  
**Fix:** Check swap and reduce quality settings:
```bash
free -h  # Check available memory
# Add these flags to ODM command:
# --feature-quality lowest
# --pc-quality lowest
# --orthophoto-resolution 10
```

### rclone returns `403 Insufficient Permission`
**Cause:** rclone was configured with readonly scope.  
**Fix:** Reconfigure with full access scope:
```bash
rclone config
# Edit existing remote → change scope to 1 (full access)
# Re-authenticate with: rclone authorize "drive" "eyJzY29wZSI6ImRyaXZlIn0"
```

### gdown fails with "more than 50 files" error
**Cause:** gdown has a 50-file limit on shared folders.  
**Fix:** Use rclone instead (Step 6).

### Python `externally-managed-environment` error
**Cause:** Ubuntu 22.04 protects the system Python.  
**Fix:** Always use a virtual environment:
```bash
python3 -m venv ~/farm_project/venv
source ~/farm_project/venv/bin/activate
pip install rasterio numpy matplotlib
```

### NDVI script fails with shape mismatch
**Cause:** NIR and Red orthomosaics have slightly different extents or resolutions.  
**Fix:** The script handles this automatically via reprojection. If it still fails:
```bash
# Check shapes manually
python3 -c "
import rasterio
for p in ['ms_nir', 'ms_red']:
    with rasterio.open(f'~/farm_project/dataset/{p}/odm_orthophoto/odm_orthophoto.tif') as s:
        print(p, s.shape, s.crs, s.res)
"
```

### ODM images not found error
**Cause:** ODM expects images in an `images/` subfolder.  
**Fix:**
```bash
mkdir -p ~/farm_project/dataset/rgb/images
mv ~/farm_project/dataset/rgb/*.JPG ~/farm_project/dataset/rgb/images/
```

---

## 18. Adapting for Other Farms

### Step-by-step checklist for a new farm:

- [ ] Create a new project directory: `mkdir -p ~/farm_B/{dataset,outputs}`
- [ ] Update the rclone Drive folder name in download commands (e.g., `"gdrive:Farm B"`)
- [ ] Check the new farm's filename pattern: `rclone ls "gdrive:Farm B" | head -20`
- [ ] Adjust the `awk -F'_'` regex if the image numbering format differs
- [ ] Update the 3 path variables at the top of `process_ndvi.py`:
  ```python
  NIR_ORTHO  = "~/farm_B/dataset/ms_nir/odm_orthophoto/odm_orthophoto.tif"
  RED_ORTHO  = "~/farm_B/dataset/ms_red/odm_orthophoto/odm_orthophoto.tif"
  RGB_ORTHO  = "~/farm_B/dataset/rgb/odm_orthophoto/odm_orthophoto.tif"
  OUTPUT_DIR = "~/farm_B/outputs"
  ```
- [ ] Check band count of a sample TIF before running NDVI:
  ```bash
  python3 -c "
  import rasterio
  with rasterio.open('sample.TIF') as src:
      print('Bands:', src.count, '| CRS:', src.crs)
  "
  ```
- [ ] If sensor is **not DJI** (e.g., MicaSense RedEdge), verify band order — it may differ

### MicaSense RedEdge band order (for reference):
| Band | MicaSense file suffix |
|---|---|
| Blue | _1.tif |
| Green | _2.tif |
| Red | _3.tif |
| NIR | _4.tif |
| Red Edge | _5.tif |

### ODM settings to tune per farm:
| Setting | Default used | When to change |
|---|---|---|
| `--orthophoto-resolution` | 5 cm/px | Increase to 10 for lower RAM usage |
| `--feature-quality` | medium | Use `high` if you have 16GB+ RAM |
| `--pc-quality` | medium | Use `high` for denser point cloud |
| `--max-concurrency` | 4 | Set to your vCPU count |

---

## Final Output Files

| File | Description | Size (typical) |
|---|---|---|
| `ndvi_raw.tif` | Float32 NDVI raster, lossless | 400–600MB |
| `ndvi_colored.tif` | RGB thermal colormap, uint8 | 100–200MB |
| `ndvi_cog.tif` | NDVI as Cloud Optimized GeoTIFF | 400–600MB |
| `ndvi_colored_cog.tif` | Colored NDVI COG, JPEG compressed | 20–50MB |
| `ndvi_preview.png` | Side-by-side preview image | 2–5MB |
| `rgb_orthomosaic_cog.tif` | RGB orthomosaic COG | 50–100MB |

---

## Tools & Versions Used

| Tool | Version | Purpose |
|---|---|---|
| OpenDroneMap | 3.3.0 (Docker) | Photogrammetric stitching |
| Python | 3.12 | NDVI processing script |
| rasterio | 1.5.0 | Raster I/O |
| numpy | 2.4.2 | Array math |
| matplotlib | 3.10.8 | Colormap application |
| GDAL | 3.8.4 | COG export |
| rclone | latest | Google Drive transfer |
| Docker | 29.2.1 | ODM containerization |
| Ubuntu | 22.04 | Operating system |

---

*Generated from the Lima Labs Farm A processing run — February 28, 2026*

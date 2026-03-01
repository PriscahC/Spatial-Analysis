# Step 1: Connect to Your VM & Initial Setup
ssh root@your_contabo_ip

sudo apt update && sudo apt upgrade -y
sudo apt install -y python3-pip python3-venv git curl wget unzip htop gdal-bin libgdal-dev

# Step 2: Install Docker (for ODM)
curl -fsSL https://get.docker.com -o get-docker.sh
sudo sh get-docker.sh
sudo usermod -aG docker $USER
newgrp docker

## Verify
docker --version

# Step 3: Add a Swap File (Critical for 8GB RAM)
# ODM will likely crash without this. This gives you an extra 16GB of virtual memory:
sudo fallocate -l 16G /swapfile
sudo chmod 600 /swapfile
sudo mkswap /swapfile
sudo swapon /swapfile

# Make it permanent
echo '/swapfile none swap sw 0 0' | sudo tee -a /etc/fstab

# Verify
free -h

# Step 4: Set Up Python Environment
mkdir ~/lima_labs && cd ~/lima_labs

python3 -m venv venv
source venv/bin/activate

pip install rasterio numpy matplotlib scipy tqdm gdal2tiles Pillow
pip install gdown  # for downloading from Google Drive

# Step 5: Download Dataset from Google Drive
cd ~/lima_labs
source venv/bin/activate

# gdown handles large Google Drive folders
pip install gdown

# Download the entire shared folder
# Replace the ID with the one from your Drive link
# Your link: https://drive.google.com/drive/folders/1Pnj7CoTadRMo9RVbZcp8foI8B5B8QbK2
gdown --folder "1Pnj7CoTadRMo9RVbZcp8foI8B5B8QbK2" -O ~/lima_labs/dataset/

# If gdown fails (sometimes Drive blocks it), use this alternative:
pip install rclone

# Setup rclone with Google Drive (one-time)
rclone config
# Follow prompts: n → name it "gdrive" → choose Google Drive → follow auth steps

# Then sync the folder
rclone copy "gdrive:/" ~/lima_labs/dataset/ --drive-shared-with-me

# Check what downloaded:
ls ~/lima_labs/dataset/
find ~/lima_labs/dataset/ -name "*.jpg" | wc -l
find ~/lima_labs/dataset/ -name "*.tif" -o -name "*.TIF" | wc -l

# Step 6: Organize Files
mkdir -p ~/lima_labs/dataset/rgb
mkdir -p ~/lima_labs/dataset/ms_nir
mkdir -p ~/lima_labs/dataset/ms_red
mkdir -p ~/lima_labs/dataset/ms_green
mkdir -p ~/lima_labs/dataset/ms_re
mkdir -p ~/lima_labs/dataset/multispectral  # for ODM (all MS bands together)

# Sort by band
find ~/lima_labs/dataset/ -maxdepth 1 -iname "*_D.JPG"      -exec mv {} ~/lima_labs/dataset/rgb/ \;
find ~/lima_labs/dataset/ -maxdepth 1 -iname "*_MS_NIR.TIF" -exec mv {} ~/lima_labs/dataset/ms_nir/ \;
find ~/lima_labs/dataset/ -maxdepth 1 -iname "*_MS_R.TIF"   -exec mv {} ~/lima_labs/dataset/ms_red/ \;
find ~/lima_labs/dataset/ -maxdepth 1 -iname "*_MS_G.TIF"   -exec mv {} ~/lima_labs/dataset/ms_green/ \;
find ~/lima_labs/dataset/ -maxdepth 1 -iname "*_MS_RE.TIF"  -exec mv {} ~/lima_labs/dataset/ms_re/ \;

# Confirm counts (all should be equal)
echo "RGB JPGs:  $(ls ~/lima_labs/dataset/rgb/ | wc -l)"
echo "NIR TIFs:  $(ls ~/lima_labs/dataset/ms_nir/ | wc -l)"
echo "Red TIFs:  $(ls ~/lima_labs/dataset/ms_red/ | wc -l)"

# Move JPGs to images folder
find ~/lima_labs/dataset/ -maxdepth 1 -iname "*.jpg" -exec mv {} ~/lima_labs/dataset/images/ \;

# Move TIFs to multispectral folder
find ~/lima_labs/dataset/ -maxdepth 1 -iname "*.tif" -exec mv {} ~/lima_labs/dataset/multispectral/ \;

# Confirm
echo "JPGs: $(ls ~/lima_labs/dataset/rgb/ | wc -l)"
echo "TIFs: $(ls ~/lima_labs/dataset/multispectral/ | wc -l)"

# Step 7: Inspect Your TIF Files First (Important!)
cd ~/lima_labs
source venv/bin/activate

python3 << 'EOF'
import rasterio
import os

tif_dir = os.path.expanduser("~/lima_labs/dataset/multispectral")
files = sorted(os.listdir(tif_dir))[:5]

for f in files:
    print(f"\n--- {f} ---")
    with rasterio.open(os.path.join(tif_dir, f)) as src:
        print(f"  Bands: {src.count}")
        print(f"  CRS: {src.crs}")
        print(f"  Size: {src.width} x {src.height}")
        print(f"  Dtype: {src.dtypes[0]}")
        print(f"  Has GPS: {src.crs is not None}")

# Also print first 20 filenames to understand naming pattern
print("\n--- First 20 TIF filenames ---")
for f in files[:20]:
    print(f)
EOF

# Step 8: Run ODM for RGB Orthomosaic
docker run -ti --rm \
  --memory="7g" \
  -v ~/lima_labs/dataset/rgb:/datasets/code \
  opendronemap/odm:latest \
  --project-path /datasets code \
  --orthophoto-resolution 5 \
  --feature-quality medium \
  --pc-quality medium \
  --auto-boundary \
  --skip-3dmodel \
  --max-concurrency 4

# This will take 2-6 hours. Run in background with:
nohup docker run ... > ~/lima_labs/odm_rgb.log 2>&1 &

# Monitor progress
tail -f ~/lima_labs/odm_rgb.log
```

Output will be at:
```
~/lima_labs/dataset/rgb/odm_orthophoto/odm_orthophoto.tif

# Step 9: Run ODM for Multispectral Orthomosaic
nohup docker run -ti --rm \
  --memory="7g" \
  -v ~/lima_labs/dataset/multispectral:/datasets/code \
  opendronemap/odm:latest \
  --project-path /datasets code \
  --orthophoto-resolution 5 \
  --feature-quality medium \
  --pc-quality medium \
  --radiometric-calibration camera \
  --auto-boundary \
  --skip-3dmodel \
  --max-concurrency 4 > ~/lima_labs/odm_ms.log 2>&1 &

tail -f ~/lima_labs/odm_ms.log

# Step 10: NDVI + Colormap Python Script
#  Once ODM finishes, save this as ~/lima_labs/process_ndvi.py:
cat > ~/lima_labs/process_ndvi.py << 'EOF'
import rasterio
import numpy as np
import matplotlib.pyplot as plt
import matplotlib.colors as mcolors
import subprocess
import os

OUTPUT_DIR = os.path.expanduser("~/lima_labs/outputs")
MS_ORTHO = os.path.expanduser(
    "~/lima_labs/dataset/multispectral/odm_orthophoto/odm_orthophoto.tif"
)

# --- Step 1: Read bands ---
# After ODM produces two separate orthomosaics:
NIR_ORTHO = "~/lima_labs/dataset/ms_nir/odm_orthophoto/odm_orthophoto.tif"
RED_ORTHO = "~/lima_labs/dataset/ms_red/odm_orthophoto/odm_orthophoto.tif"

with rasterio.open(NIR_ORTHO) as src:
    nir = src.read(1).astype(np.float32)
    profile = src.profile

with rasterio.open(RED_ORTHO) as src:
    red = src.read(1).astype(np.float32)

# Then NDVI calculation proceeds exactly as before
ndvi = (nir - red) / (nir + red)

# --- Step 2: Calculate NDVI ---
print("Calculating NDVI...")
np.seterr(divide='ignore', invalid='ignore')
mask = (red + nir) == 0
ndvi = np.where(mask, np.nan, (nir - red) / (nir + red))
ndvi = np.clip(ndvi, -1, 1)

print(f"NDVI min: {np.nanmin(ndvi):.4f}")
print(f"NDVI max: {np.nanmax(ndvi):.4f}")
print(f"NDVI mean: {np.nanmean(ndvi):.4f}")

# --- Step 3: Save raw NDVI GeoTIFF ---
ndvi_path = os.path.join(OUTPUT_DIR, "ndvi_raw.tif")
profile.update(dtype=rasterio.float32, count=1, compress='lzw', nodata=np.nan)
with rasterio.open(ndvi_path, 'w', **profile) as dst:
    dst.write(ndvi.astype(np.float32), 1)
print(f"Raw NDVI saved: {ndvi_path}")

# --- Step 4: Apply thermal colormap ---
print("Applying colormap...")
ndvi_norm = (ndvi + 1) / 2.0
ndvi_norm = np.nan_to_num(ndvi_norm, nan=0)

cmap = plt.cm.RdYlGn
colored = cmap(ndvi_norm)
rgb = (colored[:, :, :3] * 255).astype(np.uint8)

colored_path = os.path.join(OUTPUT_DIR, "ndvi_colored.tif")
profile.update(dtype=rasterio.uint8, count=3, compress='lzw', nodata=None)
with rasterio.open(colored_path, 'w', **profile) as dst:
    dst.write(rgb[:, :, 0], 1)
    dst.write(rgb[:, :, 1], 2)
    dst.write(rgb[:, :, 2], 3)
print(f"Colored NDVI saved: {colored_path}")

# --- Step 5: Save preview PNG ---
preview_path = os.path.join(OUTPUT_DIR, "ndvi_preview.png")
fig, ax = plt.subplots(figsize=(14, 10))
im = ax.imshow(ndvi, cmap='RdYlGn', vmin=-1, vmax=1)
plt.colorbar(im, ax=ax, label='NDVI Value', fraction=0.03)
ax.set_title("NDVI Thermal Colormap - Lima Labs", fontsize=16)
ax.axis('off')
plt.savefig(preview_path, dpi=150, bbox_inches='tight')
plt.close()
print(f"Preview saved: {preview_path}")

# --- Step 6: Export as Cloud-Optimized GeoTIFF ---
print("Exporting COGs...")
subprocess.run([
    "gdal_translate", ndvi_path,
    os.path.join(OUTPUT_DIR, "ndvi_cog.tif"),
    "-of", "COG", "-co", "COMPRESS=LZW",
    "-co", "OVERVIEW_RESAMPLING=AVERAGE"
], check=True)

subprocess.run([
    "gdal_translate", colored_path,
    os.path.join(OUTPUT_DIR, "ndvi_colored_cog.tif"),
    "-of", "COG", "-co", "COMPRESS=JPEG",
    "-co", "QUALITY=85",
    "-co", "OVERVIEW_RESAMPLING=AVERAGE"
], check=True)

# RGB orthomosaic COG
rgb_ortho = os.path.expanduser(
    "~/lima_labs/dataset/rgb/odm_orthophoto/odm_orthophoto.tif"
)
subprocess.run([
    "gdal_translate", rgb_ortho,
    os.path.join(OUTPUT_DIR, "rgb_orthomosaic_cog.tif"),
    "-of", "COG", "-co", "COMPRESS=JPEG",
    "-co", "QUALITY=85",
    "-co", "OVERVIEW_RESAMPLING=AVERAGE"
], check=True)

print("\n✅ All outputs ready in:", OUTPUT_DIR)
os.system(f"ls -lh {OUTPUT_DIR}")
EOF

# Run it:
cd ~/lima_labs
source venv/bin/activate
python3 process_ndvi.py

# Step 11: Download Outputs to Your Local Machine
# Download all outputs
scp -r root@your_contabo_ip:~/lima_labs/outputs/ ./lima_labs_outputs/

# Or just specific files
scp root@your_contabo_ip:~/lima_labs/outputs/ndvi_colored_cog.tif ./
scp root@your_contabo_ip:~/lima_labs/outputs/ndvi_preview.png ./

# Monitoring Your VM During ODM | Open a second SSH session and run:
# Watch RAM and CPU live
htop

# Watch disk space
watch -n 5 df -h

# Check ODM log
tail -f ~/lima_labs/odm_rgb.log

#  What To Do If ODM Crashes (RAM issue) | Reduce quality further:
# Add these flags to the ODM command
--feature-quality lowest \
--pc-quality lowest \
--min-num-features 4000 \
--orthophoto-resolution 10   # lower resolution = less RAM

# Or split images into batches of 300 and process separately, then merge orthomosaics with:
gdal_merge.py -o merged_ortho.tif batch1_ortho.tif batch2_ortho.tif batch3_ortho.tif

# ODM Jobs
# Job 1: RGB orthomosaic (from _D.JPG files)
# Job 2: NIR orthomosaic (from _MS_NIR.TIF files)  
# Job 3: Red orthomosaic (from _MS_R.TIF files)





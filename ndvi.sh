pip install rasterio numpy matplotlib

rasterio
import numpy as np
import matplotlib.pyplot as plt
from rasterio.transform import from_bounds

# Open your multispectral orthomosaic
with rasterio.open("multispectral_orthomosaic.tif") as src:
    # Adjust band numbers based on your sensor
    # Micasense: Band 3 = Red, Band 4 = NIR
    red = src.read(3).astype(float)
    nir = src.read(4).astype(float)
    profile = src.profile
    transform = src.transform
    crs = src.crs

# Avoid division by zero
np.seterr(divide='ignore', invalid='ignore')

# NDVI formula
ndvi = np.where(
    (nir + red) == 0,
    np.nan,
    (nir - red) / (nir + red)
)

# Clip to valid range
ndvi = np.clip(ndvi, -1, 1)

# Save raw NDVI GeoTIFF
profile.update(dtype=rasterio.float32, count=1, compress='deflate')
with rasterio.open("ndvi_raw.tif", 'w', **profile) as dst:
    dst.write(ndvi.astype(np.float32), 1)

print("NDVI saved. Min:", np.nanmin(ndvi), "Max:", np.nanmax(ndvi))

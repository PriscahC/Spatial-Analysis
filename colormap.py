import rasterio
import numpy as np
import matplotlib.pyplot as plt
import matplotlib.colors as mcolors
from rasterio.enums import ColorInterp

with rasterio.open("ndvi_raw.tif") as src:
    ndvi = src.read(1)
    profile = src.profile
    crs = src.crs
    transform = src.transform

# Normalize NDVI to 0-1 for colormap
ndvi_norm = (ndvi - (-1)) / (1 - (-1))  # scale from [-1,1] to [0,1]
ndvi_norm = np.nan_to_num(ndvi_norm, nan=0)

# Apply thermal colormap (jet or inferno both look "thermal")
colormap = plt.get_cmap('jet')  # or 'inferno', 'plasma', 'RdYlGn'
colored = colormap(ndvi_norm)   # returns RGBA array (0-1 float)

# Convert to uint8
r = (colored[:,:,0] * 255).astype(np.uint8)
g = (colored[:,:,1] * 255).astype(np.uint8)
b = (colored[:,:,2] * 255).astype(np.uint8)

# Save as RGB GeoTIFF with thermal colormap
profile.update(dtype=rasterio.uint8, count=3, compress='deflate')
with rasterio.open("ndvi_thermal_colored.tif", 'w', **profile) as dst:
    dst.write(r, 1)
    dst.write(g, 2)
    dst.write(b, 3)

print("Thermal NDVI saved.")

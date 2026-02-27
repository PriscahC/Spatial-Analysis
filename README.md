# Spatial-Analysis
Drone Orthomosaic &amp; NDVI Processing


## Lima Labs – Drone Orthomosaic & NDVI Technical Interview
Assignment
You are provided with a dataset:
[Link](https://drive.google.com/drive/folders/1Pnj7CoTadRMo9RVbZcp8foI8B5B8QbK2?usp=sharing) containing raw drone imagery (RGB + Multispectral
bands) collected over an agricultural field. Your task is to generate: 
1. 💡 A thermal colormapped NDVI orthomosaic
2.  An RGB orthomosaic

### Submission: PDF report / code/ Images
Part 1 – Orthomosaic & NDVI Generation
- Stitch raw drone images into a georeferenced RGB orthomosaic.
- Generate an NDVI raster from the NIR and Red bands.
- Apply a thermal-style colormap to the NDVI output.
- Export both outputs as GeoTIFFs (cloud-optimized preferred).
- Clearly document assumptions and preprocessing steps.

## Part 2 – Workflow Explanation
Provide a step-by-step explanation of your workflow including: 
- Preprocessing steps (radiometric correction, alignment, etc.)
-  Orthorectification approach
-   NDVI calculation method
-  Colormap application method
-   Export settings and CRS handling

## Part 3 – Data Transfer Optimization
- How would you optimize uploads and downloads of large drone datasets?
- Discuss compression strategies, chunking, parallel transfers, and cloud storage architecture.
- Explain tradeoffs between speed, cost, and reliability.

## Part 4 – File Size Optimization
- Explain how you would reduce orthomosaic file sizes without significantly degrading quality.
- Discuss tiling, pyramids, compression (LZW, JPEG, DEFLATE), and Cloud Optimized GeoTIFF (COG).
- Explain when you would prioritize size vs precision.

var wms_layers = [];


        var lyr_GoogleSatellite_0 = new ol.layer.Tile({
            'title': 'Google Satellite',
            'opacity': 1.000000,
            
            
            source: new ol.source.XYZ({
            attributions: '&nbsp;&middot; <a href="https://www.google.at/permissions/geoguidelines/attr-guide.html">Map data ©2015 Google</a>',
                url: 'https://mt1.google.com/vt/lyrs=s&x={x}&y={y}&z={z}'
            })
        });
var lyr_rgb_orthomosaic_cog_1 = new ol.layer.Image({
        opacity: 1,
        
    title: 'rgb_orthomosaic_cog<br />' ,
        
        
        source: new ol.source.ImageStatic({
            url: "./layers/rgb_orthomosaic_cog_1.png",
            attributions: ' ',
            projection: 'EPSG:3857',
            alwaysInRange: true,
            imageExtent: [4038715.889429, -79300.065302, 4039422.352794, -78500.650560]
        })
    });
var lyr_VegetationHealthNDVI_2 = new ol.layer.Image({
        opacity: 1,
        
    title: 'Vegetation Health (NDVI)<br />' ,
        
        
        source: new ol.source.ImageStatic({
            url: "./layers/VegetationHealthNDVI_2.png",
            attributions: ' ',
            projection: 'EPSG:3857',
            alwaysInRange: true,
            imageExtent: [4038741.478006, -79363.837194, 4039373.344487, -78539.507351]
        })
    });

lyr_GoogleSatellite_0.setVisible(true);lyr_rgb_orthomosaic_cog_1.setVisible(true);lyr_VegetationHealthNDVI_2.setVisible(true);
var layersList = [lyr_GoogleSatellite_0,lyr_rgb_orthomosaic_cog_1,lyr_VegetationHealthNDVI_2];

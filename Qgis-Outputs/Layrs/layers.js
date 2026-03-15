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
var lyr_ndvi_colored_cog_2 = new ol.layer.Image({
        opacity: 1,
        
    title: 'ndvi_colored_cog<br />' ,
        
        
        source: new ol.source.ImageStatic({
            url: "./layers/ndvi_colored_cog_2.png",
            attributions: ' ',
            projection: 'EPSG:3857',
            alwaysInRange: true,
            imageExtent: [4038765.281288, -79269.566043, 4039391.100256, -78532.967690]
        })
    });
var lyr_Clippedmask_3 = new ol.layer.Image({
        opacity: 1,
        
    title: 'Clipped (mask)<br />' ,
        
        
        source: new ol.source.ImageStatic({
            url: "./layers/Clippedmask_3.png",
            attributions: ' ',
            projection: 'EPSG:3857',
            alwaysInRange: true,
            imageExtent: [4038741.478006, -79363.837194, 4039373.344487, -78539.507351]
        })
    });
var format_Fixedgeometries_4 = new ol.format.GeoJSON();
var features_Fixedgeometries_4 = format_Fixedgeometries_4.readFeatures(json_Fixedgeometries_4, 
            {dataProjection: 'EPSG:4326', featureProjection: 'EPSG:3857'});
var jsonSource_Fixedgeometries_4 = new ol.source.Vector({
    attributions: ' ',
});
jsonSource_Fixedgeometries_4.addFeatures(features_Fixedgeometries_4);
var lyr_Fixedgeometries_4 = new ol.layer.Vector({
                declutter: false,
                source:jsonSource_Fixedgeometries_4, 
                style: style_Fixedgeometries_4,
                popuplayertitle: 'Fixed geometries',
                interactive: true,
                title: '<img src="styles/legend/Fixedgeometries_4.png" /> Fixed geometries'
            });

lyr_GoogleSatellite_0.setVisible(true);lyr_rgb_orthomosaic_cog_1.setVisible(true);lyr_ndvi_colored_cog_2.setVisible(true);lyr_Clippedmask_3.setVisible(true);lyr_Fixedgeometries_4.setVisible(true);
var layersList = [lyr_GoogleSatellite_0,lyr_rgb_orthomosaic_cog_1,lyr_ndvi_colored_cog_2,lyr_Clippedmask_3,lyr_Fixedgeometries_4];
lyr_Fixedgeometries_4.set('fieldAliases', {'fid': 'fid', });
lyr_Fixedgeometries_4.set('fieldImages', {'fid': '', });
lyr_Fixedgeometries_4.set('fieldLabels', {'fid': 'no label', });
lyr_Fixedgeometries_4.on('precompose', function(evt) {
    evt.context.globalCompositeOperation = 'normal';
});
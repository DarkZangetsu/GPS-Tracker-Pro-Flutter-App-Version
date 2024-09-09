-- Création de la table pour stocker les données de géolocalisation
CREATE TABLE locations (
    id BIGSERIAL PRIMARY KEY,
    device_id UUID NOT NULL,
    device_name TEXT,  -- Nouvelle colonne pour le nom de l'appareil
    latitude DOUBLE PRECISION NOT NULL,
    longitude DOUBLE PRECISION NOT NULL,
    altitude DOUBLE PRECISION,
    accuracy DOUBLE PRECISION,
    speed DOUBLE PRECISION,
    timestamp TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- Création d'un index sur device_id pour des requêtes plus rapides
CREATE INDEX idx_locations_device_id ON locations(device_id);

-- Création d'un index sur timestamp pour des requêtes plus rapides
CREATE INDEX idx_locations_timestamp ON locations(timestamp);

-- Création d'un index sur device_name pour des requêtes plus rapides
CREATE INDEX idx_locations_device_name ON locations(device_name);

-- Activation de l'extension PostGIS pour des fonctionnalités géospatiales avancées
CREATE EXTENSION IF NOT EXISTS postgis;

-- Ajout d'une colonne de géométrie pour des requêtes spatiales efficaces
ALTER TABLE locations ADD COLUMN geom GEOGRAPHY(POINT, 4326);

-- Création d'un trigger pour remplir automatiquement la colonne geom
CREATE OR REPLACE FUNCTION update_geom()
RETURNS TRIGGER AS $$
BEGIN
    NEW.geom = ST_SetSRID(ST_MakePoint(NEW.longitude, NEW.latitude), 4326)::geography;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER update_locations_geom
BEFORE INSERT OR UPDATE ON locations
FOR EACH ROW EXECUTE FUNCTION update_geom();

-- Création d'un index spatial pour des requêtes géographiques plus rapides
CREATE INDEX idx_locations_geom ON locations USING GIST(geom);
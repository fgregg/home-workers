PG_DB=home_workers
CULTURAL_CENTER=-87.56374, 41.76832

define check_relation
 psql -d $(PG_DB) -c "\d $@" > /dev/null 2>&1 ||
endef

db :
	createdb $(PG_DB)
	psql -d $(PG_DB) -c "CREATE EXTENSION postgis"
	psql -d $(PG_DB) -c "INSERT INTO \"spatial_ref_sys\" (\"srid\", \"auth_name\", \"auth_srid\", \"srtext\", \"proj4text\") VALUES (102671, 'ESRI', 102671, 'PROJCS[\"NAD_1983_StatePlane_Illinois_East_FIPS_1201_Feet\",GEOGCS[\"GCS_North_American_1983\",DATUM[\"D_North_American_1983\",SPHEROID[\"GRS_1980\",6378137,298.257222101]],PRIMEM[\"Greenwich\",0],UNIT[\"Degree\",0.017453292519943295]],PROJECTION[\"Transverse_Mercator\"],PARAMETER[\"False_Easting\",984249.9999999999],PARAMETER[\"False_Northing\",0],PARAMETER[\"Central_Meridian\",-88.33333333333333],PARAMETER[\"Scale_Factor\",0.999975],PARAMETER[\"Latitude_Of_Origin\",36.66666666666666],UNIT[\"Foot_US\",0.30480060960121924]]', '+proj=tmerc +lat_0=36.66666666666666 +lon_0=-88.33333333333333 +k=0.999975 +x_0=300000 +y_0=0 +ellps=GRS80 +datum=NAD83 +to_meter=0.3048006096012192')"

licenses.csv :
	wget -O $@ https://data.cityofchicago.org/api/views/r5kz-chrr/rows.csv?accessType=DOWNLOAD

licenses : licenses.csv
	$(check_relation) (psql -d $(PG_DB) -c "CREATE TABLE $@ \
                                                (ID TEXT, \
                                                 LICENSE_ID TEXT, \
                                                 ACCOUNT_NUMBER TEXT, \
                                                 SITE_NUMBER TEXT, \
                                                 LEGAL_NAME TEXT, \
                                                 DOING_BUSINESS_AS_NAME TEXT, \
                                                 ADDRESS TEXT, \
                                                 CITY TEXT, \
                                                 STATE TEXT, \
                                                 ZIP_CODE TEXT, \
                                                 WARD TEXT, \
                                                 PRECINCT TEXT, \
                                                 POLICE_DISTRICT TEXT, \
                                                 LICENSE_CODE TEXT, \
                                                 LICENSE_DESCRIPTION TEXT, \
                                                 LICENSE_NUMBER TEXT, \
                                                 APPLICATION_TYPE TEXT, \
                                                 APPLICATION_CREATED_DATE DATE, \
                                                 APPLICATION_REQUIREMENTS_COMPLETE DATE, \
                                                 PAYMENT_DATE DATE, \
                                                 CONDITIONAL_APPROVAL TEXT, \
                                                 LICENSE_TERM_START_DATE DATE, \
                                                 LICENSE_TERM_EXPIRATION_DATE DATE, \
                                                 LICENSE_APPROVED_FOR_ISSUANCE DATE, \
                                                 DATE_ISSUED DATE, \
                                                 LICENSE_STATUS TEXT, \
                                                 LICENSE_STATUS_CHANGE_DATE DATE, \
                                                 SSA TEXT, \
                                                 LATITUDE TEXT, \
                                                 LONGITUDE TEXT, \
                                                 LOCATION TEXT)" && \
	 cat $< | psql -d $(PG_DB) -c "COPY $@ FROM STDIN WITH CSV HEADER" && \
         psql -d $(PG_DB) -c "SELECT AddGeometryColumn('licenses', 'geom', 4326, 'POINT', 2)" && \
         psql -d $(PG_DB) -c "UPDATE licenses SET geom=ST_SetSRID(ST_MakePoint(longitude::float, latitude::float),4326)")



zoning.zip :
	wget -O $@ "https://data.cityofchicago.org/api/geospatial/7cve-jgbp?method=export&format=Original"

zoning_2016_01.shp : zoning.zip
	unzip $<
	touch $@

zoning : zoning_2016_01.shp
	$(check_relation) shp2pgsql -c -s 102671:4326 $< $@ | psql -d $(PG_DB)


residential_licenses.csv : zoning licenses
	psql -d $(PG_DB) -c "COPY (select DISTINCT ON (account_number) \
                                   legal_name, \
                                   doing_business_as_name, \
                                   address, \
                                   license_description, \
                                   ward, 
                                   ROUND((ST_DISTANCE(ST_SetSRID(ST_MakePoint($(CULTURAL_CENTER)), \
                                                                 4326)::geography, \
                                                      licenses.geom::geography) * 0.000621371)::numeric, \
                                         2) AS miles_from_cultural_center \
                                   FROM licenses INNER join zoning \
                                   ON (ST_Contains(zoning.geom, licenses.geom)) \
                                   WHERE license_term_expiration_date > NOW() \
                                   AND zone_class LIKE 'R%' \
                                   AND ward IN ('5', '6', '7', '8', '10') \
                                   AND license_description NOT IN \
                                        ('Children''s Services Facility License', \
                                         'Tobacco Retail Over Counter', \
                                         'Tavern', \
                                         'Retail Food Establishment', \
                                         'Raffles', \
                                         'Public Garage', \
                                         'Animal Care License', \
                                         'Consumption on Premises - Incidental Activity', \
                                         'Food - Shared Kitchen Long-Term User', \
                                         'Manufacturing Establishments', \
                                         'Motor Vehicle Services License', \
                                         'Peddler License', \
                                         'Package Goods', \
                                         'Music and Dance', \
                                         'Outdoor Patio', \
                                         'Not-For-Profit Club', \
                                         'Filling Station', \
                                         'Public Place of Amusement', \
                                         'Late Hour', \
                                         'Caterer''s Liquor License')) \
                             TO STDOUT CSV HEADER" > $@

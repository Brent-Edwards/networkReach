/*
--Returns the following :
Table
(
  id integer,			-- The edge's ID
  geom geometry, 		-- The geometry (is partial if factor <> 1)
  factor double precision 	-- How much of the original edge (based on length) did we take
);
*/

/*
networkReach parameters:
1: The edge table
2: The cost field in the edgeTable to base calculations on 
3: The geometry field in the edgeTable
4: Id(s) of the starting point(s) in the vertices_tmp table
5: Network reach distance (in units of the edge table cost column)
*/
-- Function: networkreachpartial(regclass, character varying, character varying, integer[], double precision)

-- DROP FUNCTION networkreachpartial(regclass, character varying, character varying, integer[], double precision);

CREATE OR REPLACE FUNCTION networkreachpartial(
    IN edgetable regclass,
    IN costfield character varying,
    IN geomfield character varying,
    IN startnode integer[],
    IN networkreachdistance double precision)
  RETURNS TABLE(id integer, geom geometry, factor double precision) AS
$BODY$
  DECLARE
    i integer;
  BEGIN
    FOREACH i IN ARRAY startnode
    LOOP
	    -- Create a temporary table for the network whilst we process it
	    -- DROP on commit so we do not get problems reusing it again in this session
	    -- BE mods - added DROP TABLE IF EXISTS to avoid errors when the function is called multiple times - ex. UNION queries. SET client_min_messages = error to suppress NOTICE message - ex. tempNetwork does not exist
	    SET client_min_messages = error;
	    DROP TABLE IF EXISTS tempNetwork;
	    CREATE TEMP TABLE tempNetwork
	    (
	      id integer NOT NULL,
	      geom geometry NOT NULL,
	      factor double precision NOT NULL
	    ) 
	    ON COMMIT DROP; 


	    EXECUTE '    
	    INSERT INTO tempNetwork(id, geom, factor)
	    SELECT et.id, et.' || format('%s',geomfield) || ' AS geom, 1 as factor
	    FROM
		(SELECT id1,cost from pgr_drivingDistance(
		  ''SELECT id, source, target, ' || quote_ident(costField) || ' AS cost FROM ' || format('%s',edgeTable) || ''',
		  ' || format('%s',i) || ',' || format('%s', networkReachDistance) || ',false,false)
		 ) firstPath
	    CROSS JOIN 
		(SELECT id1,cost from pgr_drivingDistance(
		  ''SELECT id, source, target, ' || quote_ident(costField) || ' AS cost FROM ' || format('%s',edgeTable) || ''',
		  ' || format('%s',i) || ',' || format('%s', networkReachDistance) || ',false,false)
		 ) secondPath
	    INNER JOIN ' || format('%s',edgeTable) || ' et 
	    ON firstPath.id1 = et.source
	    AND secondPath.id1 = et.target;';

	    EXECUTE '
	    INSERT INTO tempNetwork(id, geom, factor)
	    SELECT allNodes.id, st_line_substring(allNodes.' || format('%s',geomfield) || ', 0.0, (' || format('%s', networkReachDistance) || '-allNodes.distance)/allNodes.Cost) AS geom, (' || format('%s', networkReachDistance) || '-allNodes.distance)/allNodes.Cost AS factor
	    FROM
	      (SELECT reachNodes.id1, et.id, et.cost, reachNodes.cost distance, et.' || format('%s',geomfield) || '
	       FROM
		 (SELECT id1, cost FROM pgr_drivingDistance(
		 ''SELECT id, source, target, ' || quote_ident(costField) || ' AS cost FROM ' || format('%s',edgeTable) || ''',
		 ' || format('%s',i) || ',' || format('%s', networkReachDistance) || ',false,false)
		 ) reachNodes
	      JOIN (SELECT p.id, p.target, p.source, p.' || quote_ident(costField) || ' AS cost, p.' || format('%s',geomfield) || ' FROM ' || format('%s',edgeTable) || ' p) et ON reachNodes.id1 = et.source
	      ORDER BY reachNodes.id1
	     ) allNodes
	    FULL OUTER JOIN tempNetwork
	    ON tempNetwork.id = allNodes.id
	    WHERE tempNetwork.id IS NULL;';

	    EXECUTE '
	    INSERT INTO tempNetwork(id, geom, factor)
	    SELECT allNodes.id, st_line_substring(allNodes.' || format('%s',geomfield) || ',1-((' || format('%s', networkReachDistance) || '-allNodes.distance)/allNodes.Cost),1) AS geom, (' || format('%s', networkReachDistance) || '-allNodes.distance)/allNodes.Cost AS factor
	    FROM
	      (SELECT reachNodes.id1, et.id, et.cost, reachNodes.cost distance, et.' || format('%s',geomfield) || '
	       FROM
		 (SELECT id1, cost FROM pgr_drivingDistance(
		 ''SELECT id, source, target, ' || quote_ident(costField) || ' AS cost FROM ' || format('%s',edgeTable) || ''',
		 ' || format('%s',i) || ',' || format('%s', networkReachDistance) || ',false,false)
		 ) reachNodes
	       JOIN (SELECT p.id, p.target, p.source, p.' || quote_ident(costField) || ' AS cost, p.' || format('%s',geomfield) || ' FROM ' || format('%s',edgeTable) || ' p) et ON reachNodes.id1 = et.target
	       ORDER BY reachNodes.id1
	      ) allNodes
	    FULL OUTER JOIN tempNetwork
	    ON tempNetwork.id = allNodes.id
	    WHERE tempNetwork.id IS NULL;';


	    RETURN QUERY SELECT t.id, t.geom, t.factor FROM tempNetwork t;
    END LOOP;
END;
$BODY$
  LANGUAGE plpgsql VOLATILE
  COST 100
  ROWS 1000;
ALTER FUNCTION networkreachpartial(regclass, character varying, character varying, integer[], double precision)
  OWNER TO postgres;

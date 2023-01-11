create or replace PACKAGE BODY           f1 AS
    v_value VARCHAR2(32000);
    PROCEDURE p1(p_value IN VARCHAR2)  IS
    BEGIN
    v_value := v_value || p_value;
    END p1;
FUNCTION scoreboard (p_competition_series IN NUMBER) RETURN VARCHAR2 IS
   v_flight_id NUMBER;
   numeric_error EXCEPTION;
   PRAGMA exception_init(numeric_error,-6502);
   TYPE flight_t IS RECORD
   (
       flight_date DATE,
       pilot VARCHAR2(100),
       score NUMBER,
       cancellation_type VARCHAR2(1)  ,
       total_score NUMBER,
       original_score NUMBER,
       crashed VARCHAR2(1), 
       cancelled_points_flight_id NUMBER, 
       competition_flight_id NUMBER
   );
  TYPE flight_array IS TABLE OF flight_t INDEX BY PLS_INTEGER;
  TYPE flight_aa IS TABLE of flight_array INDEX BY PLS_INTEGER;
  v_results flight_aa;
  TYPE score_t IS TABLE OF NUMBER INDEX BY PLS_INTEGER;
  v_total_score score_t;
  v_ranking score_t;
  i PLS_INTEGER;
  p PLS_INTEGER;
  cursor c_tasks is
  SELECT col
  FROM
  (
  SELECT 1 ord, 'ID' || CHR(10) || 'Date' col, TO_DATE('01-JAN-1900', 'dd-mon-yyyy') flight_date
  FROM sys.dual
  UNION
  SELECT 2 ord, id || CHR(10)|| flight_date col, flight_date
  FROM competitions
  )
  ORDER BY ord,flight_date ;
  CURSOR c_details  is
  SELECT 
     competition_flight_id, flight_id, flight_date, pilot, pilot_id, score,
     original_score,  --cancellation_type, 
     total_score,  
     DENSE_RANK() OVER(ORDER BY total_score DESC) rn, 
     crashed, 
     cancelled_points_flight_id
  FROM
  (
  SELECT 
    competition_flight_id, flight_id, flight_date, pilot, pilot_id, score,
    original_score,  --cancellation_type,
    best6 total_score, 
    crashed, cancelled_points_flight_id
  FROM (
    SELECT competition_flight_id, flight_id, flight_date, pilot, pilot_id, score,original_score, 
     --cancellation_type, 
     best6,
                  --SUM(score) OVER(PARTITION BY pilot ORDER BY score DESC ) total_score
  --CASE WHEN (ROW_NUMBER() OVER(PARTITION BY pilot_id ORDER BY score ) ) <=6 THEN score else 0 END best6,
  --ROW_NUMBER() OVER(PARTITION BY pilot_id ORDER BY score DESC) best6rn
    crashed, cancelled_points_flight_id
  FROM
  ( 
     SELECT 
        cf.competition_flight_id, 
        cf.flight_id,
        comp.flight_date,
        cf.pilot_id,
        p.first_name || ' ' || p.second_name pilot,
        cf.score,
        cf.original_score,
        --c.flight_date cancelled_points_date,  
        /* 
        CASE when cancellation_type = 'C' THEN 'Crashed'
        WHEN cancellation_type = 'P' THEN 'Prev Best'
        END cancellation_reason,
        c.cancellation_type, */
        cf.crash crashed, 
        (SELECT SUM(b6.score) FROM best6 b6 where b6.pilot_id = cf.pilot_id) best6,
        cancelled_points_flight_id
    /*,
    ROW_NUMBER() OVER(PARTITION BY p.first_name || ' ' || p.second_name ORDER BY p.first_name || ' ' || p.second_name, c.flight_date DESC ) rn */
from 
(SELECT id 
competition_flight_id,  
flight_id, pilot_id, score,original_score, crash, cancelled_points_flight_id 
FROM competition_flights_tbl
/*WHERE id IN 
(
    SELECT id
    FROM competition_flights_tbl
    MINUS
    SELECT cancelled_points_flight_id
    FROM competition_flights_tbl
)*/
) 
cf 
/*LEFT OUTER JOIN
(SELECT pilot_id, crash_flight_id crash_flight_id, flight_date, 'C' cancellation_type
FROM crashes JOIN competitions ON (crash_flight_id = id)
UNION
SELECT pilot_id, cancelled_points_flight_id crash_flight_id, flight_date, 'P' cancellation_type
FROM crashes JOIN competitions ON (crash_flight_id = id)
)
c ON (c.crash_flight_id = cf.flight_id
AND c.pilot_id = cf.pilot_id)
*/
JOIN pilots p ON (p.id = cf.pilot_id)
JOIN competitions comp ON (comp.id = cf.flight_id)
WHERE EXISTS 
(SELECT 'X' FROM flightlog.competition_dates cd
WHERE comp.flight_date BETWEEN cd.first_flight and cd.last_flight
    AND
cd.id = p_competition_series
-- cd.id = :P0_COMP_SERIES_ORIG
--AND cd.id = :P16_COMPETITION_SERIES
)
) flt
  )
  )
ORDER BY flight_id
  --ORDER BY rn
  --best6rn desc
  ;
    FUNCTION isbest6(p_flight_id IN VARCHAR2, p_pilot_id IN VARCHAR2) RETURN BOOLEAN IS 
        v_true VARCHAR2(5) :='FALSE';
    BEGIN 
        SELECT DISTINCT 'TRUE'
        INTO v_true
        FROM best6
        WHERE pilot_id = p_pilot_id
        AND flight_id = p_flight_id;
        IF v_true = 'TRUE' THEN 
         RETURN TRUE;
        ELSE 
         RETURN FALSE;
        END IF;   
        EXCEPTION WHEN no_data_found THEN RETURN FALSE;
    END isbest6;
    FUNCTION iscancelled(p_flight_id IN NUMBER) RETURN BOOLEAN IS
        v_true VARCHAR2(5) := 'FALSE';
    BEGIN 
        SELECT DISTINCT 'TRUE'
        INTO v_true
        FROM competition_flights_tbl
        WHERE cancelled_points_flight_id = p_flight_id;
        IF v_true = 'TRUE' THEN 
           RETURN TRUE;
        END IF;
    EXCEPTION 
        WHEN no_data_found THEN RETURN FALSE;   

    END iscancelled;
    PROCEDURE header IS 
    BEGIN 
        sys.htp.p('
<html>
<body>
 <style>
table, th, td {
 border: 1px solid black;
 border-collapse: collapse;
}
th, td {
 padding: 15px;
}
</style>
');
   END header;
      PROCEDURE table_header IS
   BEGIN 
      sys.htp.p('<table style="width:100%">');
      sys.htp.p('<tr>');
   --sys.htp.p('<th>' || v_flight_id || '</th>' );
  sys.htp.p('<th style="background-color:#0000FF;color:white;font-weight: bold">Rank</th>' );
--v_results(v_results.LAST).flight_date
  sys.htp.p('<th style="background-color:#0000FF;color:white;font-weight: bold">Total</th>' );

  sys.htp.p('<th style="background-color:#0000FF;color:white;font-weight:bold">');
  sys.htp.p('Pilot');
  sys.htp.p('</th>');
   FOR flt IN
   (
       SELECT id flight_id, flight_date
       FROM  competitions 
       ORDER BY flight_date DESC
   ) LOOP
/*   
   i := v_results.FIRST;
   p := v_results(i).FIRST;
   */
--    sys.htp.p('i=' ||i ||' p='|| p || ' array: ' || v_results(i)(p).pilot || '</tr>');
       sys.htp.p('<th style="background-color:#0000FF;color:white;font-weight:bold">' || TO_CHAR(flt.flight_date, 'DD/MM/YY')  || '</th>' );
/*
   BEGIN
   <<label1>>
   WHILE i IS NOT NULL and p IS NOT NULL LOOP

      sys.htp.p('<th>' || v_results(i)(p).flight_date  || '</th>' );
       i := v_results.next(i);
       p := v_results(i).FIRST;
       --    sys.htp.p('flight: ' || i || ' pilot:' || p  || v_results(i)(p).pilot|| '</tr><tr>');
       --EXIT label1;
   END LOOP;
   EXCEPTION WHEN numeric_error THEN NULL;
   END;  
*/
   END LOOP;
   sys.htp.p( '</tr>');
   END table_header;
BEGIN
    v_value := '';
   --header;
   --table_header;
    FOR a IN c_details LOOP
        v_results(a.flight_id)(a.pilot_id).flight_date := a.flight_date;
        v_results(a.flight_id)(a.pilot_id).pilot := a.pilot;
        v_results(a.flight_id)(a.pilot_id).score := a.score;
        --v_results(a.flight_id)(a.pilot_id).cancellation_type := a.cancellation_type;
        v_results(a.flight_id)(a.pilot_id).total_score := a.total_score;
        v_results(a.flight_id)(a.pilot_id).original_score := a.original_score;
        v_results(a.flight_id)(a.pilot_id).crashed := a.crashed;
        v_results(a.flight_id)(a.pilot_id).cancelled_points_flight_id := a.cancelled_points_flight_id;
        v_results(a.flight_id)(a.pilot_id).competition_flight_id := a.competition_flight_id;
--      v_results(a.flight_id)(a.pilot_id).best6rn := a.best6rn;
        v_total_score(a.pilot_id) := a.total_score;
      IF a.rn IS NOT NULL THEN
         v_ranking(a.pilot_id) := a.rn;
      END IF;  
   END LOOP;
   FOR p IN
   (
       SELECT DISTINCT pilot_id, pilot_name, rn rnk
       FROM
       (
          SELECT flight_id, flight_date, pilot pilot_name, pilot_id, score,original_score,  --cancellation_type, 
          total_score, 
  DENSE_RANK() OVER(ORDER BY total_score DESC) rn
  FROM
  (
  SELECT flight_id, flight_date, pilot, pilot_id, score,original_score,  --cancellation_type,
  best6 total_score
  FROM (
  SELECT flt.flight_id, flt.flight_date, flt.pilot, flt.pilot_id, flt.score, flt.original_score, -- cancellation_type,
                  --SUM(score) OVER(PARTITION BY pilot ORDER BY score DESC ) total_score
  --CASE WHEN (ROW_NUMBER() OVER(PARTITION BY pilot_id ORDER BY score DESC ) ) <=6 THEN score else 0 END
  (SELECT SUM(b6.score) FROM best6 b6 where b6.pilot_id = flt.pilot_id)
   best6
  --ROW_NUMBER() OVER(PARTITION BY pilot_id ORDER BY score DESC ) best6rn
  FROM
  ( 
    select 
        cf.flight_id,
        comp.flight_date,
        cf.pilot_id,
        p.first_name || ' ' || p.second_name pilot,
        cf.score,
        cf.original_score--,
        --,   
    /*
    CASE when cf.cancellation_type = 'C' THEN 'Crashed'
    WHEN cf.cancellation_type = 'P' THEN 'Prev Best'
    END
    cancellation_reason,
    */
    --cf.cancellation_type
    /*,
    ROW_NUMBER() OVER(PARTITION BY p.first_name || ' ' || p.second_name ORDER BY p.first_name || ' ' || p.second_name, c.flight_date DESC ) rn */
from competition_flights_tbl cf  
/*(SELECT pilot_id, crash_flight_id crash_flight_id, flight_date, 'C' cancellation_type
FROM crashes JOIN competitions ON (crash_flight_id = id)
UNION
SELECT pilot_id, cancelled_points_flight_id crash_flight_id, flight_date, 'P' cancellation_type
FROM crashes JOIN competitions ON (crash_flight_id = id)
)
c ON (c.crash_flight_id = cf.flight_id
AND c.pilot_id = cf.pilot_id)
*/
JOIN pilots p ON (p.id = cf.pilot_id)
JOIN competitions comp ON (comp.id = cf.flight_id)
) flt
  )
  )
       )
--        WHERE pilot_name NOT IN( 'Mitchell Skene', 'Kate Byrne', 'Colin Hamilton','Adrian D')
ORDER BY rnk
       /*
       SELECT p.id pilot_id, p.first_name || ' '|| p.second_name pilot_name
       FROM pilots p
       ORDER BY p.second_name, p.first_name */
   ) LOOP
       p1('<tr style="height:30px;text-align:center">');
       p1('<td>');
       p1(p.rnk
           --v_ranking(p.pilot_id)
           );
       p1('</td><td style="text-align:right">' );
       p1(TO_CHAR(v_total_score(p.pilot_id),'9999.9'));
       p1('</td><td style="white-space:nowrap;text-align:left">');
       p1(p.pilot_name );
       p1('</td>');
      --   sys.htp.p('<td>' || v_results(v_flight_id)(p.pilot_id).total_score || '</td>' );
/* Start here
FOR flt IN
       (      
           SELECT id flight_id, flight_date
           FROM  competitions 
           ORDER BY flight_date DESC
       ) LOOP
         BEGIN
--style="background-color:#0000FF;color:white;font-weight: bold"
           IF NVL(v_results(flt.flight_id)(p.pilot_id).crashed, 'N') = 'Y' THEN 
           --v_results(flt.flight_id)(p.pilot_id).cancellation_type = 'C' THEN
              sys.htp.p('<td style="text-align:right;color:red"><del>' ||
              v_results(flt.flight_id)(p.pilot_id).original_score  || '</del></td>' );
           ELSIF iscancelled(v_results(flt.flight_id)(p.pilot_id).competition_flight_id)  THEN
           --v_results(flt.flight_id)(p.pilot_id).cancellation_type = 'P' THEN
              sys.htp.p('<td style="text-align:right;color:orange"><del>' ||
              v_results(flt.flight_id)(p.pilot_id).original_score  || '</del></td>' );
           ELSIF isbest6(flt.flight_id, p.pilot_id) THEN    
           --ELSIF v_results(flt.flight_id)(p.pilot_id).best6rn <=6 THEN
              sys.htp.p('<td style="text-align:right;color:green;font-weight:bold">' || v_results(flt.flight_id)(p.pilot_id).score  || '</td>' );
           ELSE
              sys.htp.p('<td style="text-align:right;color:black">' || v_results(flt.flight_id)(p.pilot_id).score  || '</td>' );
           END IF;
           --sys.htp.p('<br> Flt:' || v_results(flt.flight_id)(p.pilot_id).competition_flight_id ||'<BR>');
           --sys.htp.p('<br> Canc:' || v_results(flt.flight_id)(p.pilot_id).cancelled_points_flight_id ||'<BR>');
           --dbms_output.put_line('cfid: ' || v_results(flt.flight_id)(p.pilot_id).competition_flight_id );
           --|| ' cancfid:' || v_results(flt.flight_id)(p.pilot_id).cancelled_points_flight_id);

           EXCEPTION
               WHEN no_data_found THEN
                   sys.htp.p('<td> </td>' );
           END;       
           --dbms_output.put_line('cfid: ' || v_results(flt.flight_id)(p.pilot_id).competition_flight_id || ' cancfid:' || v_results(flt.flight_id)(p.pilot_id).cancelled_points_flight_id);
       END LOOP;
       sys.htp.p('</tr>' );
   END LOOP;
   /*
   BEGIN
   WHILE i IS NOT NULL and p IS NOT NULL LOOP
       sys.htp.p('<td>' || v_results(i)(p).score  || '</td>' );
       i := v_results.next(i);
       p := v_results(i).FIRST;
   END LOOP;
       EXCEPTION WHEN numeric_error THEN NULL;
   END;  
*/    
/*   
   for a in c_tasks loop
      sys.htp.p('<th>' || a.col || '</th>' );
   end loop;
   sys.htp.p('</tr>');
   --sys.htp.p('<td> </td>');
   FOR a IN (
   SELECT id pilot_id, first_name || ' ' || second_name pilot FROM pilots
   ) LOOP
     sys.htp.p('<tr>');
     sys.htp.p('<td>' || a.pilot || '</td>');
     FOR s_rec IN c_details (a.pilot_id) LOOP
     sys.htp.p('<td>' || s_rec.score);
     sys.htp.p('</td>');

     END LOOP;
     sys.htp.p('</tr>');
   END LOOP;
*/
/*
  FOR a IN c_details
  (
      SELECT  flight_date
      FROM competitions
      ORDER BY flight_date
  )
  LOOP
     sys.htp.p('<td>' || a.flight_date || '</td>');
  END LOOP;
*/
--  sys.htp.p('</tr>');
  p1('</table></body></html>');
       END LOOP;
       RETURN v_value;
END scoreboard;
END f1;

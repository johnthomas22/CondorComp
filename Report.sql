--
-- Package "REPORT"
--
CREATE OR REPLACE EDITIONABLE PACKAGE "FLIGHTLOG"."REPORT" AS
    PROCEDURE SCOREBOARD (
        P_COMPETITION_SERIES IN COMPETITIONS.ID%TYPE
    );

END REPORT;

CREATE OR REPLACE EDITIONABLE PACKAGE BODY "FLIGHTLOG"."REPORT" AS

    PROCEDURE SCOREBOARD (
        P_COMPETITION_SERIES IN COMPETITIONS.ID%TYPE
    ) IS

        V_FLIGHT_ID    NUMBER;
        NUMERIC_ERROR EXCEPTION;
        PRAGMA EXCEPTION_INIT ( NUMERIC_ERROR, -6502 );
        TYPE FLIGHT_T IS RECORD (
            FLIGHT_DATE                 DATE,
            PILOT                       VARCHAR2(100),
            SCORE                       NUMBER,
            CANCELLATION_TYPE           VARCHAR2(1),
            TOTAL_SCORE                 NUMBER,
            ORIGINAL_SCORE              NUMBER,
            CRASHED                     VARCHAR2(1),
            CANCELLED_POINTS_FLIGHT_ID  NUMBER,
            COMPETITION_FLIGHT_ID       NUMBER
        );
        TYPE FLIGHT_ARRAY IS
            TABLE OF FLIGHT_T INDEX BY PLS_INTEGER;
        TYPE FLIGHT_AA IS
            TABLE OF FLIGHT_ARRAY INDEX BY PLS_INTEGER;
        V_RESULTS      FLIGHT_AA;
        TYPE SCORE_T IS
            TABLE OF NUMBER INDEX BY PLS_INTEGER;
        V_TOTAL_SCORE  SCORE_T;
        V_RANKING      SCORE_T;
        I              PLS_INTEGER;
        P              PLS_INTEGER;


        CURSOR C_DETAILS IS
        SELECT
            COMPETITION_FLIGHT_ID,
            FLIGHT_ID,
            FLIGHT_DATE,
            PILOT,
            PILOT_ID,
            SCORE,
            ORIGINAL_SCORE,  --cancellation_type, 
            TOTAL_SCORE,
            DENSE_RANK()
            OVER(
                ORDER BY TOTAL_SCORE DESC
            ) RN,
            CRASHED,
            CANCELLED_POINTS_FLIGHT_ID
        FROM
            (
                SELECT
                    COMPETITION_FLIGHT_ID,
                    FLIGHT_ID,
                    FLIGHT_DATE,
                    PILOT,
                    PILOT_ID,
                    SCORE,
                    ORIGINAL_SCORE,  --cancellation_type,
                    BEST6 TOTAL_SCORE,
                    CRASHED,
                    CANCELLED_POINTS_FLIGHT_ID
                FROM
                    (
                        SELECT
                            COMPETITION_FLIGHT_ID,
                            FLIGHT_ID,
                            FLIGHT_DATE,
                            PILOT,
                            PILOT_ID,
                            SCORE,
                            ORIGINAL_SCORE, 
     --cancellation_type, 
                            BEST6,
                  --SUM(score) OVER(PARTITION BY pilot ORDER BY score DESC ) total_score
  --CASE WHEN (ROW_NUMBER() OVER(PARTITION BY pilot_id ORDER BY score ) ) <=6 THEN score else 0 END best6,
  --ROW_NUMBER() OVER(PARTITION BY pilot_id ORDER BY score DESC) best6rn
                            CRASHED,
                            CANCELLED_POINTS_FLIGHT_ID
                        FROM
                            (
                                SELECT
                                    CF.COMPETITION_FLIGHT_ID,
                                    CF.FLIGHT_ID,
                                    COMP.FLIGHT_DATE,
                                    CF.PILOT_ID,
                                    P.FIRST_NAME
                                    || ' '
                                    || P.SECOND_NAME     PILOT,
                                    CF.SCORE,
                                    CF.ORIGINAL_SCORE,
        --c.flight_date cancelled_points_date,  
        /* 
        CASE when cancellation_type = 'C' THEN 'Crashed'
        WHEN cancellation_type = 'P' THEN 'Prev Best'
        END cancellation_reason,
        c.cancellation_type, */
                                    CF.CRASH             CRASHED,
                                    (
                                        SELECT
                                            SUM(B6.SCORE)
                                        FROM
                                            BEST6 B6
                                        WHERE
                                            B6.PILOT_ID = CF.PILOT_ID
                                        AND b6.competition_series_id = p_competition_series
                                    )                    BEST6,
                                    CANCELLED_POINTS_FLIGHT_ID
    /*,
    ROW_NUMBER() OVER(PARTITION BY p.first_name || ' ' || p.second_name ORDER BY p.first_name || ' ' || p.second_name, c.flight_date DESC ) rn */
                                FROM
                                    (
                                        SELECT
                                            ID COMPETITION_FLIGHT_ID,
                                            FLIGHT_ID,
                                            PILOT_ID,
                                            SCORE,
                                            ORIGINAL_SCORE,
                                            CRASH,
                                            CANCELLED_POINTS_FLIGHT_ID
                                        FROM
                                            COMPETITION_FLIGHTS_TBL
/*WHERE id IN 
(
    SELECT id
    FROM competition_flights_tbl
    MINUS
    SELECT cancelled_points_flight_id
    FROM competition_flights_tbl
)*/
                                    ) CF 
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
                                    JOIN PILOTS        P ON ( P.ID = CF.PILOT_ID )
                                    JOIN COMPETITIONS  COMP ON ( COMP.ID = CF.FLIGHT_ID )
                                WHERE
                                    EXISTS (
                                        SELECT
                                            'X'
                                        FROM
                                            COMPETITION_DATES CD
                                        WHERE
                                            COMP.FLIGHT_DATE BETWEEN CD.FIRST_FLIGHT AND CD.LAST_FLIGHT
                                            AND CD.ID = P_COMPETITION_SERIES
                                    )
                            ) FLT
                    )
            )
        ORDER BY
            FLIGHT_ID
  --ORDER BY rn
  --best6rn desc
            ;

        FUNCTION ISBEST6 (
            P_FLIGHT_ID  IN  VARCHAR2,
            P_PILOT_ID   IN  VARCHAR2
        ) RETURN BOOLEAN IS
            V_TRUE VARCHAR2(5) := 'FALSE';
        BEGIN
            SELECT DISTINCT
                'TRUE'
            INTO V_TRUE
            FROM
                BEST6
            WHERE
                PILOT_ID = P_PILOT_ID
                AND FLIGHT_ID = P_FLIGHT_ID;

            IF V_TRUE = 'TRUE' THEN
                RETURN TRUE;
            ELSE
                RETURN FALSE;
            END IF;
        EXCEPTION
            WHEN NO_DATA_FOUND THEN
                RETURN FALSE;
        END ISBEST6;

        FUNCTION ISCANCELLED (
            P_FLIGHT_ID IN NUMBER
        ) RETURN BOOLEAN IS
            V_TRUE VARCHAR2(5) := 'FALSE';
        BEGIN
            SELECT DISTINCT
                'TRUE'
            INTO V_TRUE
            FROM
                COMPETITION_FLIGHTS_TBL
            WHERE
                CANCELLED_POINTS_FLIGHT_ID = P_FLIGHT_ID;

            IF V_TRUE = 'TRUE' THEN
                RETURN TRUE;
            END IF;
        EXCEPTION
            WHEN NO_DATA_FOUND THEN
                RETURN FALSE;
        END ISCANCELLED;

        PROCEDURE HEADER IS
        BEGIN
            SYS.HTP.P('
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
ex2 {
 width: 70px;
 max-width: 80px;
}
</style>
');
        END HEADER;

        PROCEDURE TABLE_HEADER  (
        P_COMPETITION_SERIES IN COMPETITIONS.ID%TYPE
    ) IS
        BEGIN
            SYS.HTP.P('<table>');
            --SYS.HTP.P('<table style="width:100%">');
            --SYS.HTP.P('<colgroup style="width:100%">');
            SYS.HTP.P('<tr>');
   --sys.htp.p('<th>' || v_flight_id || '</th>' );
            SYS.HTP.P('<th style="background-color:#0000FF;color:white;font-weight:bold">Rank</th>');
--v_results(v_results.LAST).flight_date
            SYS.HTP.P('<th style="background-color:#0000FF;color:white;font-weight:bold">Total</th>');
            SYS.HTP.P('<th style="background-color:#0000FF;color:white;font-weight:bold">');
            SYS.HTP.P('Pilot');
            SYS.HTP.P('</th>');
            FOR FLT IN (
                SELECT
                    C.ID FLIGHT_ID,
                    C.FLIGHT_DATE
                FROM
                    COMPETITIONS C
                    JOIN COMPETITION_DATES CD ON ( C.FLIGHT_DATE BETWEEN CD.FIRST_FLIGHT AND CD.LAST_FLIGHT )
                WHERE
                    CD.ID = P_COMPETITION_SERIES
                ORDER BY
                    FLIGHT_DATE DESC
            ) LOOP
                SYS.HTP.P('<th style="background-color:#0000FF;color:white;font-weight:bold">'
                          || TO_CHAR(
                                    FLT.FLIGHT_DATE,
                                    'DD/MM/YY'
                             )
                          || '</th>');
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

            SYS.HTP.P('</tr>');
        END TABLE_HEADER;

    BEGIN
        HEADER;
        TABLE_HEADER(p_competition_series);

 --  sys.htp.p('<table style="width:100%">'); --<tr>
--   sys.htp.p('<tr>');

        BEGIN
            FOR A IN C_DETAILS LOOP
                V_RESULTS(A.FLIGHT_ID)(A.PILOT_ID).FLIGHT_DATE := A.FLIGHT_DATE;

                V_RESULTS(A.FLIGHT_ID)(A.PILOT_ID).PILOT := A.PILOT;

                V_RESULTS(A.FLIGHT_ID)(A.PILOT_ID).SCORE := A.SCORE;
        --v_results(a.flight_id)(a.pilot_id).cancellation_type := a.cancellation_type;
                V_RESULTS(A.FLIGHT_ID)(A.PILOT_ID).TOTAL_SCORE := A.TOTAL_SCORE;

                V_RESULTS(A.FLIGHT_ID)(A.PILOT_ID).ORIGINAL_SCORE := A.ORIGINAL_SCORE;

                V_RESULTS(A.FLIGHT_ID)(A.PILOT_ID).CRASHED := A.CRASHED;

                V_RESULTS(A.FLIGHT_ID)(A.PILOT_ID).CANCELLED_POINTS_FLIGHT_ID := A.CANCELLED_POINTS_FLIGHT_ID;

                V_RESULTS(A.FLIGHT_ID)(A.PILOT_ID).COMPETITION_FLIGHT_ID := A.COMPETITION_FLIGHT_ID;
--      v_results(a.flight_id)(a.pilot_id).best6rn := a.best6rn;
                V_TOTAL_SCORE(A.PILOT_ID) := A.TOTAL_SCORE;
                IF A.RN IS NOT NULL THEN
                    V_RANKING(A.PILOT_ID) := A.RN;
                END IF;

            END LOOP;
        EXCEPTION
            WHEN NO_DATA_FOUND THEN
                NULL;
        END;

        FOR P IN (
            WITH BESTOF6 AS (
                SELECT
                    B6.PILOT_ID                  PILOT_ID,
                    B6.COMPETITION_FLIGHTS_ID    COMPETITION_FLIGHTS_ID,
                    B6.FLIGHT_ID                 FLIGHT_ID,
                    B6.SCORE                     SCORE
                FROM
                    FLIGHTLOG.BEST6 B6
                    JOIN FLIGHTLOG.COMPETITIONS         C ON ( B6.FLIGHT_ID = C.ID )
                    JOIN FLIGHTLOG.COMPETITION_DATES    CD ON ( C.FLIGHT_DATE BETWEEN CD.FIRST_FLIGHT AND CD.LAST_FLIGHT )
                WHERE
                    CD.ID = P_COMPETITION_SERIES
            )
            SELECT DISTINCT
                PILOT_ID,
                PILOT_NAME,
                RN RNK
            FROM
                (
                    SELECT
                        FLIGHT_ID,
                        FLIGHT_DATE,
                        PILOT  PILOT_NAME,
                        PILOT_ID,
                        SCORE,
                        ORIGINAL_SCORE,  --cancellation_type, 
                        TOTAL_SCORE,
                        DENSE_RANK()
                        OVER(
                            ORDER BY TOTAL_SCORE DESC
                        )      RN
                    FROM
                        (
                            SELECT
                                FLIGHT_ID,
                                FLIGHT_DATE,
                                PILOT,
                                PILOT_ID,
                                SCORE,
                                ORIGINAL_SCORE,  --cancellation_type,
                                BEST6 TOTAL_SCORE
                            FROM
                                (
                                    SELECT
                                        FLT.FLIGHT_ID,
                                        FLT.FLIGHT_DATE,
                                        FLT.PILOT,
                                        FLT.PILOT_ID,
                                        FLT.SCORE,
                                        FLT.ORIGINAL_SCORE, -- cancellation_type,
                  --SUM(score) OVER(PARTITION BY pilot ORDER BY score DESC ) total_score
  --CASE WHEN (ROW_NUMBER() OVER(PARTITION BY pilot_id ORDER BY score DESC ) ) <=6 THEN score else 0 END
                                        (
                                            SELECT
                                                NVL(SUM(B6.SCORE),0) 
                                            FROM
                                                BESTOF6 B6
                                            WHERE
                                                B6.PILOT_ID = FLT.PILOT_ID
                                        ) BEST6
  --ROW_NUMBER() OVER(PARTITION BY pilot_id ORDER BY score DESC ) best6rn
                                    FROM
                                        (
                                            SELECT
                                                CF.FLIGHT_ID,
                                                COMP.FLIGHT_DATE,
                                                CF.PILOT_ID,
                                                P.FIRST_NAME
                                                || ' '
                                                || P.SECOND_NAME PILOT,
                                                CF.SCORE,
                                                CF.ORIGINAL_SCORE--,
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
                                            FROM
                                                COMPETITION_FLIGHTS_TBL CF  
/*(SELECT pilot_id, crash_flight_id crash_flight_id, flight_date, 'C' cancellation_type
FROM crashes JOIN competitions ON (crash_flight_id = id)
UNION
SELECT pilot_id, cancelled_points_flight_id crash_flight_id, flight_date, 'P' cancellation_type
FROM crashes JOIN competitions ON (crash_flight_id = id)
)
c ON (c.crash_flight_id = cf.flight_id
AND c.pilot_id = cf.pilot_id)
*/
                                                JOIN PILOTS        P ON ( P.ID = CF.PILOT_ID )
                                                JOIN COMPETITIONS  COMP ON ( COMP.ID = CF.FLIGHT_ID )
                                        ) FLT
                                )
                        )
                )
            ORDER BY
                RNK

        ) LOOP
            SYS.HTP.P('<tr style="height:30px;text-align:center">');
            SYS.HTP.P('<td>');
            SYS.HTP.P(P.RNK
           --v_ranking(p.pilot_id)
            );
            SYS.HTP.P('</td><td class="ex2" style="text-align:right;">');
            IF V_TOTAL_SCORE.FIRST IS NOT NULL 
 THEN
BEGIN
                SYS.HTP.P(TO_CHAR(
                                 V_TOTAL_SCORE(P.PILOT_ID),
                                 '9999.9'));
EXCEPTION WHEN no_data_found then null; 
    END;
     END IF;

            SYS.HTP.P('</td><td style="white-space:nowrap;text-align:left">');
            SYS.HTP.P(P.PILOT_NAME);
            SYS.HTP.P('</td>');

      --   sys.htp.p('<td>' || v_results(v_flight_id)(p.pilot_id).total_score || '</td>' );

            FOR FLT IN (
                SELECT
                    C.ID FLIGHT_ID,
                    C.FLIGHT_DATE
                FROM
                    COMPETITIONS C
                    JOIN FLIGHTLOG.COMPETITION_DATES CD ON ( C.FLIGHT_DATE BETWEEN CD.FIRST_FLIGHT AND CD.LAST_FLIGHT )
                WHERE
                    CD.ID = P_COMPETITION_SERIES
                ORDER BY
                    FLIGHT_DATE DESC
            ) LOOP

 /*
   i := v_results.FIRST;
   p := v_results(i).FIRST;
*/ 
    --IF v_results.FIRST IS NULL THEN      
                BEGIN
--style="background-color:#0000FF;color:white;font-weight: bold"
                    IF NVL(
                          V_RESULTS(FLT.FLIGHT_ID)(P.PILOT_ID).CRASHED,
                          'N'
                       ) = 'Y' THEN 
           --v_results(flt.flight_id)(p.pilot_id).cancellation_type = 'C' THEN
                        SYS.HTP.P('<td style="text-align:right;color:red"><del>'
                                  || V_RESULTS(FLT.FLIGHT_ID)(P.PILOT_ID).ORIGINAL_SCORE
                                  || '</del></td>');

                    ELSIF ISCANCELLED(V_RESULTS(FLT.FLIGHT_ID)(P.PILOT_ID).COMPETITION_FLIGHT_ID) THEN
           --v_results(flt.flight_id)(p.pilot_id).cancellation_type = 'P' THEN
                        SYS.HTP.P('<td style="text-align:right;color:orange">'
                                  || V_RESULTS(FLT.FLIGHT_ID)(P.PILOT_ID).SCORE
                                  || '</td>');
                    ELSIF ISBEST6(
                                 FLT.FLIGHT_ID,
                                 P.PILOT_ID
                          ) THEN    
           --ELSIF v_results(flt.flight_id)(p.pilot_id).best6rn <=6 THEN
                        SYS.HTP.P('<td style="text-align:right;color:green;font-weight:bold">'
                                  || V_RESULTS(FLT.FLIGHT_ID)(P.PILOT_ID).SCORE
                                  || '</td>');
                    ELSE
                        SYS.HTP.P('<td style="text-align:right;color:black">'
                                  || V_RESULTS(FLT.FLIGHT_ID)(P.PILOT_ID).SCORE
                                  || '</td>');
                    END IF;
           --sys.htp.p('<br> Flt:' || v_results(flt.flight_id)(p.pilot_id).competition_flight_id ||'<BR>');
           --sys.htp.p('<br> Canc:' || v_results(flt.flight_id)(p.pilot_id).cancelled_points_flight_id ||'<BR>');
           --dbms_output.put_line('cfid: ' || v_results(flt.flight_id)(p.pilot_id).competition_flight_id );
           --|| ' cancfid:' || v_results(flt.flight_id)(p.pilot_id).cancelled_points_flight_id);

                EXCEPTION
                    WHEN NO_DATA_FOUND THEN
                        SYS.HTP.P('<td> </td>');
                END;       
           --dbms_output.put_line('cfid: ' || v_results(flt.flight_id)(p.pilot_id).competition_flight_id || ' cancfid:' || v_results(flt.flight_id)(p.pilot_id).cancelled_points_flight_id);

            END LOOP;

            SYS.HTP.P('</tr>');
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
        SYS.HTP.P('</table></body></html>');
    END;
END report;
/
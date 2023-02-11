--
-- Package "MAINTAIN"
--
CREATE OR REPLACE EDITIONABLE PACKAGE "FLIGHTLOG"."MAINTAIN" AS
    PROCEDURE CALCULATE_BEST6 (
        P_COMPETITION_SERIES IN NUMBER
    );

END MAINTAIN;

CREATE OR REPLACE EDITIONABLE PACKAGE BODY "FLIGHTLOG"."MAINTAIN" AS

    PROCEDURE CALCULATE_BEST6 (
        P_COMPETITION_SERIES IN NUMBER
    ) IS

        V_BEST6_ROWID                   ROWID;
        V_COMPETITION_FLIGHTS_ID  NUMBER;

        PROCEDURE INSERT_BEST6 (
            P_COMPETITION_FLIGHTS_ID  IN  NUMBER,
            P_FLIGHT_ID               IN  NUMBER,
            P_PILOT_ID                IN  NUMBER,
            P_SCORE                   IN  NUMBER
        ) IS
            V_B6_FLAG VARCHAR2(5) := 'FALSE';
        BEGIN
            INSERT INTO BEST6_TBL (
                PILOT_ID,
                COMPETITION_FLIGHTS_ID,
                FLIGHT_ID,
                SCORE
            ) VALUES (
                P_PILOT_ID,
                P_COMPETITION_FLIGHTS_ID,
                P_FLIGHT_ID,
                P_SCORE
            );

            DELETE FROM BEST6_TBL
            WHERE
                ROWID IN (
                    SELECT
                        RID
                    FROM
                        (
                            SELECT
                                BEST6_ROWID  RID, ROW_NUMBER()
                                                 OVER(
                                    ORDER BY SCORE DESC
                                                 )            RN
                            FROM
                                BEST6 B6
                            WHERE
                                B6.PILOT_ID = P_PILOT_ID
                                AND B6.COMPETITION_SERIES_ID = P_COMPETITION_SERIES
                        )
                    WHERE
                        RN > 6
                );

        END INSERT_BEST6;

        PROCEDURE UPDATE_CRASH (
            P_PILOT_ID  IN  NUMBER,
            P_CFRID     IN  ROWID
        ) IS
        BEGIN
            BEGIN
                SELECT
                    BEST6_ROWID RID,
                    B6.COMPETITION_FLIGHTS_ID
                INTO
                    V_BEST6_ROWID,
                    V_COMPETITION_FLIGHTS_ID
                FROM
                    BEST6 B6
                WHERE
                    best6_ROWID = (
                        SELECT
                            MAX(RID)
                        FROM
                            (
                                SELECT
                                    RANK()
                                    OVER(
                                        ORDER BY B2.SCORE DESC
                                    )            RNK,
                                    BEST6_ROWID  RID
                                FROM
                                    BEST6 B2
                                WHERE
                                    B2.PILOT_ID = P_PILOT_ID
                                    AND B2.COMPETITION_SERIES_ID = P_COMPETITION_SERIES
                            )
                        WHERE
                            RNK = 1
                    );

                DBMS_OUTPUT.PUT_LINE('Crashed cfid:' || V_COMPETITION_FLIGHTS_ID);
                UPDATE COMPETITION_FLIGHTS_TBL CF
                SET
                    CF.SCORE = CF.ORIGINAL_SCORE * 0.5
                --    ORIGINAL_SCORE = CF.SCORE
                WHERE
                    CF.ID = V_COMPETITION_FLIGHTS_ID;

                UPDATE BEST6_TBL
                SET score = (SELECT score from COMPETITION_FLIGHTS_TBL cf where CF.ID = V_COMPETITION_FLIGHTS_ID)
                WHERE
                   ROWID = V_BEST6_ROWID;       

            EXCEPTION
                WHEN NO_DATA_FOUND THEN
                    NULL;
            END;

           -- dbms_output.put_line('Score:' || f.score);

            UPDATE COMPETITION_FLIGHTS_TBL CF
            SET
                CF.SCORE = 0,
            --    CF.ORIGINAL_SCORE = CF.SCORE,
                CF.CANCELLED_POINTS_FLIGHT_ID = V_COMPETITION_FLIGHTS_ID
            WHERE
                ROWID = P_CFRID;


/*
Under new rule  11/1/23 we don't automatically lose the previous best flight, just 50% of the points

*/
        END UPDATE_CRASH;

    BEGIN
        FOR P IN (
            SELECT
                ID
            FROM
                PILOTS
        ) LOOP
            FOR F IN (
                SELECT
                    CF.ROWID    CFRID,
                    CF.ID       COMPETITION_FLIGHTS_ID,
                    CF.FLIGHT_ID,
                    CF.PILOT_ID,
                    C.FLIGHT_DATE,
                    CF.CRASH    CRASHED,
                    CF.SCORE
                FROM
                    COMPETITION_FLIGHTS_TBL CF
                    JOIN COMPETITIONS C ON ( CF.FLIGHT_ID = C.ID )
                WHERE
                    CF.PILOT_ID = P.ID
                    AND CF.FLIGHT_ID IN (
                        SELECT
                            C.ID COMPETITION_FLIGHT_ID
                        FROM
                            FLIGHTLOG.COMPETITIONS C
                            JOIN FLIGHTLOG.COMPETITION_DATES CD ON ( C.FLIGHT_DATE BETWEEN CD.FIRST_FLIGHT AND CD.LAST_FLIGHT
                                                                     AND CD.ID = P_COMPETITION_SERIES
                                --P0_COMPETITION_SERIES 
                        )
                    )
                ORDER BY
                    C.FLIGHT_DATE 
            ) LOOP
                DBMS_OUTPUT.PUT_LINE('pilot_id:'
                                     || P.ID
                                     || ' flight_date:'
                                     || F.FLIGHT_DATE
                                     || ' crashed:'
                                     || F.CRASHED);

                IF NVL(
                      F.CRASHED,
                      'N'
                   ) = 'Y' THEN
                       NULL;
                    UPDATE_CRASH(
                                F.PILOT_ID,
                                F.CFRID
                    ); 
                ELSE
                    INSERT_BEST6(
                                P_COMPETITION_FLIGHTS_ID  => F.COMPETITION_FLIGHTS_ID,
                                P_FLIGHT_ID               => F.FLIGHT_ID,
                                P_PILOT_ID                => F.PILOT_ID,
                                P_SCORE                   => F.SCORE
                    );
                END IF;

                DBMS_OUTPUT.PUT_LINE('Outer cfid:' || F.COMPETITION_FLIGHTS_ID);
            END LOOP;
        END LOOP;
    END CALCULATE_BEST6;

END MAINTAIN;
/
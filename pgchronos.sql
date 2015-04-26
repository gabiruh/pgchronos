CREATE OR REPLACE FUNCTION contains(
    tsr tstzrange[],
    ts timestampTz
) RETURNS boolean AS
$$
    select coalesce
    (
        (
            SELECT true
            FROM (select unnest(tsr) tr) tr
            where ts <@ tr.tr
            limit 1
        ),
        false
    );
$$ LANGUAGE 'sql' IMMUTABLE STRICT;
COMMENT ON FUNCTION contains(tstzrange[], timestampTz) IS 'True if timestampTz ts contained in any daterange in tsr';

CREATE OR REPLACE FUNCTION contains(
    ts timestamptz,
    tsr tstzrange[]
) RETURNS boolean AS
$$
    select contains(tsr,ts);
$$ LANGUAGE 'sql' IMMUTABLE STRICT;
COMMENT ON FUNCTION contains(tstzrange[], timestampTz) IS 'True if timestampTz ts contained in any daterange in tsr';

CREATE OR REPLACE FUNCTION contains(
    d daterange[],
    dt date
) RETURNS boolean AS
$$
    select coalesce
    (
        (
            SELECT true
            FROM (select unnest(d) d) d
            where dt <@ d.d
            limit 1
        ),
        false
    );
$$ LANGUAGE 'sql' IMMUTABLE STRICT;
COMMENT ON FUNCTION contains(daterange[], date) IS 'True if date dt contained in any daterange in d';

CREATE OR REPLACE FUNCTION contains(
    dt date,
    d daterange[]
) RETURNS boolean AS
$$
    select contains(d,dt);
$$ LANGUAGE 'sql' IMMUTABLE STRICT;
COMMENT ON FUNCTION contains(date, daterange[]) IS 'True if date dt contained in any daterange in d';

CREATE OR REPLACE FUNCTION difference(
   ts1  IN tstzrange[], 
   ts2  IN tstzrange[]
) RETURNS tstzrange[] AS
$$
    SELECT array_agg(prd)
    FROM (
        SELECT tstzrange((d_in).start_date, MIN((d_out).end_date)) AS prd
        FROM (
            SELECT DISTINCT lower(d) AS start_date
            FROM unnest(ts1) d
            WHERE NOT contains(ts2, lower(d))
            AND NOT contains(ts1, lower(d))

            UNION

            SELECT DISTINCT upper(d)
            FROM unnest(ts2) d
            WHERE contains(ts1, upper(d))
            AND NOT contains(ts2, upper(d))
        ) d_in
        JOIN (
            SELECT upper(d) AS end_date
            FROM unnest(ts1) d
            WHERE NOT contains(ts1, upper(d))

            UNION ALL

            SELECT lower(d)
            FROM unnest(ts2) d
            WHERE contains(ts1, lower(d))
              AND NOT contains(ts2, lower(d))
        ) d_out ON d_in.start_date < d_out.end_date
        GROUP BY (d_in).start_date
        ORDER BY (d_in).start_date
    ) sub;
$$ LANGUAGE 'sql' IMMUTABLE STRICT;

CREATE OR REPLACE FUNCTION difference(
   dr1  IN daterange[], 
   dr2  IN daterange[]
) RETURNS daterange[] AS
$$
    SELECT array_agg(prd)
    FROM (
        SELECT daterange((d_in).start_date, MIN((d_out).end_date)) AS prd
        FROM (
            SELECT DISTINCT lower(d) AS start_date
            FROM unnest(dr1) d
            WHERE NOT contains(dr2,lower(d))
            AND NOT contains(dr1, lower(d) - 1)

            UNION

            SELECT DISTINCT upper(d)
            FROM unnest(dr2) d
            WHERE contains(dr1, upper(d))
            AND NOT contains(dr2, upper(d))
        ) d_in
        JOIN (
            SELECT upper(d) AS end_date
            FROM unnest(dr1) d
            WHERE NOT contains(dr1, upper(d))

            UNION ALL

            SELECT lower(d)
            FROM unnest(dr2) d
            WHERE contains(dr1, lower(d))
              AND NOT contains(dr2, lower(d) - 1)
        ) d_out ON d_in.start_date < d_out.end_date
        GROUP BY (d_in).start_date
        ORDER BY (d_in).start_date
    ) sub;
$$ LANGUAGE 'sql' IMMUTABLE STRICT;
COMMENT ON FUNCTION difference(daterange[], daterange[])
IS 'Return daterange[] containing all values in dr1 that are not filtered out by dr2';

CREATE OR REPLACE FUNCTION intersection(
    dr1 IN daterange[], 
    dr2 IN daterange[]
) RETURNS daterange[] AS
$$
    SELECT array_agg(t)
    FROM (
        SELECT daterange(start_date, MIN(end_date)) AS t
        FROM (
            SELECT DISTINCT lower(d) AS start_date
            FROM unnest(dr1) d
            WHERE NOT contains(dr1, lower(d) - 1)
              AND contains(dr2, lower(d))

            UNION

            SELECT DISTINCT lower(d) 
            FROM unnest(dr2) d
            WHERE NOT contains(dr2, lower(d) - 1)
              AND contains(dr1, lower(d))
        ) AS t_in
        JOIN (
            SELECT upper(d) AS end_date
            FROM unnest(dr1) d
            WHERE NOT contains(dr1, upper(d))
              AND contains(dr2, upper(d)-1)

            UNION ALL

            SELECT upper(d)
            FROM unnest(dr2) d
            WHERE NOT contains(dr2, upper(d))
              AND contains(dr1, upper(d)-1)
        ) AS t_out ON t_in.start_date < t_out.end_date
        GROUP BY t_in.start_date
        ORDER BY t_in.start_date
    ) sub;
$$ LANGUAGE 'sql' IMMUTABLE STRICT;
COMMENT ON FUNCTION intersection(daterange[], daterange[]) IS 'Return daterange[] containing all values in both dr1 and dr2';

CREATE OR REPLACE FUNCTION reduce(dr daterange[])
RETURNS daterange[] AS
$$
    SELECT array_agg(t)
    FROM (
        SELECT daterange(start_date, MIN(end_date)) AS t
        FROM (
            SELECT DISTINCT lower(d) AS start_date
            FROM unnest(dr) d
            WHERE NOT contains(dr, lower(d)-1)
        ) AS t_in
        JOIN (
            SELECT upper(d) AS end_date
            FROM unnest(dr) d
            WHERE NOT contains(dr, upper(d))
        ) AS t_out ON t_in.start_date < t_out.end_date
        GROUP BY t_in.start_date
        ORDER BY t_in.start_date
    ) sub;
$$ LANGUAGE 'sql' IMMUTABLE STRICT;
COMMENT ON FUNCTION reduce(daterange[]) IS 'Union overlapping and adjacent periods';

CREATE OR REPLACE FUNCTION range_union(
   dr1  IN daterange[],
   dr2  IN daterange[]
) RETURNS daterange[] AS
$$
   SELECT reduce(dr1 || dr2);
$$ LANGUAGE 'sql' IMMUTABLE;
COMMENT ON FUNCTION range_union(daterange[], daterange[])
IS 'Union overlapping and adjacent periods';

CREATE OPERATOR @>(
  PROCEDURE = contains,
  LEFTARG = tstzrange[],
  RIGHTARG = timestamptz,
  commutator = <@
);

CREATE OPERATOR <@(
  PROCEDURE = contains,
  LEFTARG = timestamptz,
  RIGHTARG = tstzrange[],
  commutator = @>
);

CREATE OPERATOR @>(
  PROCEDURE = contains,
  LEFTARG = daterange[],
  RIGHTARG = date,
  commutator = <@
);

CREATE OPERATOR <@(
  PROCEDURE = contains,
  LEFTARG = date,
  RIGHTARG = daterange[],
  commutator = @>
);

CREATE OPERATOR - (
  PROCEDURE = difference,
  LEFTARG = daterange[],
  RIGHTARG = daterange[]
);

CREATE OPERATOR - (
  PROCEDURE = difference,
  LEFTARG = tstzrange[],
  RIGHTARG = tstzrange[]
);

CREATE OPERATOR * (
  PROCEDURE = intersection,
  LEFTARG = daterange[],
  RIGHTARG = daterange[]
);

CREATE OPERATOR + (
  PROCEDURE = range_union,
  LEFTARG = daterange[],
  RIGHTARG = daterange[]
);

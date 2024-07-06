WITH paid_sessions AS (
    SELECT
        s.visitor_id,
        s.visit_date,
        s.source AS utm_source,
        s.medium AS utm_medium,
        s.campaign AS utm_campaign,
        l.lead_id,
        l.created_at,
        l.amount,
        l.closing_reason,
        l.status_id,
        ROW_NUMBER()
            OVER (PARTITION BY s.visitor_id ORDER BY s.visit_date DESC)
        AS rnk
    FROM
        sessions AS s
    LEFT JOIN
        leads AS l
        ON s.visitor_id = l.visitor_id AND s.visit_date <= l.created_at
    WHERE
        s.medium IN ('cpc', 'cpm', 'cpa', 'youtube', 'cpp', 'tg', 'social')
)
SELECT
        ps.visitor_id,
        ps.visit_date,
        ps.utm_source,
        ps.utm_medium,
        ps.utm_campaign,
        ps.lead_id,
        ps.created_at,
        ps.amount,
        ps.closing_reason,
        ps.status_id
FROM
        paid_sessions AS ps
WHERE
	ps.rnk = 1
ORDER BY
    ps.amount DESC NULLS LAST,
    ps.visit_date ASC,
    ps.utm_source ASC,
    ps.utm_medium ASC,
    ps.utm_campaign ASC;

WITH paid_sessions AS (
    SELECT
        s.visitor_id,
        s.source AS utm_source,
        s.medium AS utm_medium,
        s.campaign AS utm_campaign,
        l.lead_id,
        l.created_at,
        l.amount,
        l.closing_reason,
        l.status_id,
        DATE(s.visit_date) AS visit_date,
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
),

last_paid_click AS (
    SELECT
        visitor_id,
        visit_date,
        utm_source,
        utm_medium,
        utm_campaign,
        lead_id,
        created_at,
        amount,
        closing_reason,
        status_id
    FROM
        paid_sessions
    WHERE
        rnk = 1
),

advertising_costs AS (
    SELECT
        campaign_date AS visit_date,
        utm_source,
        utm_medium,
        utm_campaign,
        SUM(daily_spent) AS total_cost
    FROM
        vk_ads
    GROUP BY
        campaign_date, utm_source, utm_medium, utm_campaign
    UNION ALL
    SELECT
        campaign_date,
        utm_source,
        utm_medium,
        utm_campaign,
        SUM(daily_spent)
    FROM
        ya_ads
    GROUP BY
        campaign_date, utm_source, utm_medium, utm_campaign
),

final_data AS (
    SELECT
        lpc.visit_date,
        lpc.utm_source,
        lpc.utm_medium,
        lpc.utm_campaign,
        COUNT(lpc.visitor_id) AS visitors_count,
        COALESCE(ac.total_cost, 0) AS total_cost,
        COUNT(DISTINCT lpc.lead_id) AS leads_count,
        COUNT(
            DISTINCT CASE
                WHEN
                    lpc.closing_reason = 'Успешная продажа'
                    OR lpc.status_id = 142
                    THEN lpc.lead_id
            END
        ) AS purchases_count,
        SUM(
            CASE
                WHEN
                    lpc.closing_reason = 'Успешная продажа'
                    OR lpc.status_id = 142
                    THEN lpc.amount
                ELSE 0
            END
        ) AS revenue
    FROM
        last_paid_click AS lpc
    LEFT JOIN
        advertising_costs AS ac
        ON
            lpc.visit_date = ac.visit_date
            AND lpc.utm_source = ac.utm_source
            AND lpc.utm_medium = ac.utm_medium
            AND lpc.utm_campaign = ac.utm_campaign
    GROUP BY
        lpc.visit_date,
        lpc.utm_source,
        lpc.utm_medium,
        lpc.utm_campaign,
        ac.total_cost
)

SELECT
    visit_date,
    utm_source,
    utm_medium,
    utm_campaign,
    visitors_count,
    total_cost,
    leads_count,
    purchases_count,
    revenue
FROM
    final_data
ORDER BY
    revenue DESC NULLS LAST,
    visit_date ASC,
    visitors_count DESC,
    utm_source ASC,
    utm_medium ASC,
    utm_campaign ASC;
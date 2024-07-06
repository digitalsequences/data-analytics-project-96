--1) Сколько у нас пользователей заходят на сайт?

SELECT
	date(visit_date),
	EXTRACT(WEEK FROM date(visit_date)) AS week,
	EXTRACT(MONTH FROM date(visit_date)) AS MONTH,
	count(DISTINCT visitor_id) AS visitors_count
FROM sessions s
GROUP BY date(visit_date)
ORDER BY date(visit_date);


--2) Какие каналы их приводят на сайт? Хочется видеть по дням/неделям/месяцам

SELECT
	DISTINCT (s.source) AS utm_source,
	date(visit_date),
	EXTRACT(WEEK FROM date(visit_date)) AS week,
	EXTRACT(MONTH FROM date(visit_date)) AS month
FROM sessions s
ORDER BY date(visit_date);


--3) Сколько лидов к нам приходят?

SELECT
	date(created_at),
	EXTRACT(WEEK FROM date(created_at)) AS week,
	EXTRACT(MONTH FROM date(created_at)) AS month,
	count(DISTINCT lead_id) AS leadsß_count
FROM leads l
WHERE closing_reason = 'Успешная продажа'
GROUP BY date(created_at)
ORDER BY date(created_at);


--4) Какая конверсия из клика в лид? А из лида в оплату?

SELECT
	round((SELECT count(DISTINCT lead_id) FROM leads)::numeric * 100
	/ count(DISTINCT visitor_id), 3) AS conv_in_lead,
	round((SELECT count(DISTINCT lead_id) FROM leads WHERE closing_reason = 'Успешная продажа')::NUMERIC
	* 100 / count(DISTINCT visitor_id), 3) AS conv_in_pay
FROM sessions;


--5) Сколько мы тратим по разным каналам в динамике?

SELECT
	date(campaign_date) AS visit_date,
	utm_source,
	SUM(daily_spent) AS total_cost
FROM
    vk_ads
GROUP BY
	campaign_date, utm_source
UNION ALL
SELECT
	date(campaign_date),
	utm_source,
	SUM(daily_spent)
FROM
	ya_ads
GROUP BY
	date(campaign_date), utm_source
ORDER BY visit_date, total_cost DESC;


--6) Окупаются ли каналы?

WITH source_cost AS (
	SELECT
		utm_source,
		SUM(daily_spent) AS total_cost
	FROM
	    vk_ads
	GROUP BY
		utm_source
	UNION ALL
	SELECT
		utm_source,
		SUM(daily_spent)
	FROM
		ya_ads
	GROUP BY
		utm_source
),
source_revenue AS (
SELECT
	s.SOURCE AS utm_source,
	sum(amount) AS revenue	
FROM sessions AS s
LEFT JOIN leads AS l
USING (visitor_id)
WHERE closing_reason = 'Успешная продажа'
GROUP BY s.SOURCE
)

SELECT 
	DISTINCT utm_source,
	CASE 
		WHEN revenue - total_cost > 0 OR revenue - total_cost IS NULL THEN 'Выручка больше расхода'
		ELSE 'Расход больше выручки'
	END AS payback
FROM source_revenue AS sr
LEFT JOIN source_cost AS sc
USING (utm_source);


--7) Расчет метрик

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

raw_data AS (
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
),
final_data AS (
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
	    raw_data
	ORDER BY
	    revenue DESC NULLS LAST,
	    visit_date ASC,
	    visitors_count DESC,
	    utm_source ASC,
	    utm_medium ASC,
    	utm_campaign ASC
)

SELECT
	utm_source,
	utm_medium,
	utm_campaign,
	round(sum(total_cost) / sum(visitors_count), 2) AS cpu, --total_cost / visitors_count
	CASE 
		WHEN sum(leads_count) = 0 THEN 0
		ELSE round(sum(total_cost) / sum(leads_count), 2)
	END AS cpl, --total_cost / leads_count
	CASE
		WHEN sum(purchases_count) = 0 THEN 0
		ELSE round(sum(total_cost) / sum(purchases_count), 2)
	END AS cppu, --total_cost / purchases_count
	CASE 
		WHEN sum(total_cost) = 0 THEN 0
		ELSE round(sum(revenue) - sum(total_cost) / sum(total_cost) * 100, 2)
	END AS roi --(revenue - total_cost) / total_cost * 100%
FROM final_data
GROUP BY
	utm_source,
	utm_medium,
	utm_campaign;
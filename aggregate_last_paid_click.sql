WITH paid_channels AS (
    SELECT 'cpc' AS medium
    UNION ALL
    SELECT 'cpm'
    UNION ALL
    SELECT 'cpa'
    UNION ALL
    SELECT 'youtube'
    UNION ALL
    SELECT 'cpp'
    UNION ALL
    SELECT 'tg'
    UNION ALL
    SELECT 'social'
),

last_paid_clicks AS (
    SELECT
        s.visitor_id,
        s.source AS utm_source,
        s.medium AS utm_medium,
        s.campaign AS utm_campaign,
        TO_CHAR(s.visit_date, 'YYYY-MM-DD') AS visit_date,
        ROW_NUMBER() OVER (
            PARTITION BY s.visitor_id ORDER BY s.visit_date DESC
        ) AS rn
    FROM sessions AS s
    INNER JOIN paid_channels AS pc ON s.medium = pc.medium
),

last_paid_click_per_visitor AS (
    SELECT
        visitor_id,
        visit_date,
        utm_source,
        utm_medium,
        utm_campaign
    FROM last_paid_clicks
    WHERE rn = 1
),

visits_aggregated AS (
    SELECT
        visit_date,
        utm_source,
        utm_medium,
        utm_campaign,
        COUNT(visitor_id) AS visitors_count
    FROM last_paid_click_per_visitor
    GROUP BY visit_date, utm_source, utm_medium, utm_campaign
),

costs_aggregated AS (
    SELECT
        utm_source,
        utm_medium,
        utm_campaign,
        TO_CHAR(campaign_date, 'YYYY-MM-DD') AS visit_date,
        SUM(daily_spent) AS total_cost
    FROM vk_ads
    GROUP BY
        utm_source,
        utm_medium,
        utm_campaign,
        TO_CHAR(campaign_date, 'YYYY-MM-DD')
    UNION ALL
    SELECT
        utm_source,
        utm_medium,
        utm_campaign,
        TO_CHAR(campaign_date, 'YYYY-MM-DD') AS visit_date,
        SUM(daily_spent) AS total_cost
    FROM ya_ads
    GROUP BY
        utm_source,
        utm_medium,
        utm_campaign,
        TO_CHAR(campaign_date, 'YYYY-MM-DD')
),

leads_aggregated AS (
    SELECT
        lpc.visit_date,
        lpc.utm_source,
        lpc.utm_medium,
        lpc.utm_campaign,
        COUNT(l.lead_id) AS leads_count,
        COUNT(
            CASE
                WHEN
                    l.closing_reason = 'Успешно реализовано'
                    OR l.status_id = 142
                    THEN l.lead_id
            END
        ) AS purchases_count,
        SUM(
            CASE
                WHEN
                    l.closing_reason = 'Успешно реализовано'
                    OR l.status_id = 142
                    THEN l.amount
                ELSE 0
            END
        ) AS revenue
    FROM last_paid_click_per_visitor AS lpc
    LEFT JOIN leads AS l
        ON
            lpc.visitor_id = l.visitor_id
            AND TO_CHAR(l.created_at, 'YYYY-MM-DD') >= lpc.visit_date
    GROUP BY lpc.visit_date, lpc.utm_source, lpc.utm_medium, lpc.utm_campaign
)

SELECT
    v.visitors_count,
    c.total_cost,
    l.leads_count,
    l.purchases_count,
    l.revenue,
    COALESCE(v.visit_date, c.visit_date, l.visit_date) AS visit_date,
    COALESCE(v.utm_source, c.utm_source, l.utm_source) AS utm_source,
    COALESCE(v.utm_medium, c.utm_medium, l.utm_medium) AS utm_medium,
    COALESCE(v.utm_campaign, c.utm_campaign, l.utm_campaign) AS utm_campaign
FROM visits_aggregated AS v
FULL OUTER JOIN
    costs_aggregated AS c
    ON
        v.visit_date = c.visit_date
        AND v.utm_source = c.utm_source
        AND v.utm_medium = c.utm_medium
        AND v.utm_campaign = c.utm_campaign
FULL OUTER JOIN
    leads_aggregated AS l
    ON
        COALESCE(v.visit_date, c.visit_date) = l.visit_date
        AND COALESCE(v.utm_source, c.utm_source) = l.utm_source
        AND COALESCE(v.utm_medium, c.utm_medium) = l.utm_medium
        AND COALESCE(v.utm_campaign, c.utm_campaign) = l.utm_campaign
ORDER BY
    l.revenue DESC NULLS LAST, COALESCE(v.visit_date, c.visit_date, l.visit_date) ASC, v.visitors_count DESC, COALESCE(v.utm_source, c.utm_source, l.utm_source) ASC, COALESCE(v.utm_medium, c.utm_medium, l.utm_medium) ASC, COALESCE(v.utm_campaign, c.utm_campaign, l.utm_campaign) ASC;

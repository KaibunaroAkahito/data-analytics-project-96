WITH
-- Определяем платные каналы
paid_channels AS (
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

-- Агрегируем данные по визитам
visits_data AS (
    SELECT
        source AS utm_source,
        medium AS utm_medium,
        campaign AS utm_campaign,
        DATE(visit_date) AS visit_date,
        COUNT(DISTINCT visitor_id) AS visitors_count
    FROM sessions
    GROUP BY DATE(visit_date), source, medium, campaign
),

-- Агрегируем расходы на рекламу
costs_data AS (
    -- Расходы из VK
    SELECT
        utm_source,
        utm_medium,
        utm_campaign,
        campaign_date AS visit_date,
        SUM(daily_spent) AS total_cost
    FROM vk_ads
    GROUP BY utm_source, utm_medium, utm_campaign, campaign_date

    UNION ALL

    -- Расходы из Yandex
    SELECT
        utm_source,
        utm_medium,
        utm_campaign,
        campaign_date AS visit_date,
        SUM(daily_spent) AS total_cost
    FROM ya_ads
    GROUP BY utm_source, utm_medium, utm_campaign, campaign_date
),

-- Агрегируем данные по лидам
leads_data AS (
    SELECT
        s.source AS utm_source,
        s.medium AS utm_medium,
        s.campaign AS utm_campaign,
        DATE(s.visit_date) AS visit_date,
        COUNT(DISTINCT l.lead_id) AS leads_count,
        COUNT(
            DISTINCT CASE
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
    FROM sessions AS s
    LEFT JOIN
        leads AS l
        ON s.visitor_id = l.visitor_id AND s.visit_date <= l.created_at
    GROUP BY DATE(s.visit_date), s.source, s.medium, s.campaign
)

-- Финальный набор данных для дашборда
SELECT
    v.visitors_count,
    c.total_cost,
    l.leads_count,
    l.purchases_count,
    l.revenue,
    COALESCE(v.visit_date, c.visit_date, l.visit_date) AS date,
    COALESCE(v.utm_source, c.utm_source, l.utm_source) AS utm_source,
    COALESCE(v.utm_medium, c.utm_medium, l.utm_medium) AS utm_medium,
    COALESCE(v.utm_campaign, c.utm_campaign, l.utm_campaign) AS utm_campaign,
    -- Рассчитываем метрики
    CASE
        WHEN v.visitors_count > 0 THEN c.total_cost / v.visitors_count
    END AS cpu,
    CASE
        WHEN l.leads_count > 0 THEN c.total_cost / l.leads_count
    END AS cpl,
    CASE
        WHEN l.purchases_count > 0 THEN c.total_cost / l.purchases_count
    END AS cppu,
    CASE
        WHEN
            c.total_cost > 0
            THEN (l.revenue - c.total_cost) / c.total_cost * 100
    END AS roi
FROM visits_data AS v
FULL OUTER JOIN costs_data AS c
    ON
        v.visit_date = c.visit_date
        AND v.utm_source = c.utm_source
        AND v.utm_medium = c.utm_medium
        AND v.utm_campaign = c.utm_campaign
FULL OUTER JOIN leads_data AS l ON
    COALESCE(v.visit_date, c.visit_date) = l.visit_date
    AND COALESCE(v.utm_source, c.utm_source) = l.utm_source
    AND COALESCE(v.utm_medium, c.utm_medium) = l.utm_medium
    AND COALESCE(v.utm_campaign, c.utm_campaign) = l.utm_campaign

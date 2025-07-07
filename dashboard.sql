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

-- Находим последний платный клик для каждого посетителя
last_paid_clicks AS (
    SELECT
        s.visitor_id,
        -- Форматируем с временем
        s.landing_page,
        s.source AS utm_source,
        s.medium AS utm_medium,
        s.campaign AS utm_campaign,
        s.content AS utm_content,
        TO_CHAR(s.visit_date, 'YYYY-MM-DD HH24:MI:SS.MS') AS visit_date,
        ROW_NUMBER() OVER (
            PARTITION BY s.visitor_id
            ORDER BY s.visit_date DESC
        ) AS rn
    FROM sessions AS s
    INNER JOIN paid_channels AS pc ON s.medium = pc.medium
),

-- Получаем только последние платные клики
last_paid_click_per_visitor AS (
    SELECT * FROM last_paid_clicks
    WHERE rn = 1
),

-- Агрегируем расходы на рекламу по utm-меткам
marketing_costs AS (
    -- Расходы из VK
    SELECT
        utm_source,
        utm_medium,
        utm_campaign,
        utm_content,
        -- Форматируем с временем
        TO_CHAR(campaign_date, 'YYYY-MM-DD HH24:MI:SS.MS') AS campaign_date,
        SUM(daily_spent) AS cost
    FROM vk_ads
    GROUP BY
        utm_source,
        utm_medium,
        utm_campaign,
        utm_content,
        TO_CHAR(campaign_date, 'YYYY-MM-DD HH24:MI:SS.MS')

    UNION ALL

    -- Расходы из Yandex
    SELECT
        utm_source,
        utm_medium,
        utm_campaign,
        utm_content,
        -- Форматируем с временем
        TO_CHAR(campaign_date, 'YYYY-MM-DD HH24:MI:SS.MS') AS campaign_date,
        SUM(daily_spent) AS cost
    FROM ya_ads
    GROUP BY
        utm_source,
        utm_medium,
        utm_campaign,
        utm_content,
        TO_CHAR(campaign_date, 'YYYY-MM-DD HH24:MI:SS.MS')
)

-- Финальная витрина с атрибуцией и расчетом ROI
SELECT
    lpc.visitor_id,
    lpc.visit_date,  -- Уже в нужном формате
    lpc.utm_source,
    lpc.utm_medium,
    lpc.utm_campaign,
    l.lead_id,
    -- Форматируем с временем
    l.amount,
    l.closing_reason,
    l.status_id,
    TO_CHAR(l.created_at, 'YYYY-MM-DD HH24:MI:SS.MS') AS created_at
FROM last_paid_click_per_visitor AS lpc
LEFT JOIN leads AS l
    ON lpc.visitor_id = l.visitor_id
    -- Сравниваем в одинаковом формате
    AND TO_CHAR(l.created_at, 'YYYY-MM-DD HH24:MI:SS.MS') >= lpc.visit_date
LEFT JOIN marketing_costs AS mc
    ON
        lpc.utm_source = mc.utm_source
        AND lpc.utm_medium = mc.utm_medium
        AND lpc.utm_campaign = mc.utm_campaign
        AND lpc.utm_content = mc.utm_content
        AND lpc.visit_date = mc.campaign_date  -- Оба поля в одинаковом формате
ORDER BY
    l.amount DESC NULLS LAST,
    lpc.visit_date ASC,
    lpc.utm_source ASC,
    lpc.utm_medium ASC,
    lpc.utm_campaign ASC;

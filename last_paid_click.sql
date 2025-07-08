WITH
-- Находим последний платный клик для каждого посетителя (с прямым условием для medium)
last_paid_clicks AS (
    SELECT
        s.visitor_id,
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
    WHERE s.medium IN ('cpc', 'cpm', 'cpa', 'youtube', 'cpp', 'tg', 'social')
),

-- Получаем только последние платные клики
last_paid_click_per_visitor AS (
    SELECT * FROM last_paid_clicks
    WHERE rn = 1
)

-- Финальная витрина с атрибуцией (без маркетинговых затрат)
SELECT
    lpc.visitor_id,
    lpc.visit_date,
    lpc.utm_source,
    lpc.utm_medium,
    lpc.utm_campaign,
    l.lead_id,
    l.amount,
    l.closing_reason,
    l.status_id,
    TO_CHAR(l.created_at, 'YYYY-MM-DD HH24:MI:SS.MS') AS created_at
FROM last_paid_click_per_visitor AS lpc
LEFT JOIN leads AS l
    ON
        lpc.visitor_id = l.visitor_id
        AND TO_CHAR(l.created_at, 'YYYY-MM-DD HH24:MI:SS.MS') >= lpc.visit_date
ORDER BY
    l.amount DESC NULLS LAST,
    lpc.visit_date ASC,
    lpc.utm_source ASC,
    lpc.utm_medium ASC,
    lpc.utm_campaign ASC;

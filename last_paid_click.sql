WITH
-- Определяем платные каналы
paid_channels AS (
  SELECT 'cpc' AS medium UNION ALL
  SELECT 'cpm' UNION ALL
  SELECT 'cpa' UNION ALL
  SELECT 'youtube' UNION ALL
  SELECT 'cpp' UNION ALL
  SELECT 'tg' UNION ALL
  SELECT 'social'
),

-- Находим последний платный клик для каждого посетителя
last_paid_clicks AS (
  SELECT
    s.visitor_id,
    s.visit_date,
    s.landing_page,
    s.source AS utm_source,
    s.medium AS utm_medium,
    s.campaign AS utm_campaign,
    s.content AS utm_content,
    ROW_NUMBER() OVER (
      PARTITION BY s.visitor_id
      ORDER BY s.visit_date DESC
    ) AS rn
  FROM sessions s
  JOIN paid_channels pc ON s.medium = pc.medium
),

-- Получаем только последние платные клики
last_paid_click_per_visitor AS (
  SELECT * FROM last_paid_clicks WHERE rn = 1
),

-- Агрегируем расходы на рекламу по utm-меткам
marketing_costs AS (
  -- Расходы из VK
  SELECT
    utm_source,
    utm_medium,
    utm_campaign,
    utm_content,
    campaign_date,
    SUM(daily_spent) AS cost
  FROM vk_ads
  GROUP BY utm_source, utm_medium, utm_campaign, utm_content, campaign_date

  UNION ALL

  -- Расходы из Yandex
  SELECT
    utm_source,
    utm_medium,
    utm_campaign,
    utm_content,
    campaign_date,
    SUM(daily_spent) AS cost
  FROM ya_ads
  GROUP BY utm_source, utm_medium, utm_campaign, utm_content, campaign_date
)

-- Финальная витрина с атрибуцией и расчетом ROI
SELECT
  lpc.visitor_id,
  lpc.visit_date,
  lpc.landing_page,
  lpc.utm_source,
  lpc.utm_medium,
  lpc.utm_campaign,
  lpc.utm_content,
  l.lead_id,
  l.created_at,
  l.amount,
  l.closing_reason,
  l.learning_format,
  l.status_id,
  mc.cost AS marketing_cost,
  CASE
    WHEN mc.cost > 0 AND l.amount > 0 THEN (l.amount - mc.cost) / mc.cost * 100
    ELSE NULL
  END AS roi_percent
FROM last_paid_click_per_visitor lpc
LEFT JOIN leads l ON lpc.visitor_id = l.visitor_id
  AND l.created_at >= lpc.visit_date
LEFT JOIN marketing_costs mc ON
  lpc.utm_source = mc.utm_source AND
  lpc.utm_medium = mc.utm_medium AND
  lpc.utm_campaign = mc.utm_campaign AND
  lpc.utm_content = mc.utm_content AND
  DATE(lpc.visit_date) = mc.campaign_date
ORDER BY
  l.amount DESC NULLS LAST,
  lpc.visit_date ASC,
  lpc.utm_source ASC,
  lpc.utm_medium ASC,
  lpc.utm_campaign ASC;
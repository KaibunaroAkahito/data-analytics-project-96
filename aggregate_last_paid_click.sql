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
    DATE(s.visit_date) AS visit_date,
    s.source AS utm_source,
    s.medium AS utm_medium,
    s.campaign AS utm_campaign,
    ROW_NUMBER() OVER (
      PARTITION BY s.visitor_id
      ORDER BY s.visit_date DESC
    ) AS rn
  FROM sessions s
  JOIN paid_channels pc ON s.medium = pc.medium
),

-- Получаем только последние платные клики
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

-- Агрегируем данные по визитам
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

-- Агрегируем расходы на рекламу
costs_aggregated AS (
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
leads_aggregated AS (
  SELECT
    DATE(lpc.visit_date) AS visit_date,
    lpc.utm_source,
    lpc.utm_medium,
    lpc.utm_campaign,
    COUNT(l.lead_id) AS leads_count,
    COUNT(CASE WHEN l.closing_reason = 'Успешно реализовано' OR l.status_id = 142 THEN l.lead_id END) AS purchases_count,
    SUM(CASE WHEN l.closing_reason = 'Успешно реализовано' OR l.status_id = 142 THEN l.amount ELSE 0 END) AS revenue
  FROM last_paid_click_per_visitor lpc
  LEFT JOIN leads l ON lpc.visitor_id = l.visitor_id
    AND l.created_at >= lpc.visit_date
  GROUP BY DATE(lpc.visit_date), lpc.utm_source, lpc.utm_medium, lpc.utm_campaign
)

-- Финальная витрина
SELECT
  COALESCE(v.visit_date, c.visit_date, l.visit_date) AS visit_date,
  COALESCE(v.utm_source, c.utm_source, l.utm_source) AS utm_source,
  COALESCE(v.utm_medium, c.utm_medium, l.utm_medium) AS utm_medium,
  COALESCE(v.utm_campaign, c.utm_campaign, l.utm_campaign) AS utm_campaign,
  v.visitors_count,
  c.total_cost,
  l.leads_count,
  l.purchases_count,
  l.revenue
FROM visits_aggregated v
FULL OUTER JOIN costs_aggregated c ON
  v.visit_date = c.visit_date AND
  v.utm_source = c.utm_source AND
  v.utm_medium = c.utm_medium AND
  v.utm_campaign = c.utm_campaign
FULL OUTER JOIN leads_aggregated l ON
  COALESCE(v.visit_date, c.visit_date) = l.visit_date AND
  COALESCE(v.utm_source, c.utm_source) = l.utm_source AND
  COALESCE(v.utm_medium, c.utm_medium) = l.utm_medium AND
  COALESCE(v.utm_campaign, c.utm_campaign) = l.utm_campaign
ORDER BY
  l.revenue DESC NULLS LAST,
  COALESCE(v.visit_date, c.visit_date, l.visit_date) ASC,
  v.visitors_count DESC,
  COALESCE(v.utm_source, c.utm_source, l.utm_source) ASC,
  COALESCE(v.utm_medium, c.utm_medium, l.utm_medium) ASC,
  COALESCE(v.utm_campaign, c.utm_campaign, l.utm_campaign) ASC;
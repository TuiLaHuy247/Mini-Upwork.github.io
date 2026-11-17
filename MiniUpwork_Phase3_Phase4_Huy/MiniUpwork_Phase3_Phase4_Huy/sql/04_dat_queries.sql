-- Q1. Tìm job OPEN theo danh mục, kỹ năng và khoảng giá phù hợp.
-- Chỉnh dòng VALUES. Loại job để NULL nếu muốn lấy cả hai loại.
WITH filters(category_name, skill_name, job_type, budget_min, budget_max, hourly_min, hourly_max) AS (
    VALUES ('Web Development'::TEXT, 'PostgreSQL'::TEXT, NULL::TEXT, 400, 2200, 25, 55)
)
SELECT j.job_id, j.title, c.category_name, cl.company_name, j.job_type,
       s.skill_name, js.required_level, fp.budget_amount, hj.rate_min, hj.rate_max
FROM miniupwork.job AS j
JOIN miniupwork.category AS c ON c.category_id = j.category_id
JOIN miniupwork.client AS cl ON cl.user_id = j.client_id
JOIN miniupwork.job_skill AS js ON js.job_id = j.job_id
JOIN miniupwork.skill AS s ON s.skill_id = js.skill_id
LEFT JOIN miniupwork.fixed_price_job AS fp ON fp.job_id = j.job_id
LEFT JOIN miniupwork.hourly_job AS hj ON hj.job_id = j.job_id
CROSS JOIN filters AS f
WHERE j.status = 'OPEN'
  AND lower(c.category_name) = lower(f.category_name)
  AND lower(s.skill_name) = lower(f.skill_name)
  AND (f.job_type IS NULL OR j.job_type = f.job_type)
  AND (
      (j.job_type = 'FIXED_PRICE' AND fp.budget_amount BETWEEN f.budget_min AND f.budget_max)
      OR (j.job_type = 'HOURLY' AND hj.rate_min <= f.hourly_max AND hj.rate_max >= f.hourly_min)
  )
ORDER BY j.posted_at DESC, j.job_id;

-- Q2. Tìm freelancer đang sẵn sàng, đủ mọi kỹ năng ở mức job yêu cầu.
-- Chỉnh mã job ở WHERE. Job mẫu 6 yêu cầu Technical Writing và Testing.
SELECT j.job_id, j.title, f.user_id AS freelancer_id, u.full_name, f.default_hourly_rate,
       EXISTS (
           SELECT 1 FROM miniupwork.proposal AS p
           WHERE p.job_id = j.job_id AND p.freelancer_id = f.user_id
       ) AS has_proposal_record
FROM miniupwork.job AS j
JOIN miniupwork.freelancer AS f ON f.user_id <> j.client_id
JOIN miniupwork.app_user AS u ON u.user_id = f.user_id
WHERE j.job_id = 6
  AND j.status = 'OPEN'
  AND u.status = 'ACTIVE'
  AND f.availability = 'AVAILABLE'
  AND NOT EXISTS (
      SELECT 1 FROM miniupwork.job_skill AS required
      WHERE required.job_id = j.job_id
        AND NOT EXISTS (
            SELECT 1 FROM miniupwork.freelancer_skill AS actual
            WHERE actual.freelancer_id = f.user_id
              AND actual.skill_id = required.skill_id
              AND actual.proficiency_level >= required.required_level
        )
  )
ORDER BY f.default_hourly_rate, f.user_id;

-- Q3. Đếm proposal theo job và xếp hạng mức độ quan tâm trong từng danh mục.
-- LEFT JOIN giữ lại job chưa có proposal. Xếp hạng theo số proposal chưa rút.
WITH job_counts AS (
    SELECT j.job_id, j.title, j.status AS job_status, c.category_id, c.category_name,
           COUNT(p.proposal_id) AS total_proposals,
           COUNT(*) FILTER (WHERE p.status <> 'WITHDRAWN') AS non_withdrawn_proposals,
           COUNT(*) FILTER (WHERE p.status IN ('SUBMITTED', 'SHORTLISTED')) AS pending_proposals,
           COUNT(*) FILTER (WHERE p.status = 'ACCEPTED') AS accepted_proposals
    FROM miniupwork.job AS j
    JOIN miniupwork.category AS c ON c.category_id = j.category_id
    LEFT JOIN miniupwork.proposal AS p ON p.job_id = j.job_id
    GROUP BY j.job_id, c.category_id
)
SELECT job_id, title, job_status, category_name, total_proposals,
       non_withdrawn_proposals, pending_proposals, accepted_proposals,
       DENSE_RANK() OVER (PARTITION BY category_id ORDER BY non_withdrawn_proposals DESC) AS category_rank
FROM job_counts
ORDER BY category_name, category_rank, job_id;

-- Q4. Tính tỷ lệ chấp nhận trên proposal đã có quyết định theo danh mục trực tiếp.
-- Mẫu số gồm ACCEPTED và REJECTED. NULL biểu thị chưa có quyết định.
WITH category_counts AS (
    SELECT c.category_id, c.category_name,
           COUNT(p.proposal_id) AS total_proposals,
           COUNT(*) FILTER (WHERE p.status = 'ACCEPTED') AS accepted_proposals,
           COUNT(*) FILTER (WHERE p.status = 'REJECTED') AS rejected_proposals
    FROM miniupwork.category AS c
    LEFT JOIN miniupwork.job AS j ON j.category_id = c.category_id
    LEFT JOIN miniupwork.proposal AS p ON p.job_id = j.job_id
    GROUP BY c.category_id
)
SELECT category_name, total_proposals, accepted_proposals, rejected_proposals,
       accepted_proposals + rejected_proposals AS decided_proposals,
       ROUND(100.0 * accepted_proposals / NULLIF(accepted_proposals + rejected_proposals, 0), 2)
           AS acceptance_rate_pct
FROM category_counts
ORDER BY acceptance_rate_pct DESC NULLS LAST, category_name, category_id;

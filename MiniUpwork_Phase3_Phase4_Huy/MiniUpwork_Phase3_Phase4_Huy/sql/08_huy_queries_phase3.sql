-- Mini-Upwork Phase 3 · Phần Huy
-- 4 Câu truy vấn SQL nghiệp vụ giải quyết bài toán quản trị Hợp đồng & Dòng tiền.
-- Chạy sau 06_contracts_schema_phase3.sql và 07_contracts_seed_phase3.sql.

SET search_path TO miniupwork, public;

-- =============================================================================
-- TRUY VẤN 1: MILESTONE QUÁ HẠN (Overdue Milestones)
-- Yêu cầu: Lấy từ bảng milestones nối với contracts, lọc các dòng có ngày hạn chót
-- nhỏ hơn ngày hiện tại và trạng thái khác 'APPROVED', kèm hàm tính số ngày trễ hạn
-- (CURRENT_DATE - due_date).
-- Kết quả kỳ vọng trên Seed Data:
--   Milestone 3 ("Milestone 3: Kiểm thử Bảo mật, Tối ưu SEO & Bàn giao Production")
--   thuộc Hợp đồng 1 ("Thiết kế Website Bán Hàng"), due_date = 2026-10-15,
--   status = 'IN_PROGRESS', số tiền = 1.000$.
-- =============================================================================
SELECT
    m.id AS milestone_id,
    c.id AS contract_id,
    c.title AS contract_title,
    c.client_name,
    c.freelancer_name,
    m.title AS milestone_title,
    m.amount,
    m.due_date,
    m.status AS milestone_status,
    (CURRENT_DATE - m.due_date) AS days_overdue
FROM miniupwork.milestones AS m
JOIN miniupwork.contracts AS c ON c.id = m.contract_id
WHERE m.due_date < CURRENT_DATE
  AND m.status <> 'APPROVED'
ORDER BY days_overdue DESC, m.id;


-- =============================================================================
-- TRUY VẤN 2: GIỜ CHƯA LẬP HÓA ĐƠN (Unbilled Approved Time Entries)
-- Yêu cầu: Lấy từ bảng time_entries nối với contracts với điều kiện
-- invoice_id IS NULL và status = 'APPROVED'. Nhân hours * hourly_rate để ra
-- số tiền tạm tính chưa thu.
-- Kết quả kỳ vọng trên Seed Data:
--   2 dòng time_entries (#4: 3.5 giờ = 87.50$ và #5: 2.5 giờ = 62.50$)
--   thuộc Hợp đồng 2 ("Bảo trì & Tối ưu Backend"), tổng cộng 6.0 giờ = 150.00$.
-- =============================================================================
SELECT
    t.id AS time_entry_id,
    c.id AS contract_id,
    c.title AS contract_title,
    c.freelancer_name,
    t.work_date,
    t.description,
    t.hours,
    c.hourly_rate,
    ROUND(t.hours * c.hourly_rate, 2) AS unbilled_amount,
    t.status AS time_entry_status
FROM miniupwork.time_entries AS t
JOIN miniupwork.contracts AS c ON c.id = t.contract_id
WHERE t.invoice_id IS NULL
  AND t.status = 'APPROVED'
ORDER BY t.work_date, t.id;


-- =============================================================================
-- TRUY VẤN 3: ĐỐI SOÁT THANH TOÁN (Payment Reconciliation)
-- Yêu cầu: Dùng LEFT JOIN từ bảng invoices sang payments (chỉ tính giao dịch
-- status = 'SUCCESS'), dùng GROUP BY theo từng hóa đơn để so sánh total_amount
-- với COALESCE(SUM(paid_amount), 0). Lọc ra các dòng có hiệu số khác 0
-- (trả thiếu hoặc trả thừa).
-- Kết quả kỳ vọng trên Seed Data:
--   Hóa đơn INV-2026-003 (id = 3): total_amount = 500.00$, total_paid = 350.00$,
--   discrepancy_amount = 150.00$ (Đang trả thiếu 150.00$).
-- =============================================================================
SELECT
    i.id AS invoice_id,
    i.invoice_number,
    i.contract_id,
    c.title AS contract_title,
    i.status AS invoice_status,
    i.total_amount,
    COALESCE(SUM(p.paid_amount), 0.00) AS total_paid_amount,
    (i.total_amount - COALESCE(SUM(p.paid_amount), 0.00)) AS discrepancy_amount,
    CASE
        WHEN (i.total_amount - COALESCE(SUM(p.paid_amount), 0.00)) > 0 THEN 'TRẢ THIẾU (UNDERPAID)'
        ELSE 'TRẢ THỪA (OVERPAID)'
    END AS reconciliation_note
FROM miniupwork.invoices AS i
JOIN miniupwork.contracts AS c ON c.id = i.contract_id
LEFT JOIN miniupwork.payments AS p
    ON p.invoice_id = i.id
   AND p.status = 'SUCCESS'
GROUP BY
    i.id,
    i.invoice_number,
    i.contract_id,
    c.title,
    i.status,
    i.total_amount
HAVING (i.total_amount - COALESCE(SUM(p.paid_amount), 0.00)) <> 0
ORDER BY ABS(i.total_amount - COALESCE(SUM(p.paid_amount), 0.00)) DESC, i.id;


-- =============================================================================
-- TRUY VẤN 4: DOANH THU THEO KỲ (Monthly Revenue Aggregation)
-- Yêu cầu: Truy vấn bảng payments với điều kiện status = 'SUCCESS', dùng hàm
-- trích xuất tháng/năm từ cột paid_at (DATE_TRUNC trong PostgreSQL hoặc
-- DATE_FORMAT trong MySQL) và dùng SUM(paid_amount) kết hợp GROUP BY theo kỳ.
-- Kết quả kỳ vọng trên Seed Data:
--   - Kỳ 2026-10: 2 giao dịch thành công, tổng doanh thu = 1.250,00$ (1.000$ + 250$)
--   - Kỳ 2026-11: 1 giao dịch thành công, tổng doanh thu = 350,00$
-- =============================================================================
SELECT
    DATE_TRUNC('month', p.paid_at) AS period_start,
    TO_CHAR(DATE_TRUNC('month', p.paid_at), 'YYYY-MM') AS revenue_month,
    COUNT(p.id) AS successful_payment_count,
    SUM(p.paid_amount) AS total_revenue
FROM miniupwork.payments AS p
WHERE p.status = 'SUCCESS'
GROUP BY DATE_TRUNC('month', p.paid_at)
ORDER BY period_start;

/*
-- Ghi chú cú pháp tương đương trên MySQL:
SELECT
    DATE_FORMAT(p.paid_at, '%Y-%m') AS revenue_month,
    COUNT(p.id) AS successful_payment_count,
    SUM(p.paid_amount) AS total_revenue
FROM payments AS p
WHERE p.status = 'SUCCESS'
GROUP BY DATE_FORMAT(p.paid_at, '%Y-%m')
ORDER BY revenue_month;
*/

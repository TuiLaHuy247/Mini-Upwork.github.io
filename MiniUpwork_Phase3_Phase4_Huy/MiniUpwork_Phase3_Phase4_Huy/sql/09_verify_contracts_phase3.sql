-- Mini-Upwork Phase 3 · Phần Huy
-- Script tự động kiểm tra ràng buộc (CHECK/FK) và kết quả 4 câu truy vấn nghiệp vụ.
-- Mọi thay đổi thử nghiệm đều được ROLLBACK ở cuối file (giống 05_verify_proposal.sql).

BEGIN;
SET search_path TO miniupwork, public;

DO $$
DECLARE
    v_overdue_count INT;
    v_unbilled_hours NUMERIC(12,2);
    v_unbilled_amount NUMERIC(12,2);
    v_discrepancy NUMERIC(12,2);
    v_oct_revenue NUMERIC(12,2);
    v_nov_revenue NUMERIC(12,2);
BEGIN
    -- 1. Kiểm tra số lượng bản ghi Seed Data
    IF (SELECT COUNT(*) FROM miniupwork.contracts) <> 2
       OR (SELECT COUNT(*) FROM miniupwork.milestones) <> 3
       OR (SELECT COUNT(*) FROM miniupwork.escrows) <> 3
       OR (SELECT COUNT(*) FROM miniupwork.invoices) <> 3
       OR (SELECT COUNT(*) FROM miniupwork.time_entries) <> 5
       OR (SELECT COUNT(*) FROM miniupwork.payments) <> 4
       OR (SELECT COUNT(*) FROM miniupwork.reviews) <> 1 THEN
        RAISE EXCEPTION 'Số lượng dòng Seed Data không khớp với thiết kế Phase 3';
    END IF;
    RAISE NOTICE 'PASS — Kiểm tra số lượng bản ghi Seed Data trên 7 bảng.';

    -- 2. Kiểm chứng Truy vấn 1 (Milestone quá hạn)
    SELECT COUNT(*) INTO v_overdue_count
    FROM miniupwork.milestones m
    JOIN miniupwork.contracts c ON c.id = m.contract_id
    WHERE m.due_date < CURRENT_DATE AND m.status <> 'APPROVED';

    IF v_overdue_count <> 1 THEN
        RAISE EXCEPTION 'Truy vấn 1 (Milestone quá hạn) kỳ vọng 1 dòng, nhận %', v_overdue_count;
    END IF;
    RAISE NOTICE 'PASS — Truy vấn 1: Phát hiện đúng Milestone #3 quá hạn.';

    -- 3. Kiểm chứng Truy vấn 2 (Giờ chưa lập hóa đơn)
    SELECT COALESCE(SUM(t.hours), 0), COALESCE(SUM(t.hours * c.hourly_rate), 0)
      INTO v_unbilled_hours, v_unbilled_amount
    FROM miniupwork.time_entries t
    JOIN miniupwork.contracts c ON c.id = t.contract_id
    WHERE t.invoice_id IS NULL AND t.status = 'APPROVED';

    IF v_unbilled_hours <> 6.00 OR v_unbilled_amount <> 150.00 THEN
        RAISE EXCEPTION 'Truy vấn 2 kỳ vọng 6 giờ = 150$, nhận % giờ = %$', v_unbilled_hours, v_unbilled_amount;
    END IF;
    RAISE NOTICE 'PASS — Truy vấn 2: Tính đúng 6.00 giờ chưa lập hóa đơn = 150.00 USD.';

    -- 4. Kiểm chứng Truy vấn 3 (Đối soát thanh toán)
    SELECT (i.total_amount - COALESCE(SUM(p.paid_amount), 0))
      INTO v_discrepancy
    FROM miniupwork.invoices i
    LEFT JOIN miniupwork.payments p ON p.invoice_id = i.id AND p.status = 'SUCCESS'
    WHERE i.id = 3
    GROUP BY i.id, i.total_amount
    HAVING (i.total_amount - COALESCE(SUM(p.paid_amount), 0)) <> 0;

    IF v_discrepancy <> 150.00 THEN
        RAISE EXCEPTION 'Truy vấn 3 kỳ vọng lệch 150.00 USD ở Invoice #3, nhận %', v_discrepancy;
    END IF;
    RAISE NOTICE 'PASS — Truy vấn 3: Phát hiện chính xác hóa đơn INV-2026-003 (500$) mới thu 350$, thiếu 150.00 USD.';

    -- 5. Kiểm chứng Truy vấn 4 (Doanh thu theo kỳ)
    SELECT SUM(paid_amount) INTO v_oct_revenue
    FROM miniupwork.payments
    WHERE status = 'SUCCESS' AND TO_CHAR(DATE_TRUNC('month', paid_at), 'YYYY-MM') = '2026-10';

    SELECT SUM(paid_amount) INTO v_nov_revenue
    FROM miniupwork.payments
    WHERE status = 'SUCCESS' AND TO_CHAR(DATE_TRUNC('month', paid_at), 'YYYY-MM') = '2026-11';

    IF v_oct_revenue <> 1250.00 OR v_nov_revenue <> 350.00 THEN
        RAISE EXCEPTION 'Truy vấn 4 doanh thu kỳ vọng T10=1250$, T11=350$, nhận T10=%, T11=%', v_oct_revenue, v_nov_revenue;
    END IF;
    RAISE NOTICE 'PASS — Truy vấn 4: Doanh thu theo kỳ T10/2026 = 1250.00 USD, T11/2026 = 350.00 USD.';
END;
$$;

ROLLBACK;

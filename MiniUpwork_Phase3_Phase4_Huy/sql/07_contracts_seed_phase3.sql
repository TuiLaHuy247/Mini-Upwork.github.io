-- Mini-Upwork Phase 3 · Phần Huy
-- Nạp dữ liệu mẫu có chủ đích (Seed Data) phủ đầy đủ các trường hợp biên cho 4 câu truy vấn và UI Demo.
-- Chạy sau 06_contracts_schema_phase3.sql.

BEGIN;

SET search_path TO miniupwork, public;

TRUNCATE TABLE
    miniupwork.reviews,
    miniupwork.payments,
    miniupwork.time_entries,
    miniupwork.invoices,
    miniupwork.escrows,
    miniupwork.milestones,
    miniupwork.contracts
RESTART IDENTITY CASCADE;

-- =============================================================================
-- 1. NẠP 2 HỢP ĐỒNG MẪU (contracts)
-- - Hợp đồng 1 (FIXED): Thiết kế Website Bán Hàng - 3.000$
-- - Hợp đồng 2 (HOURLY): Bảo trì & Tối ưu Backend - 25$/giờ
-- =============================================================================
INSERT INTO miniupwork.contracts (
    id, title, client_name, freelancer_name, contract_type,
    total_budget, hourly_rate, status, created_at
) VALUES
(
    1,
    'Thiết kế Website Bán Hàng',
    'Demo Studio 1 · Công ty TNHH Thương mại Điện tử Việt',
    'Trần Quang Huy · #5',
    'FIXED',
    3000.00,
    NULL,
    'ACTIVE',
    TIMESTAMPTZ '2026-09-20 09:00:00+07'
),
(
    2,
    'Bảo trì & Tối ưu Backend',
    'Demo Studio 2 · Fintech Core Solutions',
    'Trần Quang Huy · #5',
    'HOURLY',
    NULL,
    25.00,
    'ACTIVE',
    TIMESTAMPTZ '2026-10-01 08:30:00+07'
);

-- =============================================================================
-- 2. NẠP 3 MILESTONES CHO HỢP ĐỒNG 1 (milestones)
-- - Milestone 1 (1.000$): APPROVED (Đã hoàn tất, giải ngân và đánh giá 5 sao)
-- - Milestone 2 (1.000$): SUBMITTED (Chờ nghiệm thu & giải ngân trên UI)
-- - Milestone 3 (1.000$): IN_PROGRESS, due_date ở tháng trước (2026-10-15) -> Quá hạn (phục vụ Truy vấn 1)
-- =============================================================================
INSERT INTO miniupwork.milestones (
    id, contract_id, title, amount, due_date, status
) VALUES
(
    1,
    1,
    'Milestone 1: Thiết kế UI/UX & Khởi tạo Cơ sở dữ liệu',
    1000.00,
    DATE '2026-10-05',
    'APPROVED'
),
(
    2,
    1,
    'Milestone 2: Xây dựng Giỏ hàng & Tích hợp Cổng thanh toán',
    1000.00,
    DATE '2026-11-25',
    'SUBMITTED'
),
(
    3,
    1,
    'Milestone 3: Kiểm thử Bảo mật, Tối ưu SEO & Bàn giao Production',
    1000.00,
    DATE '2026-10-15',
    'IN_PROGRESS'
);

-- =============================================================================
-- 3. NẠP TÀI KHOẢN KÝ QUỸ CHO 3 MILESTONES (escrows)
-- - Escrow 1 (Milestone 1): RELEASED (1.000$)
-- - Escrow 2 (Milestone 2): FUNDED (1.000$ — dùng để demo bấm nút Nghiệm thu & Giải ngân)
-- - Escrow 3 (Milestone 3): UNFUNDED (1.000$ — cho phép demo từ Bước 1 Nạp ký quỹ hoặc Bước 2 Nộp sản phẩm)
-- =============================================================================
INSERT INTO miniupwork.escrows (
    id, milestone_id, amount, status, funded_at, released_at
) VALUES
(
    1,
    1,
    1000.00,
    'RELEASED',
    TIMESTAMPTZ '2026-09-21 10:00:00+07',
    TIMESTAMPTZ '2026-10-05 16:00:00+07'
),
(
    2,
    2,
    1000.00,
    'FUNDED',
    TIMESTAMPTZ '2026-10-06 10:00:00+07',
    NULL
),
(
    3,
    3,
    1000.00,
    'UNFUNDED',
    NULL,
    NULL
);

-- =============================================================================
-- 4. NẠP HÓA ĐƠN (invoices)
-- - Invoice 1 (id = 1): Hóa đơn theo giờ của Hợp đồng 2 (10 giờ = 250$), trạng thái PAID
-- - Invoice 2 (id = 2): Hóa đơn của Milestone 1 thuộc Hợp đồng 1 (1.000$), trạng thái PAID
-- - Invoice 3 (id = 3): Hóa đơn lệch tiền 500$ (để test Truy vấn 3 - Đối soát thanh toán), trạng thái PARTIAL
-- =============================================================================
INSERT INTO miniupwork.invoices (
    id, contract_id, milestone_id, invoice_number,
    total_amount, issued_date, due_date, status
) VALUES
(
    1,
    2,
    NULL,
    'INV-2026-001',
    250.00,
    DATE '2026-10-20',
    DATE '2026-10-27',
    'PAID'
),
(
    2,
    1,
    1,
    'INV-2026-002',
    1000.00,
    DATE '2026-10-05',
    DATE '2026-10-12',
    'PAID'
),
(
    3,
    2,
    NULL,
    'INV-2026-003',
    500.00,
    DATE '2026-11-01',
    DATE '2026-11-08',
    'PARTIAL'
);

-- =============================================================================
-- 5. NẠP BẢNG CHẤM CÔNG THEO GIỜ (time_entries) CHO HỢP ĐỒNG 2 (25$/giờ)
-- - 3 dòng đầu (tổng 10 giờ = 250$): Đã gắn vào invoice_id = 1 (PAID)
-- - 2 dòng sau (tổng 6 giờ = 150$): Trạng thái APPROVED nhưng invoice_id IS NULL (phục vụ Truy vấn 2)
-- =============================================================================
INSERT INTO miniupwork.time_entries (
    id, contract_id, invoice_id, work_date, hours, description, status
) VALUES
(
    1,
    2,
    1,
    DATE '2026-10-16',
    4.00,
    'Tối ưu chỉ mục (Index) PostgreSQL và xử lý truy vấn chậm',
    'APPROVED'
),
(
    2,
    2,
    1,
    DATE '2026-10-18',
    3.50,
    'Cấu hình Connection Pool và Refactor API FastAPI',
    'APPROVED'
),
(
    3,
    2,
    1,
    DATE '2026-10-19',
    2.50,
    'Viết Unit Test kiểm thử tải và vá lỗi bảo mật phân quyền',
    'APPROVED'
),
(
    4,
    2,
    NULL,
    DATE '2026-11-10',
    3.50,
    'Thiết lập Redis Caching cho endpoint tìm kiếm công việc',
    'APPROVED'
),
(
    5,
    2,
    NULL,
    DATE '2026-11-12',
    2.50,
    'Tối ưu hóa truy vấn đối soát thanh toán và xuất báo cáo định kỳ',
    'APPROVED'
);

-- =============================================================================
-- 6. NẠP GIAO DỊCH THANH TOÁN (payments)
-- - Payment 1: Thanh toán đủ 250$ cho Invoice 1 (SUCCESS - kỳ 10/2026)
-- - Payment 2: Giải ngân đủ 1.000$ cho Invoice 2 / Milestone 1 (SUCCESS - kỳ 10/2026)
-- - Payment 3: Thanh toán 350$ cho Invoice 3 (500$) -> Thiếu 150$ (SUCCESS - kỳ 11/2026, phục vụ Truy vấn 3 & 4)
-- - Payment 4: Giao dịch 150$ bị lỗi (FAILED) cho Invoice 3 -> Chứng minh Truy vấn 3 chỉ cộng giao dịch SUCCESS
-- =============================================================================
INSERT INTO miniupwork.payments (
    id, invoice_id, paid_amount, payment_method, status, paid_at
) VALUES
(
    1,
    1,
    250.00,
    'BANK_TRANSFER',
    'SUCCESS',
    TIMESTAMPTZ '2026-10-21 14:20:00+07'
),
(
    2,
    2,
    1000.00,
    'ESCROW_RELEASE',
    'SUCCESS',
    TIMESTAMPTZ '2026-10-05 16:05:00+07'
),
(
    3,
    3,
    350.00,
    'CREDIT_CARD',
    'SUCCESS',
    TIMESTAMPTZ '2026-11-02 10:15:00+07'
),
(
    4,
    3,
    150.00,
    'CREDIT_CARD',
    'FAILED',
    TIMESTAMPTZ '2026-11-02 10:18:00+07'
);

-- =============================================================================
-- 7. NẠP ĐÁNH GIÁ (reviews)
-- - Review 1: Đánh giá 5 sao cho Hợp đồng 1 sau khi hoàn tất Milestone 1
-- =============================================================================
INSERT INTO miniupwork.reviews (
    id, contract_id, reviewer_role, rating, comment, created_at
) VALUES
(
    1,
    1,
    'CLIENT',
    5,
    'Giao diện thiết kế chuẩn mực, cấu trúc CSDL rõ ràng và bàn giao Milestone 1 đúng tiến độ cam kết.',
    TIMESTAMPTZ '2026-10-06 09:30:00+07'
);

-- Đồng bộ lại bộ đếm tự tăng (Identity Sequence) sau khi chèn ID tường minh
SELECT setval(pg_get_serial_sequence('miniupwork.contracts', 'id'), (SELECT max(id) FROM miniupwork.contracts), true);
SELECT setval(pg_get_serial_sequence('miniupwork.milestones', 'id'), (SELECT max(id) FROM miniupwork.milestones), true);
SELECT setval(pg_get_serial_sequence('miniupwork.escrows', 'id'), (SELECT max(id) FROM miniupwork.escrows), true);
SELECT setval(pg_get_serial_sequence('miniupwork.invoices', 'id'), (SELECT max(id) FROM miniupwork.invoices), true);
SELECT setval(pg_get_serial_sequence('miniupwork.time_entries', 'id'), (SELECT max(id) FROM miniupwork.time_entries), true);
SELECT setval(pg_get_serial_sequence('miniupwork.payments', 'id'), (SELECT max(id) FROM miniupwork.payments), true);
SELECT setval(pg_get_serial_sequence('miniupwork.reviews', 'id'), (SELECT max(id) FROM miniupwork.reviews), true);

COMMIT;

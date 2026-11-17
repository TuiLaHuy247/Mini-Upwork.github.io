# Mini-Upwork Phase 3 & Phase 4 · Phần Trần Quang Huy (Tích hợp đồng bộ với Phần Đạt)

Dự án bao gồm trọn bộ thiết kế Cơ sở dữ liệu (DDL 7 bảng), Dữ liệu mẫu có chủ đích (Seed Data), 4 Câu truy vấn SQL nghiệp vụ quản trị dòng tiền, Cấu trúc JSON chuẩn hóa (`fixedContract`, `hourlyContract`), cùng Giao diện Màn hình Chi tiết Hợp đồng & Bộ máy chuyển trạng thái Ký quỹ (Escrow State Machine) đồng nhất 100% với hệ thống giao diện của nhóm.

## Cấu trúc thư mục SQL (`sql/`)

1. `sql/01_schema.sql` — Lược đồ Marketplace gốc (Users, Clients, Freelancers, Jobs, Proposals).
2. `sql/02_proposal_phase3.sql` — Mở rộng vòng đời Proposal (Phase 3 - Phần Đạt).
3. `sql/03_seed.sql` — Dữ liệu mẫu cho Jobs & Proposals.
4. `sql/04_dat_queries.sql` — 4 câu truy vấn tìm việc & đề xuất (Phần Đạt).
5. `sql/05_verify_proposal.sql` — Kiểm thử tự động ràng buộc Proposal.
6. `sql/06_contracts_schema_phase3.sql` — **[Phần Huy - Bước 1]** DDL tạo 7 bảng theo đúng thứ tự phụ thuộc Cha → Con (`contracts`, `milestones`, `escrows`, `time_entries`, `invoices`, `payments`, `reviews`).
7. `sql/07_contracts_seed_phase3.sql` — **[Phần Huy - Bước 2]** Nạp dữ liệu mẫu có chủ đích (Hợp đồng 1 Trọn gói 3.000$ với 3 Milestones phủ đủ trạng thái; Hợp đồng 2 Theo giờ 25$/giờ với 10h đã lập HĐ `invoice_id = 1` và 6h chưa lập HĐ `invoice_id IS NULL`; kèm Hóa đơn lệch tiền `INV-2026-003` 500$ mới thanh toán 350$ thiếu 150$).
8. `sql/08_huy_queries_phase3.sql` — **[Phần Huy - Bước 3]** 4 câu truy vấn SQL nghiệp vụ (Milestone quá hạn, Giờ chưa lập hóa đơn, Đối soát thanh toán, Doanh thu theo kỳ).
9. `sql/09_verify_contracts_phase3.sql` — Script PL/pgSQL tự động kiểm chứng dữ liệu và kết quả 4 câu truy vấn.

## Cách chạy giao diện Demo

- **Cách 1 (Chạy trực tiếp trên trình duyệt không cần cài đặt):** Mở trực tiếp file `miniupwork/web/contracts.html` bằng trình duyệt Chrome/Edge để thao tác ngay với 2 hợp đồng mẫu (`fixedContract` và `hourlyContract`), 4 thẻ KPI, 3 Tab nghiệp vụ, luồng State Machine 4 bước của Escrow và bảng kết quả 4 câu truy vấn SQL.
- **Cách 2 (Chạy qua FastAPI Launcher `MO_DEMO.cmd`):**
  - Chạy `MO_DEMO.cmd` và mở:
    - `http://127.0.0.1:8014/contracts` — Màn hình Chi tiết Hợp đồng & Thanh toán Escrow (Phần Huy).
    - `http://127.0.0.1:8014/` — Màn hình Tìm việc & Gửi đề xuất (Phần Đạt).

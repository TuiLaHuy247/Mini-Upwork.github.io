# Kịch bản Demo và Bảo vệ Phase 3 & Phase 4 · Trần Quang Huy (N24DECE073)

## 1. Bảo vệ Thiết kế CSDL (DDL 7 bảng) & Seed Data (Trong pgAdmin)
1. Mở `sql/06_contracts_schema_phase3.sql`: Chỉ rõ thứ tự tạo bảng Cha trước, Con sau (`contracts` → `milestones` → `escrows` → `time_entries` → `invoices` → `payments` → `reviews`) và giải thích cột `time_entries.invoice_id` cho phép `NULL` khi mới chấm công, chỉ cập nhật khi phát hành hóa đơn.
2. Mở `sql/07_contracts_seed_phase3.sql` và `sql/08_huy_queries_phase3.sql`: Chạy 4 câu truy vấn để đối chiếu kết quả thực tế:
   - **Q1 (Milestone quá hạn):** Trả về Milestone #3 (`due_date = 2026-10-15`, `status = 'IN_PROGRESS'`, trễ hạn 33 ngày).
   - **Q2 (Giờ chưa lập hóa đơn):** Trả về 2 dòng `time_entries` (#4: 3.5h = 87.50$ và #5: 2.5h = 62.50$, tổng 6.0 giờ = 150.00$).
   - **Q3 (Đối soát thanh toán):** Phát hiện hóa đơn `INV-2026-003` (500$) chỉ có 1 giao dịch `SUCCESS` 350$ (bỏ qua giao dịch `FAILED` 150$), đang trả thiếu 150.00$.
   - **Q4 (Doanh thu theo kỳ):** Kỳ `2026-10` đạt `1.250,00$` (2 giao dịch) và kỳ `2026-11` đạt `350,00$` (1 giao dịch).

## 2. Demo Màn hình Chi tiết Hợp đồng & State Machine trên Trình duyệt
1. **Demo Hợp đồng trọn gói (`fixedContract` - 3.000$):**
   - Chỉ vào 4 thẻ KPI: Tổng giá trị `3.000$`, Đang giữ ký quỹ `1.000$` (Milestone 2), Đã giải ngân `1.000$` (Milestone 1), Còn lại `1.000$` (Milestone 3).
   - Tại **Milestone 2 (`SUBMITTED` + `FUNDED`)**: Bấm nút **Nghiệm thu & Giải ngân** → Escrow chuyển sang `RELEASED`, Milestone chuyển sang `APPROVED`, KPI Đang giữ ký quỹ giảm `1.000$` và Đã giải ngân tăng lên `2.000$`; mở Tab 2 để chỉ ra Hóa đơn và Giao dịch thanh toán vừa tự động sinh ra.
   - Tại **Milestone 3**: Bấm **Nạp ký quỹ (Fund Escrow)** (Bước 1) → **Nộp sản phẩm (Submit Work)** (Bước 2) → **Nghiệm thu & Giải ngân** (Bước 3) → **Gửi đánh giá (Review)** (Bước 4: chọn 5 sao, nhập nhận xét và gửi).
2. **Demo Hợp đồng theo giờ (`hourlyContract` - 25$/giờ):**
   - Bấm nút chuyển sang **2. Demo Hợp đồng theo giờ (25$/giờ)** trên thanh Header.
   - Chỉ ra bảng Time Entries (3 dòng đầu tổng 10h = 250$ đã gắn `invoice_id = 1`; 2 dòng sau tổng 6h = 150$ đang có `invoice_id = NULL`).
   - Tại khung **Xem trước Hóa đơn theo giờ** bên phải, bấm **Xuất Hóa đơn & Thanh toán giờ chưa lập HĐ** để tự động gom 6 giờ chưa lập hóa đơn thành hóa đơn mới và cập nhật `invoice_id`.

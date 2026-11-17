-- Chạy sau seed để kiểm tra trigger và ràng buộc. Toàn bộ thay đổi được rollback.
BEGIN;

DO $$
DECLARE
    test_case RECORD;
    failed_constraint TEXT;
BEGIN
    IF (SELECT COUNT(*) FROM miniupwork.app_user) <> 10
       OR (SELECT COUNT(*) FROM miniupwork.job) <> 20
       OR (SELECT COUNT(*) FROM miniupwork.proposal) <> 40 THEN
        RAISE EXCEPTION 'Chạy kiểm tra trên bộ dữ liệu mẫu của Phase 3';
    END IF;

    FOR test_case IN
        SELECT * FROM (VALUES
            ('Tự ứng tuyển khi có hai vai trò', 'proposal_self_bid',
                $sql$INSERT INTO miniupwork.proposal (proposal_id, job_id, freelancer_id, cover_letter, offered_amount)
                     VALUES (1001, 3, 3, 'Self-bid test', 100)$sql$),
            ('Gửi vào job nháp', 'proposal_requires_open_job',
                $sql$INSERT INTO miniupwork.proposal (proposal_id, job_id, freelancer_id, cover_letter, offered_amount)
                     VALUES (1001, 17, 5, 'Draft job test', 100)$sql$),
            ('Gửi vào job đã đóng', 'proposal_requires_open_job',
                $sql$INSERT INTO miniupwork.proposal (proposal_id, job_id, freelancer_id, cover_letter, offered_amount)
                     VALUES (1001, 19, 5, 'Closed job test', 100)$sql$),
            ('Gửi trùng cặp freelancer–job', 'uq_proposal_freelancer_job',
                $sql$INSERT INTO miniupwork.proposal (proposal_id, job_id, freelancer_id, cover_letter, offered_amount)
                     VALUES (1001, 1, 6, 'Duplicate test', 100)$sql$),
            ('Gửi proposal có giá bằng 0', 'proposal_amount_positive',
                $sql$INSERT INTO miniupwork.proposal (proposal_id, job_id, freelancer_id, cover_letter, offered_amount)
                     VALUES (1001, 1, 5, 'Invalid offer test', 0)$sql$),
            ('Khởi tạo proposal ở trạng thái ACCEPTED', 'proposal_initial_status',
                $sql$INSERT INTO miniupwork.proposal (proposal_id, job_id, freelancer_id, cover_letter, offered_amount, status)
                     VALUES (1001, 1, 5, 'Invalid initial status test', 100, 'ACCEPTED')$sql$),
            ('Chấp nhận proposal thứ hai của cùng job', 'uq_proposal_one_accepted_per_job',
                $sql$UPDATE miniupwork.proposal SET status = 'ACCEPTED' WHERE proposal_id = 3$sql$),
            ('Đổi giá trong thao tác duyệt', 'proposal_decision_changes',
                $sql$UPDATE miniupwork.proposal SET status = 'ACCEPTED', offered_amount = 999
                     WHERE proposal_id = 8$sql$),
            ('Mở lại proposal đã bị từ chối', 'proposal_invalid_transition',
                $sql$UPDATE miniupwork.proposal SET status = 'SUBMITTED' WHERE proposal_id = 2$sql$)
        ) AS checks(label, constraint_name, statement)
    LOOP
        BEGIN
            EXECUTE test_case.statement;
            RAISE EXCEPTION 'Đáng lẽ phải bị từ chối: %', test_case.label;
        EXCEPTION WHEN check_violation OR unique_violation THEN
            GET STACKED DIAGNOSTICS failed_constraint = CONSTRAINT_NAME;
            IF failed_constraint IS DISTINCT FROM test_case.constraint_name THEN
                RAISE EXCEPTION 'Sai ràng buộc cho %. Kỳ vọng %, nhận %',
                    test_case.label, test_case.constraint_name, failed_constraint;
            END IF;
        END;
        RAISE NOTICE 'PASS — %', test_case.label;
    END LOOP;

    INSERT INTO miniupwork.proposal (proposal_id, job_id, freelancer_id, cover_letter, offered_amount)
    VALUES (1001, 1, 5, 'Initial valid proposal', 100);
    UPDATE miniupwork.proposal SET status = 'WITHDRAWN' WHERE proposal_id = 1001;
    UPDATE miniupwork.proposal
    SET status = 'SUBMITTED', cover_letter = 'Revised valid proposal', offered_amount = 125
    WHERE proposal_id = 1001;

    IF NOT EXISTS (
        SELECT 1 FROM miniupwork.proposal
        WHERE proposal_id = 1001 AND job_id = 1 AND freelancer_id = 5
          AND status = 'SUBMITTED' AND offered_amount = 125
    ) THEN
        RAISE EXCEPTION 'Nộp lại phải cập nhật đúng proposal ban đầu';
    END IF;
    RAISE NOTICE 'PASS — Gửi, rút, nộp lại cùng proposal_id';

    UPDATE miniupwork.proposal SET status = 'WITHDRAWN' WHERE proposal_id = 1001;
    UPDATE miniupwork.job SET status = 'CLOSED' WHERE job_id = 1;
    BEGIN
        UPDATE miniupwork.proposal SET status = 'SUBMITTED' WHERE proposal_id = 1001;
        RAISE EXCEPTION 'Đáng lẽ không thể nộp lại sau khi job đóng';
    EXCEPTION WHEN check_violation THEN
        GET STACKED DIAGNOSTICS failed_constraint = CONSTRAINT_NAME;
        IF failed_constraint IS DISTINCT FROM 'proposal_requires_open_job' THEN
            RAISE;
        END IF;
    END;
    RAISE NOTICE 'PASS — Chặn nộp lại khi job đã đóng';
END;
$$;

SET CONSTRAINTS ALL IMMEDIATE;
ROLLBACK;

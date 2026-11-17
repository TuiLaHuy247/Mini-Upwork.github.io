-- Mở rộng bảng proposal của Lab 2 cho Phase 3. Chạy sau 01_schema.sql.
BEGIN;

ALTER TABLE miniupwork.proposal
    DROP CONSTRAINT proposal_status_valid,
    ADD CONSTRAINT proposal_status_valid
        CHECK (status IN ('SUBMITTED', 'SHORTLISTED', 'ACCEPTED', 'REJECTED', 'WITHDRAWN'));

-- BR-17. Một job chỉ có tối đa một proposal ACCEPTED.
CREATE UNIQUE INDEX IF NOT EXISTS uq_proposal_one_accepted_per_job
    ON miniupwork.proposal (job_id) WHERE status = 'ACCEPTED';

-- Giữ trigger và tên lỗi của Lab 2 để các thao tác gửi/rút/nộp lại vẫn dùng được.
CREATE OR REPLACE FUNCTION miniupwork.guard_proposal_lifecycle()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER
SET search_path = pg_catalog, miniupwork AS $$
DECLARE
    parent_status TEXT;
    owner_id BIGINT;
    requires_open_job BOOLEAN;
BEGIN
    IF TG_OP = 'INSERT' THEN
        IF NEW.status <> 'SUBMITTED' THEN
            RAISE EXCEPTION 'A new proposal starts in SUBMITTED'
                USING ERRCODE = '23514', CONSTRAINT = 'proposal_initial_status';
        END IF;
    ELSE
        IF NOT (
            (OLD.status = 'SUBMITTED' AND NEW.status IN ('SHORTLISTED', 'ACCEPTED', 'REJECTED', 'WITHDRAWN'))
            OR (OLD.status = 'SHORTLISTED' AND NEW.status IN ('ACCEPTED', 'REJECTED', 'WITHDRAWN'))
            OR (OLD.status = 'WITHDRAWN' AND NEW.status = 'SUBMITTED')
        ) THEN
            RAISE EXCEPTION 'The requested proposal status transition is not allowed'
                USING ERRCODE = '23514', CONSTRAINT = 'proposal_invalid_transition';
        END IF;

        IF NEW.status <> 'SUBMITTED' AND (
            NEW.cover_letter IS DISTINCT FROM OLD.cover_letter
            OR NEW.offered_amount IS DISTINCT FROM OLD.offered_amount
            OR NEW.submitted_at IS DISTINCT FROM OLD.submitted_at
        ) THEN
            IF NEW.status = 'WITHDRAWN' THEN
                RAISE EXCEPTION 'Withdrawal changes only the proposal status'
                    USING ERRCODE = '23514', CONSTRAINT = 'proposal_withdraw_changes';
            END IF;
            RAISE EXCEPTION 'A decision changes only the proposal status'
                USING ERRCODE = '23514', CONSTRAINT = 'proposal_decision_changes';
        END IF;
    END IF;

    requires_open_job := NEW.status IN ('SUBMITTED', 'SHORTLISTED', 'ACCEPTED');

    -- Dùng cùng khóa dòng với thao tác đóng job để tránh đọc trạng thái cũ.
    SELECT status, client_id INTO parent_status, owner_id
    FROM miniupwork.job
    WHERE job_id = NEW.job_id
    FOR UPDATE;

    IF owner_id = NEW.freelancer_id THEN
        RAISE EXCEPTION 'A user cannot submit a proposal to their own job'
            USING ERRCODE = '23514', CONSTRAINT = 'proposal_self_bid';
    END IF;

    -- Khi thiếu job, để khóa ngoại báo lỗi 23503.
    IF requires_open_job AND parent_status IS NOT NULL AND parent_status <> 'OPEN' THEN
        RAISE EXCEPTION 'Only OPEN jobs allow submission, shortlisting or acceptance'
            USING ERRCODE = '23514', CONSTRAINT = 'proposal_requires_open_job';
    END IF;
    RETURN NEW;
END;
$$;

COMMENT ON TABLE miniupwork.proposal IS 'One proposal lifecycle per freelancer and job. One accepted proposal per job.';

COMMIT;

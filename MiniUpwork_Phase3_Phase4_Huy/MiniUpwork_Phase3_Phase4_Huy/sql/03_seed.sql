-- Deterministic, entirely synthetic data. Run once after 01_schema.sql and 02_proposal_phase3.sql.
-- No real accounts, financial data, scraped data, or external personal records.
BEGIN;
LOCK TABLE miniupwork.app_user, miniupwork.client, miniupwork.freelancer,
    miniupwork.category, miniupwork.skill, miniupwork.freelancer_skill,
    miniupwork.job, miniupwork.fixed_price_job, miniupwork.hourly_job,
    miniupwork.job_skill, miniupwork.proposal IN SHARE ROW EXCLUSIVE MODE;
DO $$
DECLARE v_table TEXT; has_rows BOOLEAN;
BEGIN
    FOREACH v_table IN ARRAY ARRAY['app_user','client','freelancer','category','skill',
        'freelancer_skill','job','fixed_price_job','hourly_job','job_skill','proposal'] LOOP
        EXECUTE format('SELECT EXISTS (SELECT 1 FROM miniupwork.%I)', v_table) INTO has_rows;
        IF has_rows THEN
            RAISE EXCEPTION 'Seed requires empty tables; % already contains rows', v_table
                USING ERRCODE = '23514', CONSTRAINT = 'seed_requires_empty_database';
        END IF;
    END LOOP;
END;
$$;

-- Valid PBKDF2-SHA256 hashes with distinct synthetic salts. Marketplace login is
-- outside this demo, and these are not PostgreSQL role credentials.
INSERT INTO miniupwork.app_user (user_id,email,password_hash,full_name,status,created_at) VALUES
(1,'client01@example.test','pbkdf2_sha256$260000$miniupwork-lab2-user-01$rsC79fzjFsJZqGoDxKE5B8EP3ijK0IELJvOZYOWZR6o=','Demo User 01','ACTIVE','2026-09-01 09:00:00+07'),
(2,'client02@example.test','pbkdf2_sha256$260000$miniupwork-lab2-user-02$hFMiujMBVDwxQo04i5jVJQiVcReVWAswHDDEmcl5IxY=','Demo User 02','ACTIVE','2026-09-02 09:00:00+07'),
(3,'dual03@example.test','pbkdf2_sha256$260000$miniupwork-lab2-user-03$1hjjxjN13U0gAbhSkuwgYmVMR/RQ+fxHcKqqiJaZZyk=','Demo User 03','ACTIVE','2026-09-03 09:00:00+07'),
(4,'client04@example.test','pbkdf2_sha256$260000$miniupwork-lab2-user-04$sXLmcPiEFfKLD+TDxtBa1wsOiEAll6s4YxTsonHfWmI=','Demo User 04','ACTIVE','2026-09-04 09:00:00+07'),
(5,'freelancer05@example.test','pbkdf2_sha256$260000$miniupwork-lab2-user-05$fBHzi2BV52R9sGpQ9qiXDnqYKRDrs7dGBN5R5VQAo/0=','Demo User 05','ACTIVE','2026-09-05 09:00:00+07'),
(6,'freelancer06@example.test','pbkdf2_sha256$260000$miniupwork-lab2-user-06$iiPKciZlZjJUucCVhvGXcbwK7FAR6L8mTGKWfjta67o=','Demo User 06','ACTIVE','2026-09-06 09:00:00+07'),
(7,'freelancer07@example.test','pbkdf2_sha256$260000$miniupwork-lab2-user-07$7j2wxwHk63mUsFVcLNJzcEQongoWnuFp7lO4hS7f0Wk=','Demo User 07','ACTIVE','2026-09-07 09:00:00+07'),
(8,'freelancer08@example.test','pbkdf2_sha256$260000$miniupwork-lab2-user-08$kCFLeb4MVA3jjQ+JBflp9kKgf9qsnX8kCrZrTM/MOTg=','Demo User 08','ACTIVE','2026-09-08 09:00:00+07'),
(9,'freelancer09@example.test','pbkdf2_sha256$260000$miniupwork-lab2-user-09$5qC4gJSQnRXDKWBntW3ZEnZlXuU8H0v0lsZqazlB0Tc=','Demo User 09','ACTIVE','2026-09-09 09:00:00+07'),
(10,'freelancer10@example.test','pbkdf2_sha256$260000$miniupwork-lab2-user-10$NI4YILVX9BRHiMqCR/z6rtdiAkMqhww4co7RPW7CcM8=','Demo User 10','ACTIVE','2026-09-10 09:00:00+07');

INSERT INTO miniupwork.client (user_id,company_name,description)
SELECT n, 'Demo Studio ' || n, 'Synthetic client profile for the Mini-Upwork lab.'
FROM generate_series(1,4) AS g(n);
INSERT INTO miniupwork.freelancer (user_id,headline,overview,default_hourly_rate,availability)
SELECT n, 'Demo freelancer ' || n, 'Synthetic skills and experience, used only for coursework.',
       20 + n * 2, CASE WHEN n=10 THEN 'UNAVAILABLE' ELSE 'AVAILABLE' END
FROM unnest(ARRAY[3,5,6,7,8,9,10]) AS g(n);

INSERT INTO miniupwork.category(category_id,parent_category_id,category_name) VALUES
(1,NULL,'Software Development'),(2,1,'Web Development'),(3,1,'Mobile Development'),
(4,NULL,'Design'),(5,NULL,'Data Analytics'),(6,NULL,'Writing');
INSERT INTO miniupwork.skill(skill_id,skill_name) VALUES
(1,'Python'),(2,'PostgreSQL'),(3,'FastAPI'),(4,'JavaScript'),
(5,'Figma'),(6,'Data Analysis'),(7,'Technical Writing'),(8,'Testing');
INSERT INTO miniupwork.freelancer_skill(freelancer_id,skill_id,proficiency_level)
SELECT f.user_id, ((f.user_id + k) % 8) + 1, (((f.user_id + k) % 5) + 1)::smallint
FROM miniupwork.freelancer f CROSS JOIN generate_series(0,2) AS g(k);

-- Build each supertype and its matching subtype in the SAME transaction.
INSERT INTO miniupwork.job(job_id,client_id,category_id,title,description,status,job_type,posted_at)
SELECT n, 1+((n-1)%4), 2+((n-1)%5),
       CASE WHEN n%2=1 THEN 'Fixed-price demo job ' ELSE 'Hourly demo job ' END || lpad(n::text,2,'0'),
       'Synthetic job ' || n || ': build and document a small academic project.',
       'DRAFT', CASE WHEN n%2=1 THEN 'FIXED_PRICE' ELSE 'HOURLY' END,
       TIMESTAMPTZ '2026-09-15 09:00:00+07' + n * INTERVAL '1 hour'
FROM generate_series(1,20) AS g(n);
INSERT INTO miniupwork.fixed_price_job(job_id,budget_amount)
SELECT job_id, 500 + 75*job_id FROM miniupwork.job WHERE job_type='FIXED_PRICE';
INSERT INTO miniupwork.hourly_job(job_id,rate_min,rate_max)
SELECT job_id, 15+5*(job_id%5), 45+5*(job_id%5) FROM miniupwork.job WHERE job_type='HOURLY';
INSERT INTO miniupwork.job_skill(job_id,skill_id,required_level)
SELECT j.job_id, ((j.job_id+k)%8)+1, (((j.job_id+k)%5)+1)::smallint
FROM miniupwork.job j CROSS JOIN generate_series(0,1) AS g(k);
UPDATE miniupwork.job SET status='OPEN' WHERE job_id NOT IN (17,18);

-- Jobs 1..4 receive 3 proposals each; jobs 5..16,19,20 receive 2 each: 40 total.
-- A dual-role user is deliberately excluded from their own job.
WITH candidates AS (
    SELECT j.job_id, j.job_type, f.user_id AS freelancer_id,
           row_number() OVER (PARTITION BY j.job_id ORDER BY ((f.user_id+j.job_id)%7),f.user_id) AS choice_no,
           fp.budget_amount, hj.rate_min
    FROM miniupwork.job j
    JOIN miniupwork.freelancer f ON f.user_id<>j.client_id
    LEFT JOIN miniupwork.fixed_price_job fp ON fp.job_id=j.job_id
    LEFT JOIN miniupwork.hourly_job hj ON hj.job_id=j.job_id
    WHERE j.status='OPEN'
), selected AS (
    SELECT *, row_number() OVER (ORDER BY job_id,freelancer_id) AS proposal_id
    FROM candidates WHERE choice_no <= CASE WHEN job_id<=4 THEN 3 ELSE 2 END
)
INSERT INTO miniupwork.proposal(proposal_id,job_id,freelancer_id,cover_letter,offered_amount,status,submitted_at)
SELECT proposal_id,job_id,freelancer_id,
       'Demo proposal by freelancer ' || freelancer_id || ' for job ' || job_id || '.',
       CASE WHEN job_type='FIXED_PRICE' THEN budget_amount-10*choice_no ELSE rate_min+choice_no END,
       'SUBMITTED', TIMESTAMPTZ '2026-10-01 09:00:00+07' + job_id*INTERVAL '1 hour' + freelancer_id*INTERVAL '1 minute'
FROM selected ORDER BY proposal_id;
UPDATE miniupwork.proposal SET status='WITHDRAWN' WHERE proposal_id%7=0;

-- One accepted proposal for a fixed-price job and one for an hourly job.
-- Proposal 4 demonstrates a decision after shortlisting. Proposal 10 stays pending.
UPDATE miniupwork.proposal SET status = 'SHORTLISTED' WHERE proposal_id IN (4, 10);
UPDATE miniupwork.proposal SET status = 'ACCEPTED' WHERE proposal_id IN (1, 4);
UPDATE miniupwork.proposal SET status = 'REJECTED' WHERE proposal_id IN (2, 5, 6);

UPDATE miniupwork.job SET status='CLOSED' WHERE job_id=19;
UPDATE miniupwork.job SET status='CANCELLED' WHERE job_id=20;

-- Explicit seed IDs do not advance identity sequences; align every sequence.
SELECT setval(pg_get_serial_sequence('miniupwork.app_user','user_id'),(SELECT max(user_id) FROM miniupwork.app_user),true);
SELECT setval(pg_get_serial_sequence('miniupwork.category','category_id'),(SELECT max(category_id) FROM miniupwork.category),true);
SELECT setval(pg_get_serial_sequence('miniupwork.skill','skill_id'),(SELECT max(skill_id) FROM miniupwork.skill),true);
SELECT setval(pg_get_serial_sequence('miniupwork.job','job_id'),(SELECT max(job_id) FROM miniupwork.job),true);
SELECT setval(pg_get_serial_sequence('miniupwork.proposal','proposal_id'),(SELECT max(proposal_id) FROM miniupwork.proposal),true);

DO $$
BEGIN
    IF (SELECT count(*) FROM miniupwork.app_user)<>10
       OR (SELECT count(*) FROM miniupwork.job)<>20
       OR (SELECT count(*) FROM miniupwork.proposal)<>40 THEN
        RAISE EXCEPTION 'Unexpected seed row counts';
    END IF;
END;
$$;
-- Force deferred checks now as well as at COMMIT to surface incomplete seed data.
SET CONSTRAINTS ALL IMMEDIATE;
COMMIT;

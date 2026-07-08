-- 데이터 확인
DESC kt2_log;
SELECT * FROM kt2_log
LIMIT 20;

-- 날짜 컬럼 추가 및 datetime 변환
ALTER TABLE kt2_log ADD COLUMN datetime DATETIME;

UPDATE kt2_log 
SET datetime = FROM_UNIXTIME(timestamp / 1000);

-- 유저별 평균 문제풀이 시간
WITH problem_time AS (
    SELECT
        user_id,
        item_id,
        MIN(CASE WHEN action_type = 'enter' THEN datetime END) AS start_time,
        MIN(CASE WHEN action_type = 'submit' THEN datetime END) AS submit_time
    FROM kt2_log
    GROUP BY user_id, item_id
),

duration AS (
    SELECT
        user_id,
        item_id,
        TIMESTAMPDIFF(SECOND, start_time, submit_time) AS solve_time
    FROM problem_time
    WHERE start_time IS NOT NULL
      AND submit_time IS NOT NULL
)

SELECT
    user_id,
    AVG(solve_time) AS avg_solve_time
FROM duration
GROUP BY user_id;

-- 유저별 pc 사용 비율
WITH user_platform_summary AS (
    SELECT
        user_id,
        COUNT(*) AS total_log_count,
        SUM(
            CASE 
                WHEN platform = 'web' THEN 1
                ELSE 0 
            END
        ) AS pc_log_count
    FROM kt2_log
    GROUP BY user_id
)

SELECT
    user_id,
    total_log_count,
    pc_log_count,
    ROUND(
        COALESCE(pc_log_count * 1.0 / NULLIF(total_log_count, 0), 0), 
        2
    ) AS pc_ratio
FROM user_platform_summary
ORDER BY pc_ratio DESC, total_log_count DESC;

-- 유저별 활동기간
SELECT user_id, DATEDIFF(MAX(datetime), MIN(datetime)) + 1 activity_time
FROM kt2_log
GROUP BY user_id
ORDER BY activity_time DESC;

-- 유저별 활동 시간대 비율
WITH user_hourly_raw AS (
    SELECT
        user_id,
        COUNT(*) AS total_log_count,
        SUM(CASE WHEN HOUR(datetime) >= 0 AND HOUR(datetime) < 6 THEN 1 ELSE 0 END) AS dawn_log_count,
        SUM(CASE WHEN HOUR(datetime) >= 6 AND HOUR(datetime) < 12 THEN 1 ELSE 0 END) AS morning_log_count,
        SUM(CASE WHEN HOUR(datetime) >= 12 AND HOUR(datetime) < 18 THEN 1 ELSE 0 END) AS afternoon_log_count,
        SUM(CASE WHEN HOUR(datetime) >= 18 AND HOUR(datetime) < 24 THEN 1 ELSE 0 END) AS evening_log_count
    FROM kt2_log
    GROUP BY user_id
)

SELECT
    user_id,
    total_log_count,
    ROUND(COALESCE(dawn_log_count * 1.0 / NULLIF(total_log_count, 0), 0), 2) AS dawn_ratio,
    ROUND(COALESCE(morning_log_count * 1.0 / NULLIF(total_log_count, 0), 0), 2) AS morning_ratio,
    ROUND(COALESCE(afternoon_log_count * 1.0 / NULLIF(total_log_count, 0), 0), 2) AS afternoon_ratio,
    ROUND(COALESCE(evening_log_count * 1.0 / NULLIF(total_log_count, 0), 0), 2) AS evening_ratio
FROM user_hourly_raw;

-- 유저별 최종접속 경과일
SELECT 
    user_id,
    MAX(datetime) AS last_login_time,
    (SELECT MAX(datetime) FROM kt2_log) AS max_service_time,
    DATEDIFF(
        (SELECT MAX(datetime) FROM kt2_log), 
        MAX(datetime)
    ) AS days_since_last_login
FROM kt2_log
GROUP BY user_id;

-- 유저별 문제풀이 횟수
SELECT user_id, COUNT(*) frequency_count
FROM kt2_log
WHERE action_type = 'submit'
GROUP BY user_id;

-- 최종접속 경과일 (recency), 문제풀이 횟수 (frequency)의 평균 -> 사용자 분류 기준 (핵심 학습자 / 잠재 학습자 / 고성취 이탈 / 저성취 이탈)
WITH max_date_cte AS (
    SELECT MAX(datetime) AS max_dataset_time FROM kt2_log
),

user_metrics AS (
    SELECT 
        k.user_id,
        MAX(k.datetime) AS user_last_time,
        COUNT(CASE WHEN k.action_type = 'submit' THEN 1 END) AS total_submit_count
    FROM kt2_log k
    GROUP BY k.user_id
),

user_durations AS (
    SELECT 
        m.user_id,
        TIMESTAMPDIFF(DAY, m.user_last_time, c.max_dataset_time) AS recency_days,
        m.total_submit_count AS frequency_count
    FROM user_metrics m
    CROSS JOIN max_date_cte c
)

SELECT 
    ROUND(AVG(recency_days), 1) AS overall_avg_recency_days,
    ROUND(AVG(frequency_count), 1) AS overall_avg_frequency_count
FROM user_durations;

-- 세그먼트 분류
-- 핵심 학습자: 유저별 recency가 평균보다 낮고 유저별 frequency가 평균보다 높음
-- 잠재 학습자: 유저별 rececny & frequency가 평균보다 낮음
-- 고성취 이탈: 유저별 recency & frequency가 평균보다 높음
-- 저성취 이탈: 유저별 recency가 평균보다 높고 유저별 frequency가 평균보다 낮음
WITH max_date_cte AS (
    SELECT MAX(datetime) AS max_dataset_time FROM kt2_log
),

user_metrics AS (
    SELECT 
        k.user_id,
        MAX(k.datetime) AS user_last_time,
        COUNT(CASE WHEN k.action_type = 'submit' THEN 1 END) AS total_submit_count
    FROM kt2_log k
    GROUP BY k.user_id
),

user_durations AS (
    SELECT 
        m.user_id,
        TIMESTAMPDIFF(DAY, m.user_last_time, c.max_dataset_time) AS recency_days,
        m.total_submit_count AS frequency_count
    FROM user_metrics m
    CROSS JOIN max_date_cte c
),

avg_values AS (
    SELECT 
        AVG(recency_days) AS avg_recency,
        AVG(frequency_count) AS avg_frequency
    FROM user_durations
)

SELECT 
    u.user_id,
    u.recency_days,
    u.frequency_count,

    CASE
        WHEN u.recency_days <= a.avg_recency 
             AND u.frequency_count >= a.avg_frequency
            THEN '핵심 학습자'

        WHEN u.recency_days <= a.avg_recency 
             AND u.frequency_count < a.avg_frequency
            THEN '잠재 학습자'

        WHEN u.recency_days > a.avg_recency 
             AND u.frequency_count >= a.avg_frequency
            THEN '고성취 이탈'

        WHEN u.recency_days > a.avg_recency 
             AND u.frequency_count < a.avg_frequency
            THEN '저성취 이탈'
    END AS user_segment

FROM user_durations u
CROSS JOIN avg_values a;

-- 데이터 마트 구축
CREATE TABLE data_mart AS

WITH 

-- 1. 평균 문제 풀이 시간
problem_time AS (
    SELECT
        user_id,
        item_id,
        MIN(CASE WHEN action_type = 'enter' THEN datetime END) AS start_time,
        MIN(CASE WHEN action_type = 'submit' THEN datetime END) AS submit_time
    FROM kt2_log
    GROUP BY user_id, item_id
),

duration AS (
    SELECT
        user_id,
        TIMESTAMPDIFF(SECOND, start_time, submit_time) AS solve_time
    FROM problem_time
    WHERE start_time IS NOT NULL
      AND submit_time IS NOT NULL
),

avg_time AS (
    SELECT
        user_id,
        AVG(solve_time) AS avg_solve_time
    FROM duration
    GROUP BY user_id
),

-- 2. 플랫폼 비율
platform_ratio AS (
    SELECT
        user_id,
        ROUND(
            SUM(CASE WHEN platform = 'web' THEN 1 ELSE 0 END) * 1.0 
            / COUNT(*), 2
        ) AS pc_ratio
    FROM kt2_log
    GROUP BY user_id
),

-- 3. 활동 기간
activity AS (
    SELECT
        user_id,
        DATEDIFF(MAX(datetime), MIN(datetime)) + 1 AS activity_days
    FROM kt2_log
    GROUP BY user_id
),

-- 4. 활동 시간대 비율
time_ratio AS (
    SELECT
        user_id,
        ROUND(SUM(CASE WHEN HOUR(datetime) < 6 THEN 1 ELSE 0 END) / COUNT(*), 2) AS dawn_ratio,
        ROUND(SUM(CASE WHEN HOUR(datetime) BETWEEN 6 AND 11 THEN 1 ELSE 0 END) / COUNT(*), 2) AS morning_ratio,
        ROUND(SUM(CASE WHEN HOUR(datetime) BETWEEN 12 AND 17 THEN 1 ELSE 0 END) / COUNT(*), 2) AS afternoon_ratio,
        ROUND(SUM(CASE WHEN HOUR(datetime) >= 18 THEN 1 ELSE 0 END) / COUNT(*), 2) AS evening_ratio
    FROM kt2_log
    GROUP BY user_id
),

-- 5. recency & frequency + 세그먼트
max_date AS (
    SELECT MAX(datetime) AS max_dt FROM kt2_log
),

user_base AS (
    SELECT
        user_id,
        MAX(datetime) AS last_dt,
        COUNT(CASE WHEN action_type = 'submit' THEN 1 END) AS frequency
    FROM kt2_log
    GROUP BY user_id
),

rf AS (
    SELECT
        u.user_id,
        TIMESTAMPDIFF(DAY, u.last_dt, m.max_dt) AS recency,
        u.frequency
    FROM user_base u
    CROSS JOIN max_date m
),

avg_rf AS (
    SELECT
        AVG(recency) AS avg_recency,
        AVG(frequency) AS avg_frequency
    FROM rf
),

segment AS (
    SELECT
        r.user_id,
        r.recency,
        r.frequency,
        CASE
            WHEN r.recency <= a.avg_recency AND r.frequency >= a.avg_frequency THEN '핵심 학습자'
            WHEN r.recency <= a.avg_recency AND r.frequency < a.avg_frequency THEN '잠재 학습자'
            WHEN r.recency > a.avg_recency AND r.frequency >= a.avg_frequency THEN '고성취 이탈'
            ELSE '저성취 이탈'
        END AS user_segment
    FROM rf r
    CROSS JOIN avg_rf a
)

SELECT
    s.user_id,
    s.recency,
    s.frequency,
    s.user_segment,
    a.avg_solve_time,
    p.pc_ratio,
    act.activity_days,
    t.dawn_ratio,
    t.morning_ratio,
    t.afternoon_ratio,
    t.evening_ratio

FROM segment s
JOIN avg_time a ON s.user_id = a.user_id
JOIN platform_ratio p ON s.user_id = p.user_id
JOIN activity act ON s.user_id = act.user_id
JOIN time_ratio t ON s.user_id = t.user_id;

SELECT * FROM data_mart;
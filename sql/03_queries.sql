-- =====================================================================
-- Основні SQL-операції (підрозділ 3.1) і запити-звіти (підрозділ 3.2)
-- Виконувати після 01_schema.sql і 02_data.sql, по одному запиту
-- (у MySQL Workbench: курсор на запиті, Ctrl+Enter)
-- =====================================================================
USE rehab_center;

-- Дата звіту. У робочій системі замість змінної використовується CURDATE()
SET @today = '2026-10-08';

-- =====================================================================
-- 3.1. ОСНОВНІ ОПЕРАЦІЇ
-- =====================================================================

-- 3.1.1. Пацієнти з прізвищем на «-чук», зареєстровані у вересні
SELECT client_id, last_name, first_name, phone, registered_at
  FROM clients
 WHERE last_name LIKE '%чук'
   AND registered_at BETWEEN '2026-09-01' AND '2026-09-30'
 ORDER BY registered_at, last_name;

-- 3.1.2. Процедури вартістю від 300 до 500 грн, від найдорожчої
SELECT procedure_id, name, duration_min, price
  FROM procedures
 WHERE price BETWEEN 300 AND 500
 ORDER BY price DESC, name;

-- 3.1.3. Оновлення контактних даних пацієнтки
UPDATE clients
   SET phone = '+380661234517',
       email = 'galyna.kuzmych@example.com'
 WHERE client_id = 17;

-- 3.1.4. Позначення сеансу проведеним: останній сеанс курсу 16.
--        Тригер trg_sessions_au автоматично завершує курс
SELECT course_id, status FROM treatment_courses WHERE course_id = 16;   -- active
UPDATE sessions SET status = 'done' WHERE session_id = 211;
SELECT course_id, status FROM treatment_courses WHERE course_id = 16;   -- completed

-- 3.1.5. Спроба видалити пацієнта з історією лікування: блокує FK
DELETE FROM clients WHERE client_id = 1;
-- Error Code: 1451. Cannot delete or update a parent row:
-- a foreign key constraint fails (... CONSTRAINT `fk_courses_client` ...)

-- 3.1.6. Видалення помилково зареєстрованого пацієнта без курсів
DELETE FROM clients WHERE client_id = 18;    -- 1 row(s) affected

-- 3.1.7. Транзакція з підтвердженням: новий курс, його склад і оплата
START TRANSACTION;
INSERT INTO treatment_courses (client_id, curator_id, start_date, end_date, diagnosis, goal)
     VALUES (17, 2, '2026-10-12', '2026-11-06', 'Гонартроз правого колінного суглоба II ступеня',
             'Зменшення болю в колінному суглобі');
SET @new_course = LAST_INSERT_ID();
INSERT INTO course_procedures (course_id, procedure_id, planned_sessions)
VALUES (@new_course, 1, 10), (@new_course, 6, 8);
INSERT INTO payments (course_id, amount, paid_at, method)
VALUES (@new_course, 6500.00, '2026-10-08 12:15:00', 'card');
COMMIT;

-- 3.1.8. Транзакція з відкатом: помилкове підвищення цін на 10 %
--        вартість уже призначеного курсу не змінюється, бо ціну зафіксовано в course_procedures
START TRANSACTION;
UPDATE procedures SET price = ROUND(price * 1.10, 2) WHERE procedure_id > 0;
SELECT name, price FROM procedures WHERE procedure_id IN (1, 4);   -- 495.00, 440.00
SELECT course_id, planned_cost FROM v_client_report WHERE course_id = 1;   -- 7700.00
ROLLBACK;
SELECT name, price FROM procedures WHERE procedure_id IN (1, 4);   -- 450.00, 400.00

-- 3.1.9. Перевірка тригерів
-- а) коректний сеанс: запис успішний
INSERT INTO sessions (course_id, procedure_id, specialist_id, room_id, start_at)
VALUES (14, 1, 2, 1, '2026-10-12 09:30:00');

-- б) фахівець Литвин (id 4) о 15:20 08.10 уже проводить сеанс
INSERT INTO sessions (course_id, procedure_id, specialist_id, room_id, start_at)
VALUES (13, 7, 4, 3, '2026-10-08 15:20:00');
-- Error Code: 1644. Накладка: фахівець уже має сеанс у цей час

-- в) масажний кабінет 102 (місткість 1) зайнятий з 11:10 до 11:40
INSERT INTO sessions (course_id, procedure_id, specialist_id, room_id, start_at)
VALUES (9, 4, 3, 2, '2026-10-08 11:20:00');
-- Error Code: 1644. Накладка: кабінет у цей час заповнений

-- г) курс 15 скасовано
INSERT INTO sessions (course_id, procedure_id, specialist_id, room_id, start_at)
VALUES (15, 14, 1, 1, '2026-10-13 15:30:00');
-- Error Code: 1644. Курс не активний: запис сеансу неможливий

-- ґ) масажистку призначено на фізіотерапевтичну процедуру
INSERT INTO sessions (course_id, procedure_id, specialist_id, room_id, start_at)
VALUES (13, 7, 3, 3, '2026-10-08 16:00:00');
-- Error Code: 1644. Спеціалізація фахівця не відповідає процедурі

-- д) запис прогресу для сеансу, який ще не проведено
INSERT INTO progress_records (course_id, session_id, recorded_on, pain_score)
VALUES (10, 202, '2026-10-08', 5);
-- Error Code: 1644. Прогрес фіксується лише для проведеного сеансу

-- е) оцінка болю поза шкалою: CHECK-обмеження
INSERT INTO progress_records (course_id, recorded_on, pain_score)
VALUES (10, '2026-10-08', 12);
-- Error Code: 3819. Check constraint 'chk_progress_pain' is violated.

-- є) понад план: процедуру 8 у курсі 11 уже заплановано 6 разів із 6
INSERT INTO sessions (course_id, procedure_id, specialist_id, room_id, start_at)
VALUES (11, 8, 4, 3, '2026-10-12 10:00:00');
-- Error Code: 1644. Перевищено заплановану кількість сеансів процедури

-- ж) пацієнтка Левчук А. С. 09.10 з 11:30 до 12:10 у басейні
INSERT INTO sessions (course_id, procedure_id, specialist_id, room_id, start_at)
VALUES (13, 7, 4, 3, '2026-10-09 11:40:00');
-- Error Code: 1644. Накладка: пацієнт уже має сеанс у цей час

-- з) перенесення сеансу завершеного курсу 3
UPDATE sessions SET start_at = '2026-09-26 08:00:00' WHERE session_id = 1;
-- Error Code: 1644. Курс завершено або скасовано: зміна сеансу неможлива

-- и) відновлення завершеного курсу
UPDATE treatment_courses SET status = 'active' WHERE course_id = 3;
-- Error Code: 1644. Завершений або скасований курс не можна відновити

-- і) ручне завершення курсу з невиконаним планом
UPDATE treatment_courses SET status = 'completed' WHERE course_id = 13;
-- Error Code: 1644. Курс не можна завершити: план не виконано

-- ї) зміна запису прогресу курсу 1 на сеанс курсу 2
UPDATE progress_records SET session_id = 6 WHERE record_id = 11;
-- Error Code: 1644. Сеанс не належить вказаному курсу

-- =====================================================================
-- 3.2. ЗАПИТИ-ЗВІТИ
-- =====================================================================

-- Звіт 1. Відсоток проходження курсів
SELECT course_id, client_name, status, planned_total,
       done_cnt, missed_cnt, completion_pct
  FROM v_course_completion
 ORDER BY completion_pct DESC, course_id;

-- Звіт 2. Пацієнти, які пропустили більше двох сеансів
SELECT c.client_id,
       CONCAT(c.last_name, ' ', c.first_name) AS client_name,
       c.phone,
       COUNT(*)                               AS missed_cnt,
       MAX(DATE(s.start_at))                  AS last_missed
  FROM sessions s
  JOIN treatment_courses tc ON tc.course_id = s.course_id
  JOIN clients c            ON c.client_id  = tc.client_id
 WHERE s.status = 'missed'
 GROUP BY c.client_id, c.last_name, c.first_name, c.phone
HAVING COUNT(*) > 2
 ORDER BY missed_cnt DESC;

-- Звіт 3. Завантаження фахівців за тиждень 28.09-04.10 з рейтингом
SELECT CONCAT(sp.last_name, ' ', LEFT(sp.first_name, 1), '.') AS specialist,
       z.name                                    AS specialization,
       COUNT(*)                                  AS sessions_cnt,
       ROUND(SUM(p.duration_min) / 60, 1)        AS hours,
       RANK() OVER (ORDER BY SUM(p.duration_min) DESC) AS load_rank
  FROM sessions s
  JOIN specialists sp     ON sp.specialist_id    = s.specialist_id
  JOIN specializations z  ON z.specialization_id = sp.specialization_id
  JOIN procedures p       ON p.procedure_id      = s.procedure_id
 WHERE s.start_at >= '2026-09-28'
   AND s.start_at <  '2026-10-05'
   AND s.status <> 'cancelled'
 GROUP BY sp.specialist_id, sp.last_name, sp.first_name, z.name
 ORDER BY load_rank;

-- Звіт 4. Завантаження кабінетів по днях (хвилини зайнятості), 28.09-02.10
SELECT DATE(s.start_at) AS day,
       SUM(CASE WHEN r.room_number = '101' THEN p.duration_min ELSE 0 END) AS r101_gym,
       SUM(CASE WHEN r.room_number = '102' THEN p.duration_min ELSE 0 END) AS r102_massage,
       SUM(CASE WHEN r.room_number = '103' THEN p.duration_min ELSE 0 END) AS r103_physio,
       SUM(CASE WHEN r.room_number = '104' THEN p.duration_min ELSE 0 END) AS r104_ergo,
       SUM(CASE WHEN r.room_number = '105' THEN p.duration_min ELSE 0 END) AS r105_psych,
       SUM(CASE WHEN r.room_number = 'Б-1' THEN p.duration_min ELSE 0 END) AS pool,
       COUNT(*) AS sessions_cnt
  FROM sessions s
  JOIN rooms r      ON r.room_id      = s.room_id
  JOIN procedures p ON p.procedure_id = s.procedure_id
 WHERE s.start_at >= '2026-09-28'
   AND s.start_at <  '2026-10-03'
   AND s.status <> 'cancelled'
 GROUP BY DATE(s.start_at)
 ORDER BY day;

-- Звіт 5. Розклад фахівця Мельника Т. І. (id 1) на 08.10.2026
CALL sp_specialist_schedule(1, '2026-10-08');

-- Звіт 6. Динаміка оцінки болю: перший і останній записи курсу
WITH ranked AS (
    SELECT pr.course_id,
           pr.pain_score,
           pr.recorded_on,
           ROW_NUMBER() OVER (PARTITION BY pr.course_id
                              ORDER BY pr.recorded_on, pr.record_id)           AS rn_first,
           ROW_NUMBER() OVER (PARTITION BY pr.course_id
                              ORDER BY pr.recorded_on DESC, pr.record_id DESC) AS rn_last,
           COUNT(*)     OVER (PARTITION BY pr.course_id)                       AS records_cnt
      FROM progress_records pr
)
SELECT f.course_id,
       CONCAT(c.last_name, ' ', c.first_name) AS client_name,
       f.records_cnt,
       f.pain_score                     AS pain_first,
       l.pain_score                     AS pain_last,
       l.pain_score - f.pain_score      AS delta,
       DATEDIFF(l.recorded_on, f.recorded_on) AS days_between
  FROM ranked f
  JOIN ranked l             ON l.course_id = f.course_id AND l.rn_last = 1
  JOIN treatment_courses tc ON tc.course_id = f.course_id
  JOIN clients c            ON c.client_id  = tc.client_id
 WHERE f.rn_first = 1
   AND f.records_cnt > 1
 ORDER BY delta, f.course_id;

-- Звіт 7. Найпопулярніші процедури за кількістю проведених сеансів
SELECT p.name,
       COUNT(*)                       AS done_cnt,
       COUNT(DISTINCT s.course_id)    AS courses_cnt,
       SUM(s.price)                   AS revenue,
       ROUND(COUNT(*) * 100 / (SELECT COUNT(*) FROM sessions WHERE status = 'done'), 1)
                                      AS share_pct,
       DENSE_RANK() OVER (ORDER BY COUNT(*) DESC) AS popularity
  FROM sessions s
  JOIN procedures p ON p.procedure_id = s.procedure_id
 WHERE s.status = 'done'
 GROUP BY p.procedure_id, p.name
 ORDER BY popularity, p.name
 LIMIT 5;

-- Звіт 8. Активні курси, що завершуються протягом найближчих 7 днів
SELECT v.course_id,
       v.client_name,
       v.end_date,
       DATEDIFF(v.end_date, @today)    AS days_left,
       v.planned_total - v.done_cnt    AS sessions_left,
       v.completion_pct
  FROM v_course_completion v
 WHERE v.status = 'active'
   AND v.end_date BETWEEN @today AND @today + INTERVAL 7 DAY
 ORDER BY v.end_date;

-- Звіт 9. Тривалість курсу за типами процедур: запланована і фактична (днів)
--         фактична - від першого до останнього проведеного сеансу завершеного курсу
SELECT CASE p.room_type
           WHEN 'gym'     THEN 'Кінезіотерапія і ЛФК'
           WHEN 'massage' THEN 'Масаж'
           WHEN 'physio'  THEN 'Фізіотерапія'
           WHEN 'pool'    THEN 'Гідрокінезотерапія'
           WHEN 'ergo'    THEN 'Ерготерапія'
           WHEN 'psych'   THEN 'Психологічний супровід'
       END                                                     AS procedure_type,
       COUNT(*)                                                AS courses_cnt,
       ROUND(AVG(DATEDIFF(tc.end_date, tc.start_date) + 1), 1) AS planned_days,
       SUM(tc.status = 'completed')                            AS completed_cnt,
       ROUND(AVG(CASE WHEN tc.status = 'completed'
                      THEN DATEDIFF(f.last_day, f.first_day) + 1 END), 1) AS actual_days
  FROM (SELECT DISTINCT cp.course_id, pr.room_type
          FROM course_procedures cp
          JOIN procedures pr ON pr.procedure_id = cp.procedure_id) p
  JOIN treatment_courses tc ON tc.course_id = p.course_id
  LEFT JOIN (SELECT course_id, MIN(DATE(start_at)) AS first_day, MAX(DATE(start_at)) AS last_day
               FROM sessions WHERE status = 'done' GROUP BY course_id) f
         ON f.course_id = tc.course_id
 WHERE tc.status <> 'cancelled'
 GROUP BY p.room_type
 ORDER BY planned_days DESC;

-- Звіт 10. Активні фахівці без жодного сеансу за 28.09-09.10
SELECT sp.specialist_id,
       CONCAT_WS(' ', sp.last_name, sp.first_name, sp.middle_name) AS specialist,
       z.name AS specialization,
       sp.experience_years
  FROM specialists sp
  JOIN specializations z ON z.specialization_id = sp.specialization_id
  LEFT JOIN sessions s
         ON s.specialist_id = sp.specialist_id
        AND s.start_at >= '2026-09-28'
        AND s.start_at <  '2026-10-10'
        AND s.status <> 'cancelled'
 WHERE sp.is_active = TRUE
   AND s.session_id IS NULL;

-- Звіт 11. Надходження за місяцями і вартість фактично наданих послуг
SELECT m.month,
       m.payments_cnt,
       m.card_sum,
       m.cash_sum,
       m.transfer_sum,
       m.total_paid,
       (SELECT SUM(s.price)
          FROM sessions s
         WHERE s.status = 'done'
           AND DATE_FORMAT(s.start_at, '%Y-%m') = m.month) AS services_value
  FROM (SELECT DATE_FORMAT(paid_at, '%Y-%m')                       AS month,
               COUNT(*)                                            AS payments_cnt,
               SUM(CASE WHEN method = 'card'     THEN amount ELSE 0 END) AS card_sum,
               SUM(CASE WHEN method = 'cash'     THEN amount ELSE 0 END) AS cash_sum,
               SUM(CASE WHEN method = 'transfer' THEN amount ELSE 0 END) AS transfer_sum,
               SUM(amount)                                         AS total_paid
          FROM payments
         GROUP BY DATE_FORMAT(paid_at, '%Y-%m')) m
 ORDER BY m.month;

-- Звіт 12. Загальний звіт по пацієнту через представлення:
--          активний курс Шевчука А. М. і скасований курс Демчук О. В.
SELECT client_name, course_id, diagnosis, curator, start_date, end_date, status,
       procedures_list, planned_total, done_cnt, completion_pct,
       pain_first, pain_last, planned_cost, delivered_cost, paid, debt
  FROM v_client_report
 WHERE client_id IN (2, 15)
 ORDER BY course_id;

-- Перевірка прав фахівця. Виконувати після 03_queries.sql, підключившись як melnyk:
--   mysql -u melnyk -p rehab_center      (пароль Mel#2026pass)
-- 1) власні сеанси на 08.10.2026 - лише сеанси Мельника Т. І.
SELECT session_id, TIME_FORMAT(start_at, '%H:%i') AS start_time, procedure_name,
       room_number, client_name, status
  FROM v_my_sessions
 WHERE start_at >= '2026-10-08' AND start_at < '2026-10-09'
 ORDER BY start_at;
-- 2) пряме читання таблиці сеансів заборонено
SELECT * FROM sessions LIMIT 1;
-- Error Code: 1142. SELECT command denied to user 'melnyk'@'localhost' for table 'sessions'
-- 3) спроба позначити чужий сеанс (фахівець Гнатюк О. С.)
CALL sp_set_session_status(208, 'done');
-- Error Code: 1644. Сеанс не належить поточному фахівцю
-- 4) позначення власного сеансу і запис прогресу
CALL sp_set_session_status(202, 'done');
CALL sp_add_progress(10, 202, '2026-10-08', 4, NULL, 'good', 'Кукса без набряку');
SELECT recorded_on, pain_score, wellbeing, comment FROM v_my_progress WHERE course_id = 10;

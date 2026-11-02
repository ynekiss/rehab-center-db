-- База даних реабілітаційного центру (rehab_center), MySQL 8.0.16+; скрипт можна виконувати повторно
DROP DATABASE IF EXISTS rehab_center;
CREATE DATABASE rehab_center CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci; USE rehab_center;
-- 1. Довідник спеціалізацій фахівців
CREATE TABLE specializations (
    specialization_id INT          NOT NULL AUTO_INCREMENT,
    name              VARCHAR(100) NOT NULL,
    description       VARCHAR(255) NULL,
    CONSTRAINT pk_specializations PRIMARY KEY (specialization_id),
    CONSTRAINT uq_specializations_name UNIQUE (name)
) ENGINE = InnoDB;
-- 2. Пацієнти (діагноз і скерування зберігаються в курсі, бо належать зверненню)
CREATE TABLE clients (
    client_id     INT          NOT NULL AUTO_INCREMENT,
    last_name     VARCHAR(50)  NOT NULL, first_name VARCHAR(50) NOT NULL, middle_name VARCHAR(50) NULL,
    birth_date    DATE         NOT NULL,
    gender        ENUM('male', 'female') NOT NULL,
    phone         VARCHAR(20)  NOT NULL,
    email         VARCHAR(100) NULL,
    registered_at DATE         NOT NULL DEFAULT (CURRENT_DATE),
    CONSTRAINT pk_clients PRIMARY KEY (client_id),
    -- захист від повторної реєстрації; телефон може бути спільним для членів родини
    CONSTRAINT uq_clients_person UNIQUE (last_name, first_name, birth_date),
    CONSTRAINT uq_clients_email UNIQUE (email),
    CONSTRAINT chk_clients_phone CHECK (phone REGEXP '^[+]380[0-9]{9}$'),
    CONSTRAINT chk_clients_email CHECK (email LIKE '%_@_%._%'),
    CONSTRAINT chk_clients_birth CHECK (birth_date >= '1900-01-01')
) ENGINE = InnoDB;
CREATE INDEX idx_clients_phone ON clients (phone);
-- 3. Фахівці центру (db_login - обліковий запис MySQL фахівця)
CREATE TABLE specialists (
    specialist_id     INT         NOT NULL AUTO_INCREMENT,
    last_name         VARCHAR(50) NOT NULL, first_name VARCHAR(50) NOT NULL, middle_name VARCHAR(50) NULL,
    specialization_id INT         NOT NULL,
    category          ENUM('highest', 'first', 'second', 'none') NOT NULL DEFAULT 'none',
    experience_years  TINYINT     NOT NULL DEFAULT 0,
    phone             VARCHAR(20) NOT NULL,
    db_login          VARCHAR(32) NULL,
    is_active         BOOLEAN     NOT NULL DEFAULT TRUE,
    CONSTRAINT pk_specialists PRIMARY KEY (specialist_id),
    CONSTRAINT uq_specialists_phone UNIQUE (phone),
    CONSTRAINT uq_specialists_login UNIQUE (db_login),
    CONSTRAINT chk_specialists_exp CHECK (experience_years BETWEEN 0 AND 60),
    CONSTRAINT chk_specialists_phone CHECK (phone REGEXP '^[+]380[0-9]{9}$'),
    CONSTRAINT fk_specialists_specialization FOREIGN KEY (specialization_id)
        REFERENCES specializations (specialization_id) ON DELETE RESTRICT ON UPDATE RESTRICT
) ENGINE = InnoDB;
-- 4. Кабінети (capacity - кількість паралельних індивідуальних сеансів різних фахівців)
CREATE TABLE rooms (
    room_id     INT         NOT NULL AUTO_INCREMENT,
    room_number VARCHAR(10) NOT NULL,
    room_type   ENUM('gym', 'massage', 'physio', 'pool', 'ergo', 'psych') NOT NULL,
    capacity    TINYINT     NOT NULL DEFAULT 1,
    CONSTRAINT pk_rooms PRIMARY KEY (room_id),
    CONSTRAINT uq_rooms_number UNIQUE (room_number),
    CONSTRAINT chk_rooms_capacity CHECK (capacity BETWEEN 1 AND 20)
) ENGINE = InnoDB;
-- 5. Довідник процедур (поточний прайс)
CREATE TABLE procedures (
    procedure_id      INT          NOT NULL AUTO_INCREMENT,
    name              VARCHAR(100) NOT NULL,
    duration_min      SMALLINT     NOT NULL,
    price             DECIMAL(8,2) NOT NULL,
    specialization_id INT          NOT NULL,
    room_type         ENUM('gym', 'massage', 'physio', 'pool', 'ergo', 'psych') NOT NULL,
    CONSTRAINT pk_procedures PRIMARY KEY (procedure_id),
    CONSTRAINT uq_procedures_name UNIQUE (name),
    CONSTRAINT chk_procedures_duration CHECK (duration_min > 0 AND duration_min <= 240),
    CONSTRAINT chk_procedures_price CHECK (price >= 0),
    CONSTRAINT fk_procedures_specialization FOREIGN KEY (specialization_id)
        REFERENCES specializations (specialization_id) ON DELETE RESTRICT ON UPDATE RESTRICT
) ENGINE = InnoDB;
-- 6. Курси лікування (одне звернення пацієнта)
CREATE TABLE treatment_courses (
    course_id  INT          NOT NULL AUTO_INCREMENT,
    client_id  INT          NOT NULL,
    curator_id INT          NOT NULL,
    start_date DATE         NOT NULL, end_date DATE NOT NULL,
    diagnosis  VARCHAR(255) NOT NULL,
    referral   VARCHAR(255) NULL,
    goal       VARCHAR(255) NOT NULL,
    status     ENUM('active', 'completed', 'cancelled') NOT NULL DEFAULT 'active',
    CONSTRAINT pk_treatment_courses PRIMARY KEY (course_id),
    CONSTRAINT chk_courses_dates CHECK (end_date >= start_date),
    CONSTRAINT fk_courses_client FOREIGN KEY (client_id) REFERENCES clients (client_id) ON DELETE RESTRICT ON UPDATE RESTRICT,
    CONSTRAINT fk_courses_curator FOREIGN KEY (curator_id)
        REFERENCES specialists (specialist_id) ON DELETE RESTRICT ON UPDATE RESTRICT
) ENGINE = InnoDB;
CREATE INDEX idx_courses_status_end ON treatment_courses (status, end_date);
-- 7. Склад курсу (M:N); unit_price - ціна, зафіксована на момент призначення
CREATE TABLE course_procedures (
    course_id        INT          NOT NULL,
    procedure_id     INT          NOT NULL,
    planned_sessions TINYINT      NOT NULL,
    unit_price       DECIMAL(8,2) NOT NULL,
    CONSTRAINT pk_course_procedures PRIMARY KEY (course_id, procedure_id),
    CONSTRAINT chk_cp_planned CHECK (planned_sessions BETWEEN 1 AND 50),
    CONSTRAINT chk_cp_price CHECK (unit_price >= 0),
    CONSTRAINT fk_cp_course FOREIGN KEY (course_id)
        REFERENCES treatment_courses (course_id) ON DELETE CASCADE ON UPDATE RESTRICT,
    CONSTRAINT fk_cp_procedure FOREIGN KEY (procedure_id)
        REFERENCES procedures (procedure_id) ON DELETE RESTRICT ON UPDATE RESTRICT
) ENGINE = InnoDB;
-- 8. Сеанси (розклад); price - вартість сеансу на момент запису
CREATE TABLE sessions (
    session_id    INT          NOT NULL AUTO_INCREMENT,
    course_id     INT          NOT NULL,
    procedure_id  INT          NOT NULL,
    specialist_id INT          NOT NULL,
    room_id       INT          NOT NULL,
    start_at      DATETIME     NOT NULL,
    price         DECIMAL(8,2) NOT NULL,
    status        ENUM('planned', 'done', 'missed', 'cancelled') NOT NULL DEFAULT 'planned',
    CONSTRAINT pk_sessions PRIMARY KEY (session_id),
    CONSTRAINT chk_sessions_price CHECK (price >= 0),
    -- сеанс можна призначити лише на процедуру, що входить до курсу
    CONSTRAINT fk_sessions_course_procedure FOREIGN KEY (course_id, procedure_id)
        REFERENCES course_procedures (course_id, procedure_id) ON DELETE RESTRICT ON UPDATE RESTRICT,
    CONSTRAINT fk_sessions_specialist FOREIGN KEY (specialist_id)
        REFERENCES specialists (specialist_id) ON DELETE RESTRICT ON UPDATE RESTRICT,
    CONSTRAINT fk_sessions_room FOREIGN KEY (room_id) REFERENCES rooms (room_id) ON DELETE RESTRICT ON UPDATE RESTRICT
) ENGINE = InnoDB;
CREATE INDEX idx_sessions_specialist_time ON sessions (specialist_id, start_at);
CREATE INDEX idx_sessions_room_time       ON sessions (room_id, start_at);
CREATE INDEX idx_sessions_start           ON sessions (start_at);
-- 9. Записи прогресу лікування
CREATE TABLE progress_records (
    record_id   INT      NOT NULL AUTO_INCREMENT,
    course_id   INT      NOT NULL,
    session_id  INT      NULL,
    recorded_on DATE     NOT NULL,
    pain_score  TINYINT  NOT NULL,
    rom_degrees SMALLINT NULL,
    wellbeing   ENUM('poor', 'fair', 'good', 'excellent') NULL,
    comment     TEXT     NULL,
    CONSTRAINT pk_progress_records PRIMARY KEY (record_id),
    CONSTRAINT uq_progress_session UNIQUE (session_id),
    CONSTRAINT chk_progress_pain CHECK (pain_score BETWEEN 0 AND 10),
    CONSTRAINT chk_progress_rom CHECK (rom_degrees BETWEEN 0 AND 360),
    CONSTRAINT fk_progress_course FOREIGN KEY (course_id)
        REFERENCES treatment_courses (course_id) ON DELETE RESTRICT ON UPDATE RESTRICT,
    CONSTRAINT fk_progress_session FOREIGN KEY (session_id)
        REFERENCES sessions (session_id) ON DELETE SET NULL ON UPDATE RESTRICT
) ENGINE = InnoDB;
CREATE INDEX idx_progress_course_date ON progress_records (course_id, recorded_on);
-- 10. Оплати за курси
CREATE TABLE payments (
    payment_id INT           NOT NULL AUTO_INCREMENT,
    course_id  INT           NOT NULL,
    amount     DECIMAL(10,2) NOT NULL,
    paid_at    DATETIME      NOT NULL DEFAULT CURRENT_TIMESTAMP,
    method     ENUM('cash', 'card', 'transfer') NOT NULL,
    CONSTRAINT pk_payments PRIMARY KEY (payment_id),
    CONSTRAINT chk_payments_amount CHECK (amount > 0),
    CONSTRAINT fk_payments_course FOREIGN KEY (course_id)
        REFERENCES treatment_courses (course_id) ON DELETE RESTRICT ON UPDATE RESTRICT
) ENGINE = InnoDB;
CREATE INDEX idx_payments_paid_at ON payments (paid_at);
DELIMITER $$
-- ЗБЕРЕЖЕНІ ПРОЦЕДУРИ. Перевірка бізнес-правил сеансу (викликається з тригерів)
CREATE PROCEDURE sp_validate_session(IN p_session_id INT, IN p_course_id INT, IN p_procedure_id INT,
                                     IN p_specialist_id INT, IN p_room_id INT, IN p_start_at DATETIME)
BEGIN
    DECLARE v_course_status, v_proc_room, v_room_type VARCHAR(20); DECLARE v_start_date, v_end_date DATE;
    DECLARE v_client, v_proc_spec, v_spec_spec, v_busy, v_planned INT;
    DECLARE v_duration SMALLINT; DECLARE v_capacity TINYINT; DECLARE v_spec_active BOOLEAN; DECLARE v_end_at DATETIME;
    -- 1) курс активний, сеанс у межах дат курсу
    SELECT client_id, status, start_date, end_date
      INTO v_client, v_course_status, v_start_date, v_end_date
      FROM treatment_courses WHERE course_id = p_course_id;
    IF v_course_status <> 'active' THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Курс не активний: запис сеансу неможливий';
    END IF;
    IF DATE(p_start_at) NOT BETWEEN v_start_date AND v_end_date THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Дата сеансу виходить за межі дат курсу';
    END IF;
    -- 2) блокування пацієнта, фахівця і кабінету до кінця транзакції:
    --    паралельний запис до тих самих об'єктів чекає, а не проходить повз перевірку
    SELECT client_id INTO v_client FROM clients WHERE client_id = v_client FOR UPDATE;
    SELECT specialization_id, is_active INTO v_spec_spec, v_spec_active
      FROM specialists WHERE specialist_id = p_specialist_id FOR UPDATE;
    SELECT room_type, capacity INTO v_room_type, v_capacity
      FROM rooms WHERE room_id = p_room_id FOR UPDATE;
    -- 3) відповідність фахівця і кабінету процедурі
    SELECT duration_min, specialization_id, room_type
      INTO v_duration, v_proc_spec, v_proc_room
      FROM procedures WHERE procedure_id = p_procedure_id;
    IF NOT v_spec_active THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Фахівець неактивний: призначення сеансу неможливе';
    END IF;
    IF v_spec_spec <> v_proc_spec THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Спеціалізація фахівця не відповідає процедурі';
    END IF;
    IF v_room_type <> v_proc_room THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Тип кабінету не відповідає процедурі';
    END IF;
    -- 4) план процедури: заплановані й проведені сеанси не перевищують planned_sessions
    SELECT planned_sessions INTO v_planned FROM course_procedures
     WHERE course_id = p_course_id AND procedure_id = p_procedure_id;
    SELECT COUNT(*) INTO v_busy FROM sessions
     WHERE course_id = p_course_id AND procedure_id = p_procedure_id
       AND status IN ('planned', 'done') AND session_id <> IFNULL(p_session_id, 0)
       FOR SHARE;
    IF v_busy >= v_planned THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Перевищено заплановану кількість сеансів процедури';
    END IF;
    -- 5) накладки: інтервали [початок; кінець) не перетинаються (межа 240 хв - для індексу)
    SET v_end_at = p_start_at + INTERVAL v_duration MINUTE;
    SELECT COUNT(*) INTO v_busy
      FROM sessions s JOIN procedures p ON p.procedure_id = s.procedure_id
     WHERE s.specialist_id = p_specialist_id
       AND s.session_id <> IFNULL(p_session_id, 0) AND s.status IN ('planned', 'done')
       AND s.start_at >= p_start_at - INTERVAL 240 MINUTE AND s.start_at < v_end_at
       AND s.start_at + INTERVAL p.duration_min MINUTE > p_start_at
       FOR SHARE;
    IF v_busy > 0 THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Накладка: фахівець уже має сеанс у цей час';
    END IF;
    -- кабінет: найбільша кількість одночасних сеансів; пік настає на початку нового або одного з наявних сеансів
    WITH ovl AS (SELECT s.session_id AS id, s.start_at AS b, s.start_at + INTERVAL p.duration_min MINUTE AS e
                   FROM sessions s JOIN procedures p ON p.procedure_id = s.procedure_id
                  WHERE s.room_id = p_room_id
                    AND s.session_id <> IFNULL(p_session_id, 0) AND s.status IN ('planned', 'done')
                    AND s.start_at >= p_start_at - INTERVAL 240 MINUTE AND s.start_at < v_end_at
                    AND s.start_at + INTERVAL p.duration_min MINUTE > p_start_at FOR SHARE)
    SELECT COALESCE(MAX(z.c), 0) INTO v_busy
      FROM (SELECT COUNT(*) AS c FROM ovl x JOIN ovl y ON y.b <= GREATEST(x.b, p_start_at) AND y.e > GREATEST(x.b, p_start_at)
             GROUP BY x.id) z;
    IF v_busy >= v_capacity THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Накладка: кабінет у цей час заповнений';
    END IF;
    SELECT COUNT(*) INTO v_busy
      FROM sessions s
      JOIN procedures p        ON p.procedure_id = s.procedure_id
      JOIN treatment_courses t ON t.course_id = s.course_id
     WHERE t.client_id = v_client
       AND s.session_id <> IFNULL(p_session_id, 0) AND s.status IN ('planned', 'done')
       AND s.start_at >= p_start_at - INTERVAL 240 MINUTE AND s.start_at < v_end_at
       AND s.start_at + INTERVAL p.duration_min MINUTE > p_start_at
       FOR SHARE;
    IF v_busy > 0 THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Накладка: пацієнт уже має сеанс у цей час';
    END IF;
END$$
-- Перевірка запису прогресу (для вставлення і зміни)
CREATE PROCEDURE sp_validate_progress(IN p_course_id INT, IN p_session_id INT, IN p_recorded_on DATE)
BEGIN
    DECLARE v_start, v_session_day DATE; DECLARE v_course INT; DECLARE v_status VARCHAR(20);
    SELECT start_date INTO v_start FROM treatment_courses WHERE course_id = p_course_id;
    IF p_recorded_on < v_start THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Дата запису прогресу раніша за початок курсу';
    END IF;
    IF p_session_id IS NOT NULL THEN
        SELECT course_id, status, DATE(start_at) INTO v_course, v_status, v_session_day
          FROM sessions WHERE session_id = p_session_id;
        IF v_course <> p_course_id THEN
            SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Сеанс не належить вказаному курсу';
        END IF;
        IF v_status <> 'done' THEN
            SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Прогрес фіксується лише для проведеного сеансу';
        END IF;
        IF p_recorded_on < v_session_day THEN
            SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Дата запису прогресу раніша за дату сеансу';
        END IF;
    END IF;
END$$
-- Автоматичне завершення курсу: план виконано за кожною процедурою
CREATE PROCEDURE sp_refresh_course_status(IN p_course_id INT)
BEGIN
    DECLARE v_unfinished INT;
    SELECT COUNT(*) INTO v_unfinished
      FROM course_procedures cp
     WHERE cp.course_id = p_course_id
       AND cp.planned_sessions > (SELECT COUNT(*) FROM sessions s
                                   WHERE s.course_id = cp.course_id
                                     AND s.procedure_id = cp.procedure_id
                                     AND s.status = 'done');
    IF v_unfinished = 0 THEN
        UPDATE treatment_courses SET status = 'completed'
         WHERE course_id = p_course_id AND status = 'active';
    END IF;
END$$
-- Розклад фахівця на дату (для адміністратора і керівника)
CREATE PROCEDURE sp_specialist_schedule(IN p_specialist_id INT, IN p_date DATE)
BEGIN
    SELECT TIME_FORMAT(s.start_at, '%H:%i') AS start_time,
           TIME_FORMAT(s.start_at + INTERVAL p.duration_min MINUTE, '%H:%i') AS end_time,
           p.name AS procedure_name, r.room_number AS room,
           CONCAT(c.last_name, ' ', c.first_name) AS client_name, s.status
      FROM sessions s
      JOIN procedures p        ON p.procedure_id = s.procedure_id
      JOIN rooms r             ON r.room_id      = s.room_id
      JOIN treatment_courses t ON t.course_id    = s.course_id
      JOIN clients c           ON c.client_id    = t.client_id
     WHERE s.specialist_id = p_specialist_id
       AND s.start_at >= p_date AND s.start_at < p_date + INTERVAL 1 DAY
       AND s.status <> 'cancelled'
     ORDER BY s.start_at;
END$$
-- Скасування курсу разом із запланованими сеансами (одна транзакція)
CREATE PROCEDURE sp_cancel_course(IN p_course_id INT)
BEGIN
    DECLARE v_status VARCHAR(20) DEFAULT NULL;
    DECLARE EXIT HANDLER FOR SQLEXCEPTION BEGIN ROLLBACK; RESIGNAL; END;
    START TRANSACTION;
    SELECT status INTO v_status FROM treatment_courses WHERE course_id = p_course_id FOR UPDATE;
    IF v_status IS NULL THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Курс не знайдено';
    END IF;
    IF v_status <> 'active' THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Скасувати можна лише активний курс';
    END IF;
    UPDATE sessions SET status = 'cancelled' WHERE course_id = p_course_id AND status = 'planned';
    UPDATE treatment_courses SET status = 'cancelled' WHERE course_id = p_course_id;
    COMMIT;
END$$
-- Фахівець позначає свій сеанс проведеним або пропущеним
CREATE PROCEDURE sp_set_session_status(IN p_session_id INT, IN p_status VARCHAR(10))
BEGIN
    IF p_status NOT IN ('done', 'missed') THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Фахівець може встановити лише статус done або missed';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM sessions s JOIN specialists sp ON sp.specialist_id = s.specialist_id
                    WHERE s.session_id = p_session_id
                      AND sp.db_login = SUBSTRING_INDEX(USER(), '@', 1)) THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Сеанс не належить поточному фахівцю';
    END IF;
    UPDATE sessions SET status = p_status WHERE session_id = p_session_id;
END$$
-- Фахівець додає запис прогресу: до свого сеансу або (як куратор) до курсу
CREATE PROCEDURE sp_add_progress(IN p_course_id INT, IN p_session_id INT, IN p_recorded_on DATE, IN p_pain TINYINT,
                                 IN p_rom SMALLINT, IN p_wellbeing VARCHAR(10), IN p_comment TEXT)
BEGIN
    DECLARE v_login VARCHAR(32) DEFAULT SUBSTRING_INDEX(USER(), '@', 1);
    IF p_session_id IS NOT NULL AND NOT EXISTS (
           SELECT 1 FROM sessions s JOIN specialists sp ON sp.specialist_id = s.specialist_id
            WHERE s.session_id = p_session_id AND sp.db_login = v_login) THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Сеанс не належить поточному фахівцю';
    END IF;
    IF p_session_id IS NULL AND NOT EXISTS (
           SELECT 1 FROM treatment_courses t JOIN specialists sp ON sp.specialist_id = t.curator_id
            WHERE t.course_id = p_course_id AND sp.db_login = v_login) THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Запис без сеансу вносить лише куратор курсу';
    END IF;
    INSERT INTO progress_records (course_id, session_id, recorded_on, pain_score, rom_degrees, wellbeing, comment)
    VALUES (p_course_id, p_session_id, p_recorded_on, p_pain, p_rom, p_wellbeing, p_comment);
END$$
-- ТРИГЕРИ. Склад курсу: фіксація ціни, лише для активного курсу
CREATE TRIGGER trg_cp_bi BEFORE INSERT ON course_procedures FOR EACH ROW
BEGIN
    IF (SELECT status FROM treatment_courses WHERE course_id = NEW.course_id) <> 'active' THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Змінювати склад можна лише в активному курсі';
    END IF;
    IF NEW.unit_price IS NULL THEN
        SET NEW.unit_price = (SELECT price FROM procedures WHERE procedure_id = NEW.procedure_id);
    END IF;
END$$
-- Склад курсу: план не можна зменшити нижче вже записаних сеансів
CREATE TRIGGER trg_cp_bu BEFORE UPDATE ON course_procedures FOR EACH ROW
BEGIN
    IF (SELECT status FROM treatment_courses WHERE course_id = NEW.course_id) <> 'active' THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Змінювати склад можна лише в активному курсі';
    END IF;
    IF NEW.planned_sessions < (SELECT COUNT(*) FROM sessions
                                WHERE course_id = OLD.course_id AND procedure_id = OLD.procedure_id
                                  AND status IN ('planned', 'done')) THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'План менший за кількість уже записаних сеансів';
    END IF;
END$$
-- Курс: заборона відновлення, завершення без виконаного плану, звуження дат
CREATE TRIGGER trg_courses_bu BEFORE UPDATE ON treatment_courses FOR EACH ROW
BEGIN
    IF OLD.status IN ('completed', 'cancelled') AND NEW.status <> OLD.status THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Завершений або скасований курс не можна відновити';
    END IF;
    IF NEW.status = 'completed' AND OLD.status = 'active' AND EXISTS (
           SELECT 1 FROM course_procedures cp
            WHERE cp.course_id = NEW.course_id
              AND cp.planned_sessions > (SELECT COUNT(*) FROM sessions s
                                          WHERE s.course_id = cp.course_id
                                            AND s.procedure_id = cp.procedure_id
                                            AND s.status = 'done')) THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Курс не можна завершити: план не виконано';
    END IF;
    IF EXISTS (SELECT 1 FROM sessions s WHERE s.course_id = NEW.course_id
                  AND s.status <> 'cancelled'
                  AND DATE(s.start_at) NOT BETWEEN NEW.start_date AND NEW.end_date) THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Нові дати курсу не охоплюють уже записані сеанси';
    END IF;
END$$
-- Сеанс: перевірка правил і фіксація ціни під час запису
CREATE TRIGGER trg_sessions_bi BEFORE INSERT ON sessions FOR EACH ROW
BEGIN
    IF NEW.status <> 'cancelled' THEN
        CALL sp_validate_session(NULL, NEW.course_id, NEW.procedure_id,
                                 NEW.specialist_id, NEW.room_id, NEW.start_at);
    END IF;
    IF NEW.price IS NULL THEN
        SET NEW.price = (SELECT unit_price FROM course_procedures
                          WHERE course_id = NEW.course_id AND procedure_id = NEW.procedure_id);
    END IF;
END$$
-- Сеанс: зміни лише в активному курсі; повторна перевірка при перенесенні
CREATE TRIGGER trg_sessions_bu BEFORE UPDATE ON sessions FOR EACH ROW
BEGIN
    IF (SELECT status FROM treatment_courses WHERE course_id = OLD.course_id) <> 'active' THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Курс завершено або скасовано: зміна сеансу неможлива';
    END IF;
    IF NEW.start_at <> OLD.start_at OR NEW.specialist_id <> OLD.specialist_id
       OR NEW.room_id <> OLD.room_id OR NEW.course_id <> OLD.course_id
       OR NEW.procedure_id <> OLD.procedure_id
       OR (OLD.status IN ('cancelled', 'missed') AND NEW.status IN ('planned', 'done')) THEN
        CALL sp_validate_session(OLD.session_id, NEW.course_id, NEW.procedure_id,
                                 NEW.specialist_id, NEW.room_id, NEW.start_at);
    END IF;
    IF NEW.procedure_id <> OLD.procedure_id OR NEW.course_id <> OLD.course_id THEN
        SET NEW.price = (SELECT unit_price FROM course_procedures
                          WHERE course_id = NEW.course_id AND procedure_id = NEW.procedure_id);
    END IF;
END$$
-- Автоматичне завершення курсу після вставлення або позначення проведеного сеансу
CREATE TRIGGER trg_sessions_ai AFTER INSERT ON sessions FOR EACH ROW
BEGIN
    IF NEW.status = 'done' THEN
        CALL sp_refresh_course_status(NEW.course_id);
    END IF;
END$$
CREATE TRIGGER trg_sessions_au AFTER UPDATE ON sessions FOR EACH ROW
BEGIN
    IF NEW.status = 'done' AND OLD.status <> 'done' THEN
        CALL sp_refresh_course_status(NEW.course_id);
    END IF;
END$$
-- Запис прогресу: однакові перевірки під час вставлення і зміни
CREATE TRIGGER trg_progress_bi BEFORE INSERT ON progress_records FOR EACH ROW
BEGIN
    CALL sp_validate_progress(NEW.course_id, NEW.session_id, NEW.recorded_on);
END$$
CREATE TRIGGER trg_progress_bu BEFORE UPDATE ON progress_records FOR EACH ROW
BEGIN
    CALL sp_validate_progress(NEW.course_id, NEW.session_id, NEW.recorded_on);
END$$
DELIMITER ;
-- ПРЕДСТАВЛЕННЯ. Відсоток проходження курсів
CREATE VIEW v_course_completion AS
SELECT tc.course_id, CONCAT(c.last_name, ' ', c.first_name) AS client_name,
       tc.start_date, tc.end_date, tc.status, pl.planned_total,
       COALESCE(st.done_cnt, 0) AS done_cnt, COALESCE(st.missed_cnt, 0) AS missed_cnt,
       ROUND(COALESCE(st.done_cnt, 0) * 100 / pl.planned_total, 1) AS completion_pct
  FROM treatment_courses tc
  JOIN clients c ON c.client_id = tc.client_id
  JOIN (SELECT course_id, SUM(planned_sessions) AS planned_total
          FROM course_procedures GROUP BY course_id) pl ON pl.course_id = tc.course_id
  LEFT JOIN (SELECT course_id, SUM(status = 'done') AS done_cnt,
                    SUM(status = 'missed') AS missed_cnt
               FROM sessions GROUP BY course_id) st ON st.course_id = tc.course_id;
-- Загальний звіт по пацієнту: один рядок на курс; борг скасованого курсу - за проведеними сеансами
CREATE VIEW v_client_report AS
SELECT c.client_id,
       CONCAT_WS(' ', c.last_name, c.first_name, c.middle_name) AS client_name,
       c.birth_date, tc.course_id, tc.diagnosis, tc.goal,
       CONCAT(sp.last_name, ' ', LEFT(sp.first_name, 1), '.') AS curator,
       tc.start_date, tc.end_date, tc.status,
       (SELECT GROUP_CONCAT(p.name ORDER BY p.name SEPARATOR ', ') FROM course_procedures cp
          JOIN procedures p ON p.procedure_id = cp.procedure_id
         WHERE cp.course_id = tc.course_id) AS procedures_list,
       cc.planned_total, cc.done_cnt, cc.completion_pct,
       (SELECT pr.pain_score FROM progress_records pr WHERE pr.course_id = tc.course_id
         ORDER BY pr.recorded_on, pr.record_id LIMIT 1) AS pain_first,
       (SELECT pr.pain_score FROM progress_records pr WHERE pr.course_id = tc.course_id
         ORDER BY pr.recorded_on DESC, pr.record_id DESC LIMIT 1) AS pain_last,
       f.planned_cost, f.delivered_cost, f.paid,
       CASE WHEN tc.status = 'cancelled' THEN f.delivered_cost ELSE f.planned_cost END
         - f.paid AS debt
  FROM clients c
  JOIN treatment_courses tc   ON tc.client_id     = c.client_id
  JOIN specialists sp         ON sp.specialist_id = tc.curator_id
  JOIN v_course_completion cc ON cc.course_id     = tc.course_id
  JOIN (SELECT t.course_id,
               (SELECT SUM(cp.planned_sessions * cp.unit_price) FROM course_procedures cp
                 WHERE cp.course_id = t.course_id) AS planned_cost,
               (SELECT COALESCE(SUM(s.price), 0) FROM sessions s
                 WHERE s.course_id = t.course_id AND s.status = 'done') AS delivered_cost,
               (SELECT COALESCE(SUM(pm.amount), 0) FROM payments pm
                 WHERE pm.course_id = t.course_id) AS paid
          FROM treatment_courses t) f ON f.course_id = tc.course_id;
-- Сеанси поточного фахівця (визначається за обліковим записом підключення)
CREATE VIEW v_my_sessions AS
SELECT s.session_id, s.start_at, s.start_at + INTERVAL p.duration_min MINUTE AS end_at,
       p.name AS procedure_name, r.room_number, s.course_id,
       CONCAT(c.last_name, ' ', c.first_name) AS client_name, s.status
  FROM sessions s
  JOIN specialists sp      ON sp.specialist_id = s.specialist_id
  JOIN procedures p        ON p.procedure_id   = s.procedure_id
  JOIN rooms r             ON r.room_id        = s.room_id
  JOIN treatment_courses t ON t.course_id      = s.course_id
  JOIN clients c           ON c.client_id      = t.client_id
 WHERE sp.db_login = SUBSTRING_INDEX(USER(), '@', 1);
-- Прогрес пацієнтів, з якими працює поточний фахівець (куратор або виконавець сеансів)
CREATE VIEW v_my_progress AS
SELECT pr.record_id, pr.course_id, CONCAT(c.last_name, ' ', c.first_name) AS client_name,
       t.diagnosis, pr.recorded_on, pr.pain_score, pr.rom_degrees, pr.wellbeing, pr.comment
  FROM progress_records pr
  JOIN treatment_courses t ON t.course_id = pr.course_id
  JOIN clients c           ON c.client_id = t.client_id
 WHERE t.course_id IN (SELECT t2.course_id FROM treatment_courses t2
                         JOIN specialists sp ON sp.specialist_id = t2.curator_id
                        WHERE sp.db_login = SUBSTRING_INDEX(USER(), '@', 1)
                       UNION
                       SELECT s.course_id FROM sessions s
                         JOIN specialists sp ON sp.specialist_id = s.specialist_id
                        WHERE sp.db_login = SUBSTRING_INDEX(USER(), '@', 1));
-- РОЛІ ТА КОРИСТУВАЧІ
DROP USER IF EXISTS 'registrar'@'localhost', 'melnyk'@'localhost', 'director'@'localhost', 'rehab_app'@'localhost';
DROP ROLE IF EXISTS 'role_admin', 'role_specialist', 'role_manager'; CREATE ROLE 'role_admin', 'role_specialist', 'role_manager';
-- Адміністратор (реєстратор): пацієнти, курси, розклад, оплати; без медичних записів прогресу
GRANT SELECT, INSERT, UPDATE, DELETE ON rehab_center.clients           TO 'role_admin';
GRANT SELECT, INSERT, UPDATE         ON rehab_center.treatment_courses TO 'role_admin';
GRANT SELECT, INSERT, UPDATE, DELETE ON rehab_center.course_procedures TO 'role_admin';
GRANT SELECT, INSERT, UPDATE         ON rehab_center.sessions          TO 'role_admin';
GRANT SELECT, INSERT                 ON rehab_center.payments          TO 'role_admin';
GRANT SELECT ON rehab_center.specializations TO 'role_admin'; GRANT SELECT ON rehab_center.specialists TO 'role_admin';
GRANT SELECT ON rehab_center.procedures TO 'role_admin';      GRANT SELECT ON rehab_center.rooms TO 'role_admin';
GRANT SELECT ON rehab_center.v_course_completion TO 'role_admin';
GRANT EXECUTE ON PROCEDURE rehab_center.sp_cancel_course TO 'role_admin';
GRANT EXECUTE ON PROCEDURE rehab_center.sp_specialist_schedule TO 'role_admin';
-- Фахівець: лише власні сеанси і прогрес своїх пацієнтів, зміни - через процедури
GRANT SELECT ON rehab_center.v_my_sessions TO 'role_specialist'; GRANT SELECT ON rehab_center.v_my_progress TO 'role_specialist';
GRANT SELECT ON rehab_center.procedures TO 'role_specialist';    GRANT SELECT ON rehab_center.rooms TO 'role_specialist';
GRANT EXECUTE ON PROCEDURE rehab_center.sp_set_session_status TO 'role_specialist';
GRANT EXECUTE ON PROCEDURE rehab_center.sp_add_progress       TO 'role_specialist';
-- Керівник: перегляд усіх даних і звітів, ведення довідників і персоналу
GRANT SELECT ON rehab_center.* TO 'role_manager';
GRANT INSERT, UPDATE, DELETE ON rehab_center.specializations TO 'role_manager';
GRANT INSERT, UPDATE, DELETE ON rehab_center.specialists     TO 'role_manager';
GRANT INSERT, UPDATE, DELETE ON rehab_center.procedures      TO 'role_manager';
GRANT INSERT, UPDATE, DELETE ON rehab_center.rooms           TO 'role_manager';
GRANT EXECUTE ON PROCEDURE rehab_center.sp_cancel_course       TO 'role_manager';
GRANT EXECUTE ON PROCEDURE rehab_center.sp_specialist_schedule TO 'role_manager';
-- Облікові записи (паролі навчальні, у робочій системі замінити); melnyk - фахівець Мельник Т. І.
CREATE USER 'registrar'@'localhost' IDENTIFIED BY 'Reg#2026pass', 'melnyk'@'localhost' IDENTIFIED BY 'Mel#2026pass',
            'director'@'localhost' IDENTIFIED BY 'Dir#2026pass', 'rehab_app'@'localhost' IDENTIFIED BY 'App#2026pass';
GRANT 'role_admin' TO 'registrar'@'localhost'; GRANT 'role_specialist' TO 'melnyk'@'localhost';
GRANT 'role_manager' TO 'director'@'localhost'; GRANT 'role_admin' TO 'rehab_app'@'localhost'; -- вебзастосунок реєстратури
SET DEFAULT ROLE ALL TO 'registrar'@'localhost', 'melnyk'@'localhost', 'director'@'localhost', 'rehab_app'@'localhost';

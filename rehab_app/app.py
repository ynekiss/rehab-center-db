"""Демонстраційний вебінтерфейс БД реабілітаційного центру (python app.py -> http://127.0.0.1:5000)."""
import datetime as dt

import mysql.connector
from flask import Flask, flash, redirect, render_template, request, url_for

import config
import db

app = Flask(__name__)
app.secret_key = config.SECRET_KEY
app.teardown_appcontext(db.close_db)

STATUS_UA = {'planned': 'заплановано', 'done': 'проведено', 'missed': 'пропущено',
             'cancelled': 'скасовано', 'active': 'активний', 'completed': 'завершений',
             'poor': 'погане', 'fair': 'задовільне', 'good': 'добре', 'excellent': 'відмінне'}


@app.template_filter('ua')
def ua_status(value):
    return STATUS_UA.get(value, value or '')


def parse_date(value, default):
    try:
        return dt.date.fromisoformat(value)
    except (TypeError, ValueError):
        return default


@app.route('/')
def index():  # головна сторінка - список пацієнтів
    return redirect(url_for('clients'))


# ---------- Пацієнти ----------
@app.route('/clients')
def clients():
    search = request.args.get('q', '').strip()
    sql = """
        SELECT c.client_id, c.last_name, c.first_name, c.middle_name,
               c.birth_date, c.phone,
               GROUP_CONCAT(tc.course_id ORDER BY tc.course_id) AS courses
          FROM clients c
          LEFT JOIN treatment_courses tc ON tc.client_id = c.client_id
    """
    params = ()
    if search:
        # шаблон LIKE формується в Python, у SQL потрапляє лише параметр
        sql += " WHERE c.last_name LIKE %s OR c.phone LIKE %s"
        params = (search + '%', '%' + search + '%')
    sql += """ GROUP BY c.client_id, c.last_name, c.first_name, c.middle_name,
                        c.birth_date, c.phone
               ORDER BY c.last_name, c.first_name"""
    rows = db.query(sql, params)
    for r in rows:
        courses = r['courses']
        if isinstance(courses, (bytes, bytearray)):     # GROUP_CONCAT може повернути байти
            courses = courses.decode()
        r['course_ids'] = [int(x) for x in courses.split(',')] if courses else []
    return render_template('clients.html', clients=rows, q=search)


@app.route('/clients/new', methods=['GET', 'POST'])
def client_new():
    form = request.form
    if request.method == 'POST':
        required = ['last_name', 'first_name', 'birth_date', 'gender', 'phone']
        if any(not form.get(f, '').strip() for f in required):
            flash('Заповніть усі обов\'язкові поля', 'error')
            return render_template('client_form.html', form=form)
        try:
            new_id = db.execute(
                """INSERT INTO clients (last_name, first_name, middle_name, birth_date,
                                        gender, phone, email)
                   VALUES (%s, %s, %s, %s, %s, %s, %s)""",
                (form['last_name'].strip(), form['first_name'].strip(),
                 form.get('middle_name', '').strip() or None, form['birth_date'],
                 form['gender'], form['phone'].strip(), form.get('email', '').strip() or None))
        except mysql.connector.Error as err:
            flash(db.error_text(err), 'error')
            return render_template('client_form.html', form=form)
        flash(f'Пацієнта зареєстровано (код {new_id})', 'ok')
        return redirect(url_for('clients', q=form['last_name'].strip()))
    return render_template('client_form.html', form={})


# ---------- Розклад ----------
SCHEDULE_SQL = """
    SELECT s.session_id, s.start_at, s.status, s.course_id,
           p.name AS procedure_name, p.duration_min,
           r.room_number,
           sp.last_name AS sp_last, sp.first_name AS sp_first,
           c.last_name AS cl_last, c.first_name AS cl_first
      FROM sessions s
      JOIN procedures p        ON p.procedure_id  = s.procedure_id
      JOIN rooms r             ON r.room_id       = s.room_id
      JOIN specialists sp      ON sp.specialist_id = s.specialist_id
      JOIN treatment_courses t ON t.course_id     = s.course_id
      JOIN clients c           ON c.client_id     = t.client_id
     WHERE s.start_at >= %s AND s.start_at < %s
"""


@app.route('/schedule')
def schedule():
    day = parse_date(request.args.get('date'), dt.date.today())
    specialist_id = request.args.get('specialist', type=int)
    # діапазон [день; наступний день) замість DATE(start_at) = день, щоб працював індекс
    sql, params = SCHEDULE_SQL, [day, day + dt.timedelta(days=1)]
    if specialist_id:
        sql += ' AND s.specialist_id = %s'
        params.append(specialist_id)
    sql += ' ORDER BY s.start_at, r.room_number'
    rows = db.query(sql, tuple(params))
    for r in rows:
        r['end_at'] = r['start_at'] + dt.timedelta(minutes=r['duration_min'])
    specialists = db.query('SELECT specialist_id, last_name, first_name FROM specialists '
                           'WHERE is_active = TRUE ORDER BY last_name')
    return render_template('schedule.html', sessions=rows, day=day,
                           specialists=specialists, specialist_id=specialist_id)


@app.route('/sessions/new', methods=['GET', 'POST'])
def session_new():
    options = {
        'course_procs': db.query("""
            SELECT cp.course_id, cp.procedure_id, p.name AS procedure_name,
                   c.last_name, c.first_name
              FROM course_procedures cp
              JOIN treatment_courses t ON t.course_id    = cp.course_id
              JOIN clients c           ON c.client_id    = t.client_id
              JOIN procedures p        ON p.procedure_id = cp.procedure_id
             WHERE t.status = 'active'
             ORDER BY c.last_name, cp.course_id, p.name"""),
        'specialists': db.query("""
            SELECT sp.specialist_id, sp.last_name, sp.first_name, z.name AS spec
              FROM specialists sp
              JOIN specializations z ON z.specialization_id = sp.specialization_id
             WHERE sp.is_active = TRUE ORDER BY sp.last_name"""),
        'rooms': db.query('SELECT room_id, room_number, room_type FROM rooms ORDER BY room_number'),
    }
    form = request.form
    if request.method == 'POST':
        try:
            course_id, procedure_id = (int(x) for x in form['course_proc'].split(':'))
            start_at = dt.datetime.fromisoformat(f"{form['date']} {form['time']}")
            new_id = db.execute(
                """INSERT INTO sessions (course_id, procedure_id, specialist_id, room_id, start_at)
                   VALUES (%s, %s, %s, %s, %s)""",
                (course_id, procedure_id, int(form['specialist_id']),
                 int(form['room_id']), start_at))
        except (KeyError, ValueError):
            flash('Перевірте правильність заповнення форми', 'error')
            return render_template('session_form.html', form=form, **options)
        except mysql.connector.Error as err:
            # тут користувач бачить повідомлення тригера про накладку
            flash(db.error_text(err), 'error')
            return render_template('session_form.html', form=form, **options)
        flash(f'Сеанс № {new_id} записано', 'ok')
        return redirect(url_for('schedule', date=start_at.date().isoformat()))
    return render_template('session_form.html', form={}, **options)


@app.route('/sessions/<int:session_id>/status', methods=['POST'])
def session_status(session_id):
    status = request.form.get('status')
    if status not in ('done', 'missed', 'cancelled'):
        flash('Недопустимий статус', 'error')
    else:
        try:
            db.execute('UPDATE sessions SET status = %s WHERE session_id = %s',
                       (status, session_id))
            flash('Статус сеансу змінено', 'ok')
        except mysql.connector.Error as err:
            flash(db.error_text(err), 'error')
    return redirect(request.referrer or url_for('schedule'))


# ---------- Картка курсу ----------
@app.route('/courses/<int:course_id>')
def course(course_id):
    info = db.query_one("""
        SELECT t.course_id, t.start_date, t.end_date, t.goal, t.status, t.diagnosis,
               c.client_id, c.last_name, c.first_name, c.middle_name,
               sp.last_name AS cur_last, sp.first_name AS cur_first,
               v.planned_total, v.done_cnt, v.missed_cnt, v.completion_pct
          FROM treatment_courses t
          JOIN clients c              ON c.client_id      = t.client_id
          JOIN specialists sp         ON sp.specialist_id = t.curator_id
          JOIN v_course_completion v  ON v.course_id      = t.course_id
         WHERE t.course_id = %s""", (course_id,))
    if info is None:
        flash('Курс не знайдено', 'error')
        return redirect(url_for('clients'))
    procs = db.query("""
        SELECT p.name, cp.planned_sessions,
               SUM(CASE WHEN s.status = 'done'   THEN 1 ELSE 0 END) AS done_cnt,
               SUM(CASE WHEN s.status = 'missed' THEN 1 ELSE 0 END) AS missed_cnt
          FROM course_procedures cp
          JOIN procedures p    ON p.procedure_id = cp.procedure_id
          LEFT JOIN sessions s ON s.course_id = cp.course_id
                              AND s.procedure_id = cp.procedure_id
         WHERE cp.course_id = %s
         GROUP BY p.name, cp.planned_sessions
         ORDER BY p.name""", (course_id,))
    try:
        # медичні записи доступні лише обліковим записам із правом читання progress_records
        progress = db.query('SELECT recorded_on, pain_score, rom_degrees, wellbeing, comment '
                            'FROM progress_records WHERE course_id = %s ORDER BY recorded_on, record_id',
                            (course_id,))
    except mysql.connector.Error as err:
        if err.errno not in db.NO_PRIVILEGE:
            raise
        progress = None
    return render_template('course.html', c=info, procs=procs, progress=progress)


# ---------- Звіт про завантаження фахівців ----------
@app.route('/reports/load')
def load_report():
    today = dt.date.today()
    start = parse_date(request.args.get('start'), today - dt.timedelta(days=today.weekday()))
    end = parse_date(request.args.get('end'), start + dt.timedelta(days=6))
    rows = db.query("""
        SELECT sp.last_name, sp.first_name, z.name AS specialization,
               COUNT(s.session_id) AS sessions_cnt,
               ROUND(COALESCE(SUM(p.duration_min), 0) / 60.0, 1) AS hours,
               RANK() OVER (ORDER BY COALESCE(SUM(p.duration_min), 0) DESC) AS load_rank
          FROM specialists sp
          JOIN specializations z ON z.specialization_id = sp.specialization_id
          LEFT JOIN sessions s   ON s.specialist_id = sp.specialist_id AND s.status <> 'cancelled'
                                AND s.start_at >= %s AND s.start_at < %s
          LEFT JOIN procedures p ON p.procedure_id = s.procedure_id
         WHERE sp.is_active = TRUE
         GROUP BY sp.specialist_id, sp.last_name, sp.first_name, z.name
         ORDER BY load_rank, sp.last_name""", (start, end + dt.timedelta(days=1)))
    max_hours = max([float(r['hours']) for r in rows] + [1])
    return render_template('load_report.html', rows=rows, start=start, end=end, max_hours=max_hours)


if __name__ == '__main__':
    app.run(debug=config.DEBUG)

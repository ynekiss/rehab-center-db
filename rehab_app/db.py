"""Робота з базою даних: одне підключення на запит, лише параметризовані запити."""
import mysql.connector
from flask import g

from config import DB_CONFIG

# Помилка, яку генерує SIGNAL у тригерах і процедурах
TRIGGER_ERROR = 1644
DUPLICATE_KEY = 1062
CHECK_VIOLATION = 3819
NO_PRIVILEGE = (1142, 1143, 1370)


def get_db():
    if 'db' not in g:
        g.db = mysql.connector.connect(**DB_CONFIG)
    return g.db


def close_db(exc=None):
    db = g.pop('db', None)
    if db is not None:
        db.close()


def query(sql, params=()):
    """SELECT: повертає список словників. Значення передаються окремо від SQL."""
    cur = get_db().cursor(dictionary=True)
    try:
        cur.execute(sql, params)
        return cur.fetchall()
    finally:
        cur.close()


def query_one(sql, params=()):
    rows = query(sql, params)
    return rows[0] if rows else None


def execute(sql, params=()):
    db = get_db()
    cur = db.cursor()
    try:
        cur.execute(sql, params)
        db.commit()
        return cur.lastrowid
    except mysql.connector.Error:
        db.rollback()
        raise
    finally:
        cur.close()


def error_text(err):
    """Перетворює помилку СКБД на повідомлення для користувача."""
    if err.errno == TRIGGER_ERROR:
        return err.msg                      # текст із SIGNAL ... MESSAGE_TEXT
    if err.errno == DUPLICATE_KEY:
        return 'Пацієнта з таким ПІБ і датою народження або email уже зареєстровано'
    if err.errno in NO_PRIVILEGE:
        return 'Недостатньо прав облікового запису для цієї дії'
    if err.errno == CHECK_VIOLATION:
        return 'Дані не відповідають обмеженням бази (перевірте формат полів)'
    return f'Помилка бази даних ({err.errno})'

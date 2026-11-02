"""Параметри підключення до БД; значення можна перевизначити змінними середовища."""
import os

# обліковий запис визначає робоче місце: rehab_app - реєстратура (роль адміністратора),
# director - керівник (бачить записи прогресу); див. README
DB_CONFIG = {
    'host': os.environ.get('DB_HOST', 'localhost'),
    'port': int(os.environ.get('DB_PORT', '3306')),
    'user': os.environ.get('DB_USER', 'rehab_app'),
    'password': os.environ.get('DB_PASSWORD', 'App#2026pass'),
    'database': os.environ.get('DB_NAME', 'rehab_center'),
    'charset': 'utf8mb4', 'collation': 'utf8mb4_unicode_ci',
}

# ключ сесії і режим налагодження задаються змінними середовища;
# без SECRET_KEY генерується випадковий ключ, налагодження за замовчуванням вимкнено
SECRET_KEY = os.environ.get('SECRET_KEY') or os.urandom(32)
DEBUG = os.environ.get('FLASK_DEBUG') == '1'

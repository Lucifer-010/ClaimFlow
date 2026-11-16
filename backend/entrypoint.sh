#!/bin/sh
set -e

echo "Waiting for PostgreSQL if DB_HOST is set..."
if [ -n "$DB_HOST" ]; then
    while ! nc -z "$DB_HOST" "$DB_PORT"; do
        echo "Waiting for postgres at $DB_HOST:$DB_PORT..."
        sleep 1
    done
    echo "PostgreSQL started"
fi

echo "Applying database migrations..."
python manage.py migrate --noinput

echo "Collecting static files..."
python manage.py collectstatic --noinput --clear || true

exec "$@"


FROM python:3.12-slim

# Don't buffer logs (Cloud Logging shows them immediately) and don't write .pyc files
ENV PYTHONUNBUFFERED=1 PYTHONDONTWRITEBYTECODE=1

WORKDIR /app
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt
COPY main.py .

# Run as a non-root user
RUN useradd --create-home appuser
USER appuser

ENTRYPOINT ["python", "main.py"]

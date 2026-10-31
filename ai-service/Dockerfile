# syntax=docker/dockerfile:1
FROM python:3.12-slim AS base
ENV PYTHONDONTWRITEBYTECODE=1 PYTHONUNBUFFERED=1 PIP_NO_CACHE_DIR=1
WORKDIR /app

# Tesseract (tiếng Việt) để đọc ảnh hóa đơn khi không có mô hình thị giác
RUN apt-get update && apt-get install -y --no-install-recommends tesseract-ocr tesseract-ocr-vie \
    && rm -rf /var/lib/apt/lists/*
COPY requirements.txt .
RUN pip install -r requirements.txt "uvicorn[standard]"

COPY app ./app
COPY ml ./ml
# Huấn luyện lại trong image để mô hình khớp đúng phiên bản thư viện
RUN python -m ml.train && useradd -m svc && chown -R svc /app
USER svc
EXPOSE 8000
HEALTHCHECK --interval=30s --timeout=3s CMD python -c "import urllib.request;urllib.request.urlopen('http://localhost:8000/health')"
CMD ["uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "8000", "--workers", "2"]

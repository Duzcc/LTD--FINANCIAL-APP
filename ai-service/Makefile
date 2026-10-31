PY ?= .venv/bin/python
.PHONY: setup data train eval dev test lint

setup:            ## Tạo môi trường ảo và cài thư viện
	python3 -m venv .venv && $(PY) -m pip install -r requirements-dev.txt
data:             ## Sinh lại bộ dữ liệu huấn luyện
	$(PY) -m ml.data.generate_dataset
train:            ## Huấn luyện + đánh giá, ghi artifacts/
	$(PY) -m ml.train
eval:             ## Kiểm định lùi bộ dự báo
	$(PY) -m ml.evaluate_forecaster
dev:              ## Chạy dịch vụ ở cổng 8000 (tự nạp lại khi sửa code)
	$(PY) -m uvicorn app.main:app --reload --port 8000
test:
	$(PY) -m pytest
lint:
	$(PY) -m ruff check app ml tests

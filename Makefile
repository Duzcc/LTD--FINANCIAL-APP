# Lệnh tắt cho cả 3 phần. Chạy `make help` để xem danh sách.
PHONY_EXTRA = build-app
.PHONY: help setup dev-backend dev-ai dev-app test test-app test-backend test-ai train up down

help:
	@grep -E '^[a-z-]+:.*?## ' $(MAKEFILE_LIST) | awk -F':.*?## ' '{printf "  %-14s %s\n", $$1, $$2}'

setup: ## Cài đặt phụ thuộc cho frontend, backend, ai-service
	cd frontend && flutter pub get
	cd backend && npm install
	cd ai-service && make setup train

dev-ai: ## Chạy AI service ở cổng 8000
	cd ai-service && make dev
dev-backend: ## Chạy backend ở cổng 3000 (MongoDB theo MONGODB_URI trong backend/.env)
	cd backend && npm run dev
dev-app: ## Chạy ứng dụng Flutter
	cd frontend && flutter run

test: test-ai test-backend test-app ## Chạy toàn bộ kiểm thử
test-app:
	cd frontend && flutter analyze && flutter test
test-backend:
	cd backend && npm test
test-ai:
	cd ai-service && make lint test

build-app: ## Build bản phát hành Android (APK theo kiến trúc) và Web
	cd frontend && flutter build apk --release --split-per-abi && flutter build web --release --no-web-resources-cdn

train: ## Huấn luyện lại mô hình AI
	cd ai-service && make data train eval

up: ## Chạy phía máy chủ bằng Docker
	docker compose up -d --build
down:
	docker compose down

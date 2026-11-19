# Đóng góp

- Tạo nhánh từ `main`, đặt tên theo việc làm, ví dụ `feature/ngan-sach-tuan`, `fix/so-du-chuyen-vi`.
- Mỗi commit một thay đổi, tiêu đề ngắn bằng tiếng Việt.
- Trước khi tạo PR, chạy định dạng và test:

```bash
cd frontend && dart format lib test integration_test && flutter analyze && flutter test
cd backend && npm run format && npm test
cd ai-service && .venv/bin/python -m ruff format app ml tests && .venv/bin/python -m pytest
```

- Không commit `.env`, khóa API hay dữ liệu thật.

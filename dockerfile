# Builder stage
FROM python:3.11-slim as builder
WORKDIR /install
COPY main/requirements.txt .
RUN pip install --prefix=/install -r requirements.txt

# Final stage
FROM python:3.11-slim
WORKDIR /app
COPY --from=builder /install /usr/local
COPY main/app.py .
RUN mkdir -p /app/data

CMD ["uvicorn", "app:app", "--host", "0.0.0.0", "--port", "3030"]
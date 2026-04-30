FROM python:3.11-slim

WORKDIR /app

# copy from main folder
COPY main/requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY main/app.py .

# create data dir
RUN mkdir -p /app/data

EXPOSE 3030

CMD ["uvicorn", "app:app", "--host", "0.0.0.0", "--port", "3030"]
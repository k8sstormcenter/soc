# Use a slim Python image
FROM python:3.11-slim

# Set env vars
ENV PYTHONDONTWRITEBYTECODE=1
ENV PYTHONUNBUFFERED=1

# Set work dir
WORKDIR /app

# Install system dependencies
RUN apt-get update && apt-get install -y curl build-essential && rm -rf /var/lib/apt/lists/*

# Install poetry
RUN curl -sSL https://install.python-poetry.org | python3 - && \
    ln -s /root/.local/bin/poetry /usr/local/bin/poetry

# Copy project files
COPY pyproject.toml poetry.lock ./
COPY src ./src
COPY main.py .

# Install Python deps (no venv)
RUN poetry config virtualenvs.create false && poetry install --no-interaction --no-ansi

# Expose port
EXPOSE 5000

# Start the app
CMD ["python", "main.py"]

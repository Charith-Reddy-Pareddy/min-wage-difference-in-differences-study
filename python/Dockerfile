# Self-contained image for minwage's test suite -- it does NOT try to
# run train.py or causal_estimate.py, since both need
# data/processed/ml_panel.csv from the R pipeline (outside this build
# context and gitignored), which a container has no way to produce on
# its own. Building and testing the package is the useful thing a
# from-scratch environment can verify without that data.
FROM python:3.11-slim

WORKDIR /app

COPY pyproject.toml ./
COPY src ./src
COPY tests ./tests

RUN pip install --no-cache-dir -e ".[dev]"

CMD ["python", "-m", "pytest"]

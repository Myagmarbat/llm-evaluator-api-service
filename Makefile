.PHONY: help install test test-live docker-build docker-run tf-init tf-plan tf-apply tf-destroy

help:
	@echo "Targets:"
	@echo "  install      Install Python dependencies"
	@echo "  test         Run unit and mocked integration tests"
	@echo "  test-live    Run live integration tests (requires INTEGRATION_APP_URL)"
	@echo "  docker-build Build production container"
	@echo "  docker-run   Run container locally on :8000"
	@echo "  tf-init      Initialize Terraform (ENVIRONMENT=dev|production)"
	@echo "  tf-plan      Plan infrastructure changes"
	@echo "  tf-apply     Apply infrastructure (loads .env if present)"
	@echo "  tf-destroy   Destroy infrastructure"

install:
	pip install -r requirements.txt

test:
	pytest tests/ -m "not live" -v --cov=app

test-live:
	pytest tests/integration/test_live_api.py -m live -v

docker-build:
	docker build -t llm-evaluator-api-service:local .

docker-run:
	docker run --rm -p 8000:8000 \
		-e INFERENCE_API_KEY=$${INFERENCE_API_KEY} \
		llm-evaluator-api-service:local

tf-init:
	cd terraform && terraform init -input=false

tf-plan:
	./scripts/tf.sh plan

tf-apply:
	./scripts/tf.sh apply

tf-destroy:
	./scripts/tf.sh destroy

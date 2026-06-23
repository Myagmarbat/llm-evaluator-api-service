.PHONY: help install test docker-build docker-run tf-init tf-plan tf-apply tf-destroy

help:
	@echo "Targets:"
	@echo "  install      Install Python dependencies"
	@echo "  test         Run test suite"
	@echo "  docker-build Build production container"
	@echo "  docker-run   Run container locally on :8000"
	@echo "  tf-init      Initialize Terraform (local backend)"
	@echo "  tf-plan      Plan infrastructure changes"
	@echo "  tf-apply     Apply infrastructure (loads .env if present)"
	@echo "  tf-destroy   Destroy infrastructure"

install:
	pip install -r requirements.txt

test:
	pytest tests/ -v --cov=app

docker-build:
	docker build -t llm-evaluator-api-service:local .

docker-run:
	docker run --rm -p 8000:8000 \
		-e INFERENCE_API_KEY=$${INFERENCE_API_KEY} \
		llm-evaluator-api-service:local

tf-init:
	cd terraform && terraform init -input=false

tf-plan:
	./scripts/tf.sh plan -var="image_tag=$${IMAGE_TAG:-latest}"

tf-apply:
	./scripts/tf.sh apply -var="image_tag=$${IMAGE_TAG:-latest}"

tf-destroy:
	./scripts/tf.sh destroy

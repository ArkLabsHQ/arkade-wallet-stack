# Arkade Wallet Stack — day-2 operations. Run `make help` for the target list.

.DEFAULT_GOAL := help
COMPOSE := docker compose

.PHONY: help setup up down restart logs ps pull update config env

help: ## Show this help
	@grep -E '^[a-zA-Z_-]+:.*?## ' $(MAKEFILE_LIST) | \
		awk 'BEGIN{FS=":.*?## "}{printf "  \033[36m%-9s\033[0m %s\n", $$1, $$2}'

setup: ## Run interactive setup (prereqs + config + launch)
	@./setup.sh

up: ## Start the stack in the background
	$(COMPOSE) up -d

down: ## Stop the stack (keeps volumes / data)
	$(COMPOSE) down

restart: ## Restart all services
	$(COMPOSE) restart

logs: ## Follow logs from all services
	$(COMPOSE) logs -f

ps: ## Show service status
	$(COMPOSE) ps

pull: ## Pull the latest pinned images
	$(COMPOSE) pull

update: pull ## Pull images and recreate changed containers
	$(COMPOSE) up -d

config: ## Validate and render the effective compose config
	$(COMPOSE) config

env: ## Create .env from .env.example (if missing)
	@test -f .env && echo ".env already exists" || \
		(cp .env.example .env && echo "created .env — edit it, then run 'make up'")

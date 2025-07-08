# Copyright Xavier Beheydt. All rights reserved.

.DEFAULT_GOAL := up

# Variables
MKDIR = mkdir
ifeq ($(OS), Windows_NT)
	WEB_BROWSER = powershell -Command Start-Process
else
	WEB_BROWSER = open
endif
COMPOSE_CMD = docker compose \
	-f docker-compose.yml \
	--env-file .env/dolibarr.env

# Default services
SERVICES ?= \
	web db

DB_DUMP ?=
DB_PASSWORD ?=

# Targets
.PHONY: test

test:
	$(MAKE) --dry-run

.PHONY: up
up:  ## Build and start all or specific services
	$(COMPOSE_CMD) up -d ${SERVICES}

.PHONY: down
down:  ## Stop and remove all or specific services
	$(COMPOSE_CMD) down ${SERVICES}

.PHONY: stop
stop:  ## Stop all or specific services
	$(COMPOSE_CMD) stop ${SERVICES}

.PHONY: start
start:  ## Start all or specific services
	$(COMPOSE_CMD) start ${SERVICES}

.PHONY: restart
restart:  ## Restart all or specific services
	$(COMPOSE_CMD) restart ${SERVICES}

.PHONY: logs
logs:  ## Logs all or specific services
	$(COMPOSE_CMD) logs -f ${SERVICES}

.PHONY: update
update:  ## Update services
update: pull up ## Update services

.PHONY: pull
pull:  ## Pull all images
	$(COMPOSE_CMD) pull ${SERVICES}

.PHONY: db/restore
db/restore:  ## Restore DB from SQL.GZ file
	$(COMPOSE_CMD) exec -T db mariadb -uroot -p${DB_PASSWORD} dolibarr < ${DB_DUMP}
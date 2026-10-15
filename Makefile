.PHONY: build up down logs smoke pull-base clean

build:
	docker compose build

up: build
	docker compose up -d

down:
	docker compose down

logs:
	docker compose logs -f --tail=100

smoke:
	bash scripts/smoke-test.sh

# 预先拉上游镜像，减少 build 时对 ghcr 的依赖抖动
pull-base:
	docker pull ghcr.io/ardeyouxipianyi/workbuddy2api-hub:latest
	docker pull ghcr.io/guji08233/opencode-free-gate:latest

clean:
	docker compose down -v

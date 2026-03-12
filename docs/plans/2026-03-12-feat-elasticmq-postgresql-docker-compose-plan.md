---
title: "feat: Add ElasticMQ and PostgreSQL to docker-compose"
type: feat
date: 2026-03-12
---

# feat: Add ElasticMQ and PostgreSQL to docker-compose

## Overview

`docker-compose.yml`을 신규 생성하여 ElasticMQ(로컬 SQS)와 PostgreSQL 18.1을 구성한다. **모든 환경에서 primary DB를 PostgreSQL로 전환**하고, cache/queue/cable은 기존 SQLite를 유지한다.

## Problem Statement / Motivation

- 프로덕션에서 AWS SQS를 사용할 예정이나, 로컬에서 SQS API를 테스트할 수 없음
- 모든 환경에서 primary DB를 PostgreSQL로 통일하여 환경 간 차이를 최소화
- 로컬 개발 환경 셋업이 표준화되어 있지 않음

## Proposed Solution

`docker-compose.yml`과 `config/elasticmq.conf`를 생성하고, 모든 환경의 primary DB를 PostgreSQL로 전환한다. Solid Queue/Cache/Cable은 SQLite를 계속 사용한다.

## Scope Decision

**In scope:**

- `docker-compose.yml` 생성 (ElasticMQ + PostgreSQL)
- `config/elasticmq.conf` 생성 (기본 큐 1개)
- `config/database.yml` 전체 환경 PostgreSQL 전환 (primary만)
- `bin/rails db:system:change --to=postgresql` 실행 (Gemfile, database.yml, Dockerfile 자동 수정)
- `Gemfile`에 `sqlite3` 재추가
- `.env.example` 생성
- `.github/workflows/ci.yml` PostgreSQL 서비스 추가
- `config/deploy.yml` 수정 (AWS RDS 환경변수 연결)

**Out of scope (follow-up PRs):**

- `shoryuken` gem + `config/shoryuken.yml` + `config/initializers/shoryuken.rb` (worker 구현 시 함께 추가)
- `bin/setup` / `bin/dev` 스크립트 업데이트

## Technical Considerations

### Multi-database 구성: PostgreSQL + SQLite 혼용

모든 환경에서 동일한 패턴을 적용한다:

- **primary** → PostgreSQL (환경별 DB 이름)
- **cache** → SQLite (`storage/<env>_cache.sqlite3`)
- **queue** → SQLite (`storage/<env>_queue.sqlite3`)
- **cable** → SQLite (`storage/<env>_cable.sqlite3`)

이를 위해 `sqlite3`와 `pg` gem 모두 top-level에 유지해야 한다.

### `bin/rails db:system:change --to=postgresql` 활용

Rails 기본 제공 명령을 사용하여 DB 시스템을 전환한다. 이 명령이 `Gemfile`, `database.yml`, `Dockerfile`을 자동으로 업데이트한다. 단, `sqlite3` gem이 제거되므로 Solid Stack용으로 다시 추가해야 한다.

### Docker Compose 헬스체크

PostgreSQL healthcheck로 `db:prepare` 실행 전 DB 준비 상태를 보장한다.

### 포트 충돌

`127.0.0.1` 바인딩으로 localhost만 노출. `.env`로 포트 오버라이드 가능.

## Acceptance Criteria

- [x] `docker compose up -d` 실행 시 ElasticMQ와 PostgreSQL이 정상 기동됨
- [x] ElasticMQ Web UI (`http://localhost:9325`)에서 `default` 큐 확인됨
- [x] ElasticMQ SQS API (`http://localhost:9324`)가 응답함
- [x] `bin/rails db:prepare` 실행 시 PostgreSQL에 primary 스키마가 생성됨
- [x] `bin/rails test` 실행 시 PostgreSQL test DB를 사용하여 테스트 통과
- [x] `bin/kamal deploy` (프로덕션 Docker 빌드) 성공
- [ ] CI pipeline (GitHub Actions) 테스트 통과
- [x] `.env.example` 파일에 필요한 환경변수 문서화됨

## Implementation Checklist

### 1. `bin/rails db:system:change --to=postgresql` 실행

Rails 기본 명령으로 다음 파일들이 자동 수정됨:

- `Gemfile`: `sqlite3` → `pg` 교체
- `config/database.yml`: PostgreSQL 기본 설정으로 전환
- `Dockerfile`: `libpq-dev`/`libpq5` 패키지 추가

> **주의:** 이 명령은 `sqlite3` gem을 제거하므로 수동으로 다시 추가해야 함 (Solid Cache/Queue/Cable용).

### 2. `Gemfile` 후속 수정

`db:system:change` 실행 후, `sqlite3`을 추가:

```ruby
gem "pg"
gem "sqlite3", ">= 2.1"  # Solid Cache, Queue, Cable용
```

### 3. `config/database.yml` 후속 수정

`db:system:change`가 생성한 기본 PostgreSQL 설정에 Solid Cache/Queue/Cable의 SQLite 설정을 추가:

```yaml
# db:system:change가 생성한 PostgreSQL 기본 설정 유지
default: &default
  adapter: postgresql
  encoding: unicode
  pool: <%= ENV.fetch("RAILS_MAX_THREADS", 5) %>
  host: <%= ENV.fetch("DB_HOST", "localhost") %>
  username: <%= ENV.fetch("DB_USERNAME", "explained") %>
  password: <%= ENV.fetch("DB_PASSWORD", "explained") %>
  port: <%= ENV.fetch("DB_PORT", 5432) %>

# Solid Stack용 SQLite 설정
default_sqlite: &default_sqlite
  adapter: sqlite3
  max_connections: <%= ENV.fetch("RAILS_MAX_THREADS", 5) %>
  timeout: 5000

development:
  primary:
    <<: *default
    database: explained_development
  cache:
    <<: *default_sqlite
    database: storage/development_cache.sqlite3
    migrations_paths: db/cache_migrate
  queue:
    <<: *default_sqlite
    database: storage/development_queue.sqlite3
    migrations_paths: db/queue_migrate
  cable:
    <<: *default_sqlite
    database: storage/development_cable.sqlite3
    migrations_paths: db/cable_migrate

test:
  primary:
    <<: *default
    database: explained_test
  cache:
    <<: *default_sqlite
    database: storage/test_cache.sqlite3
    migrations_paths: db/cache_migrate
  queue:
    <<: *default_sqlite
    database: storage/test_queue.sqlite3
    migrations_paths: db/queue_migrate
  cable:
    <<: *default_sqlite
    database: storage/test_cable.sqlite3
    migrations_paths: db/cable_migrate

production:
  primary:
    <<: *default
    database: <%= ENV.fetch("DB_NAME", "explained_production") %>
  cache:
    <<: *default_sqlite
    database: storage/production_cache.sqlite3
    migrations_paths: db/cache_migrate
  queue:
    <<: *default_sqlite
    database: storage/production_queue.sqlite3
    migrations_paths: db/queue_migrate
  cable:
    <<: *default_sqlite
    database: storage/production_cable.sqlite3
    migrations_paths: db/cable_migrate
```

### 4. `docker-compose.yml` 생성

파일: `docker-compose.yml` (repo root)

```yaml
services:
  elasticmq:
    image: softwaremill/elasticmq-native
    ports:
      - "127.0.0.1:9324:9324"
      - "127.0.0.1:9325:9325"
    volumes:
      - ./config/elasticmq.conf:/opt/elasticmq.conf

  db:
    image: postgres:18
    ports:
      - "127.0.0.1:5432:5432"
    environment:
      POSTGRES_USER: explained
      POSTGRES_PASSWORD: explained
      POSTGRES_DB: explained_development
    volumes:
      - postgres_data:/var/lib/postgresql/data
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U explained"]
      interval: 5s
      timeout: 5s
      retries: 5

volumes:
  postgres_data:
```

### 5. `config/elasticmq.conf` 생성

파일: `config/elasticmq.conf`

```hocon
include classpath("application.conf")

node-address {
  protocol = http
  host = "*"
  port = 9324
  context-path = ""
}

rest-sqs {
  enabled = true
  bind-port = 9324
  bind-hostname = "0.0.0.0"
  sqs-limits = strict
}

queues {
  default {
    defaultVisibilityTimeout = 30 seconds
    delay = 0 seconds
    receiveMessageWait = 0 seconds
  }
}
```

### 6. `.env.example` 생성

파일: `.env.example`

```env
# PostgreSQL (docker-compose)
DB_HOST=localhost
DB_PORT=5432
DB_USERNAME=explained
DB_PASSWORD=explained

# ElasticMQ (local SQS)
SQS_ENDPOINT=http://localhost:9324
AWS_REGION=us-east-1
AWS_ACCESS_KEY_ID=test
AWS_SECRET_ACCESS_KEY=test
```

### 7. `.github/workflows/ci.yml` 수정

test 및 system-test job에 PostgreSQL 서비스 추가:

```yaml
test:
  runs-on: ubuntu-latest
  services:
    postgres:
      image: postgres:18
      env:
        POSTGRES_USER: explained
        POSTGRES_PASSWORD: explained
        POSTGRES_DB: explained_test
      ports:
        - 5432:5432
      options: >-
        --health-cmd pg_isready
        --health-interval 10s
        --health-timeout 5s
        --health-retries 5
  env:
    DB_HOST: localhost
    DB_PORT: 5432
    DB_USERNAME: explained
    DB_PASSWORD: explained
```

### 8. `config/deploy.yml` 수정

프로덕션에서 AWS RDS (PostgreSQL)를 사용하므로, DB 접속 정보를 secret 환경변수로 연결한다.

```yaml
env:
  secret:
    - RAILS_MASTER_KEY
    - DB_HOST
    - DB_USERNAME
    - DB_PASSWORD
    - DB_NAME
  clear:
    SOLID_QUEUE_IN_PUMA: true
    DB_PORT: 5432
```

> **Note:** `DB_HOST`, `DB_USERNAME`, `DB_PASSWORD`, `DB_NAME`은 `.kamal/secrets`에서 관리한다. AWS RDS 엔드포인트(예: `explained.xxxx.ap-northeast-2.rds.amazonaws.com`)를 `DB_HOST`로 설정.

볼륨 설명 주석도 업데이트:

```yaml
# Solid Cache/Queue/Cable의 SQLite 파일과 Active Storage 파일을 위한 영속 볼륨
volumes:
  - "explained_storage:/rails/storage"
```

## Dependencies & Risks

| Risk                              | Impact | Mitigation                                                      |
| --------------------------------- | ------ | --------------------------------------------------------------- |
| Dockerfile 빌드 실패 (libpq 누락) | High   | `libpq-dev`/`libpq5` 추가를 같은 PR에서 처리                    |
| 프로덕션 RDS 접속 실패            | High   | `deploy.yml`에 secret 환경변수 연결, `.kamal/secrets` 설정 필수 |
| 로컬 PostgreSQL과 포트 충돌       | Medium | `127.0.0.1` 바인딩 + `.env` 오버라이드                          |
| CI PostgreSQL 서비스 설정 오류    | Medium | ci.yml 업데이트를 같은 PR에서 처리                              |
| 기존 SQLite 개발 데이터 손실      | Low    | SQLite 파일 유지, 새로 db:prepare                               |
| multi-db 구성 오류 (adapter 혼용) | Medium | YAML anchor 분리 (`default`/`default_sqlite`)                   |

## Follow-up Tasks

1. `shoryuken` gem + config + initializer 추가 (worker job 구현과 함께)
2. `bin/setup`에 `docker compose up -d` 단계 추가
3. `Procfile.dev`에 Shoryuken worker 프로세스 추가
4. AWS RDS 인스턴스 생성 및 `.kamal/secrets`에 접속 정보 설정

## References

- Brainstorm: `docs/brainstorms/2026-03-12-elasticmq-docker-compose-brainstorm.md`
- ElasticMQ Docker Hub: `softwaremill/elasticmq-native`
- 현재 DB 설정: `config/database.yml`
- 현재 Dockerfile: `Dockerfile`
- 현재 CI 설정: `.github/workflows/ci.yml`
- 현재 Kamal 설정: `config/deploy.yml`

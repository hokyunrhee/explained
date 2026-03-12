---
title: "feat: Add Shoryuken SQS Worker"
type: feat
date: 2026-03-12
---

# feat: Add Shoryuken SQS Worker

## Overview

Shoryuken gem을 추가하여 ElasticMQ(SQS 호환) 큐에서 메시지를 폴링하고 PostgreSQL에 기록하는 Worker 시스템을 구성한다. 기존 Solid Queue(ActiveJob)는 그대로 유지하며, Shoryuken은 SQS 전용 메시지 처리만 담당하는 **병행 구성**으로 운영한다.

**Brainstorm:** `docs/brainstorms/2026-03-12-shoryuken-sqs-worker-brainstorm.md`

## Key Decisions

| 결정 사항        | 선택                               | 이유                                                  |
| ---------------- | ---------------------------------- | ----------------------------------------------------- |
| Worker 방식      | `Shoryuken::Worker` 직접 사용      | ActiveJob 오버헤드 없이 SQS 기능 완전 활용            |
| ActiveJob 어댑터 | 변경 없음 (Solid Queue 유지)       | 기존 Rails 잡과 분리 운영                             |
| 큐 이름          | `explained-default`                | 프로젝트명 접두사로 충돌 방지                         |
| 동시성           | 5 스레드                           | worker 역할에서 `RAILS_MAX_THREADS=10`으로 DB 풀 확보 |
| 에러 처리        | SQS visibility timeout 기반 재시도 | DLQ는 실제 Worker 추가 시 구성                        |
| 프로덕션 배포    | Kamal worker 역할                  | 같은 이미지, CMD만 변경                               |

## Acceptance Criteria

- [x] `bundle exec shoryuken -R -C config/shoryuken.yml`로 별도 터미널에서 ElasticMQ 큐 폴링 시작
- [x] Kamal `deploy.yml`에 worker 역할 추가 완료
- [x] Shoryuken initializer가 테스트 환경에서 SQS 클라이언트를 생성하지 않음

---

## Implementation Plan

### Phase 1: Gem 추가 및 기본 구성

#### 1.1 Gemfile 수정

**File:** `Gemfile` (line 31 이후)

```ruby
# SQS message processing with Shoryuken [https://github.com/ruby-shoryuken/shoryuken]
gem "shoryuken"
```

> `aws-sdk-sqs`는 Shoryuken의 transitive dependency로 이미 포함되므로 명시적 추가 불필요.

그 후 `bundle install` 실행.

#### 1.2 Shoryuken 설정 파일 생성

**New file:** `config/shoryuken.yml`

```yaml
# config/shoryuken.yml
# NOTE: Shoryuken YAML은 ERB를 지원하지 않음. concurrency는 CLI -c 플래그 또는 여기서 직접 지정.
concurrency: 5

queues:
  - explained-default
```

> **Bug fix (ERB 미지원):** Shoryuken의 YAML 로더는 ERB를 처리하지 않는다. `<%= %>` 구문은 문자열로 그대로 파싱되어 오류 발생. concurrency를 동적으로 변경하려면 CLI 플래그 `-c 10`을 사용할 것.

#### 1.3 Shoryuken Initializer 생성

**New file:** `config/initializers/shoryuken.rb`

```ruby
# config/initializers/shoryuken.rb

# 테스트 환경에서는 SQS 클라이언트를 생성하지 않음 (Shoryuken::Testing 사용)
return if Rails.env.test?

sqs_client_options = { region: ENV.fetch("AWS_REGION", "us-east-1") }

# 프로덕션: IAM role 또는 명시적 자격 증명 (미설정 시 즉시 실패)
# 개발: ElasticMQ용 더미 자격 증명
if Rails.env.production?
  sqs_client_options[:access_key_id] = ENV.fetch("AWS_ACCESS_KEY_ID")
  sqs_client_options[:secret_access_key] = ENV.fetch("AWS_SECRET_ACCESS_KEY")
else
  sqs_client_options[:access_key_id] = ENV.fetch("AWS_ACCESS_KEY_ID", "test")
  sqs_client_options[:secret_access_key] = ENV.fetch("AWS_SECRET_ACCESS_KEY", "test")
end

# ElasticMQ 또는 커스텀 SQS 엔드포인트 (개발 환경)
if ENV["SQS_ENDPOINT"].present?
  sqs_client_options[:endpoint] = ENV["SQS_ENDPOINT"]
  sqs_client_options[:verify_checksums] = false
end

Shoryuken.configure_server do |config|
  config.sqs_client = Aws::SQS::Client.new(sqs_client_options)
  Shoryuken.logger = Rails.logger
end
```

> **Bug fix (테스트 환경 가드):** 테스트 환경에서 SQS 클라이언트 생성을 방지. CI에서 ElasticMQ 없이도 테스트 실행 가능.

### Phase 2: ElasticMQ 큐 이름 변경

**File:** `config/elasticmq.conf`

기존 `queues` 블록을 다음으로 교체:

```hocon
queues {
  explained-default {
    defaultVisibilityTimeout = 30 seconds
    delay = 0 seconds
    receiveMessageWait = 0 seconds
  }
}
```

> **Note:** 기존 `default` 큐를 `explained-default`로 변경. DLQ는 실제 Worker 추가 시 구성.

### Phase 3: 프로덕션 배포 구성 (Kamal)

> **Note:** `app/workers/` 디렉토리와 첫 번째 Worker는 실제 비즈니스 로직이 정해진 후 생성한다. 샘플 Worker는 추가하지 않는다.

> **개발 환경:** `bin/dev`는 변경하지 않음. Shoryuken은 별도 터미널에서 실행:
>
> ```bash
> bundle exec shoryuken -R -C config/shoryuken.yml
> ```

#### 3.1 deploy.yml 업데이트

**File:** `config/deploy.yml`

`servers` 섹션에 worker 역할 추가 (line 8-14):

```yaml
servers:
  web:
    hosts:
      - 192.168.0.1
    env:
      clear:
        SOLID_QUEUE_IN_PUMA: true
  worker:
    hosts:
      - 192.168.0.1
    cmd: bundle exec shoryuken -R -C config/shoryuken.yml
    env:
      clear:
        RAILS_MAX_THREADS: 10
```

> **Bug fix (SOLID_QUEUE_IN_PUMA):** `puma.rb`에서 `if ENV["SOLID_QUEUE_IN_PUMA"]`로 존재 여부만 체크하므로 문자열 `"false"`도 truthy. 글로벌 env에서 제거하고 web 역할에만 설정해야 worker 컨테이너에 누수되지 않음.
>
> **DB 풀:** `SHORYUKEN_DB_POOL` 같은 커스텀 변수 대신 `RAILS_MAX_THREADS=10`을 worker 역할에 설정. `database.yml`의 기존 `pool: <%= ENV.fetch("RAILS_MAX_THREADS", 5) %>`가 그대로 동작.

`env.secret`에 AWS 자격 증명 추가 (line 41-46):

```yaml
env:
  secret:
    - RAILS_MASTER_KEY
    - DB_HOST
    - DB_USERNAME
    - DB_PASSWORD
    - DB_NAME
    - AWS_ACCESS_KEY_ID
    - AWS_SECRET_ACCESS_KEY
  clear:
    DB_PORT: 5432
    AWS_REGION: us-east-1
```

---

## File Change Summary

| Action     | File                               | Description                                                        |
| ---------- | ---------------------------------- | ------------------------------------------------------------------ |
| **Modify** | `Gemfile`                          | `shoryuken` 추가                                                   |
| **Modify** | `config/elasticmq.conf`            | 큐 이름을 `explained-default`로 변경                               |
| **Modify** | `config/deploy.yml`                | worker 역할 + AWS 환경변수 + SOLID_QUEUE_IN_PUMA를 web 역할로 이동 |
| **Create** | `config/shoryuken.yml`             | Shoryuken 큐 및 동시성 설정                                        |
| **Create** | `config/initializers/shoryuken.rb` | AWS SQS 클라이언트 구성                                            |

## Architecture Diagram

```
┌─────────────────────────────────────────────────────┐
│                    Rails App                         │
│                                                      │
│  ┌──────────────┐          ┌──────────────────────┐ │
│  │  ActiveJob    │          │  Shoryuken::Worker   │ │
│  │  (Mailers,   │          │  (SQS Messages →     │ │
│  │   Caching)   │          │   PostgreSQL)         │ │
│  └──────┬───────┘          └──────────┬───────────┘ │
│         │                             │              │
│  ┌──────▼───────┐          ┌──────────▼───────────┐ │
│  │  Solid Queue  │          │  SQS / ElasticMQ     │ │
│  │  (SQLite)     │          │  (explained-default)  │ │
│  └──────────────┘          └──────────────────────┘ │
└─────────────────────────────────────────────────────┘

Processes:
  bin/rails server   → Puma (web)
  bin/jobs            → Solid Queue (background jobs)
  bundle exec shoryuken → Shoryuken (SQS workers)
```

## Message Flow (Error Handling)

Worker 추가 시 `auto_delete: true` 설정하면 성공 시 메시지 자동 삭제. 실패 시 SQS visibility timeout 후 자동 재시도.

## Future Considerations (Out of Scope)

DLQ, error reporting, health check, FIFO 큐, batch processing, long polling, processing groups, 환경별 큐 이름 분리(programmatic queue config) 등은 첫 번째 실제 Worker 추가 시 함께 구성.

## References

- [Shoryuken Wiki](https://github.com/ruby-shoryuken/shoryuken/wiki)
- [Shoryuken Worker Options](https://github.com/ruby-shoryuken/shoryuken/wiki/Worker-options)
- [Configure AWS Client](https://github.com/ruby-shoryuken/shoryuken/wiki/Configure-the-AWS-Client)
- Brainstorm: `docs/brainstorms/2026-03-12-shoryuken-sqs-worker-brainstorm.md`
- Infra plan: `docs/plans/2026-03-12-feat-elasticmq-postgresql-docker-compose-plan.md`

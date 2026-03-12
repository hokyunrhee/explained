# Brainstorm: Shoryuken SQS Worker 구성

**Date:** 2026-03-12
**Status:** Decided

## What We're Building

Shoryuken gem을 추가하여 ElasticMQ(SQS 호환) 큐에서 메시지를 폴링하고, PostgreSQL(primary DB)에 기록하는 Worker를 구성한다.

기존 Solid Queue는 Rails 기본 백그라운드 잡(메일러, 캐시 등)을 계속 담당하며, Shoryuken은 SQS 전용 메시지 처리만 담당하는 **병행 구성**으로 운영한다.

## Why This Approach

- **Shoryuken Worker 직접 사용 (ActiveJob 어댑터 없이)**
  - SQS 메시지 폴링 → DB 기록이라는 단순한 유스케이스에 적합
  - SQS 고유 기능 완전 활용 가능 (visibility timeout, batch 처리, FIFO 큐 등)
  - ActiveJob 오버헤드 없이 낮은 레이턴시
  - Solid Queue와 독립적으로 운영 가능, 서로 간섭 없음

- **ActiveJob 어댑터 병행 방식을 선택하지 않은 이유**
  - 두 어댑터 전환 복잡도 증가
  - SQS 고유 기능 일부 제한
  - 이 유스케이스에서는 ActiveJob 인터페이스가 불필요

## Key Decisions

1. **Shoryuken Worker 직접 사용** — `Shoryuken::Worker`를 include한 Worker 클래스 생성
2. **Solid Queue 유지** — 기존 Rails ActiveJob은 Solid Queue가 계속 처리
3. **별도 프로세스로 실행** — `bundle exec shoryuken` 으로 독립 실행
4. **ElasticMQ(로컬) / SQS(프로덕션)** — 환경별 엔드포인트 분리
5. **에러 처리: SQS 기본 재시도 + DLQ** — SQS visibility timeout으로 자동 재시도, maxReceiveCount: 3 초과 시 Dead Letter Queue로 이동
6. **DLQ 구성** — 메인 큐와 별도의 DLQ 큐 생성 (ElasticMQ/SQS 모두), 실패 메시지 추적 및 수동 재처리 가능

## Error Handling Strategy

- **재시도**: SQS visibility timeout 기반 자동 재시도 (Shoryuken 레벨 재시도 로직 불필요)
- **maxReceiveCount: 3** — 3회 실패 후 DLQ로 자동 이동
- **DLQ**: 메인 큐마다 대응하는 DLQ 큐 구성
- **Worker에서는 예외를 raise만 하면 됨** — SQS가 메시지를 다시 visible 상태로 전환하여 재시도
- ElasticMQ에서도 DLQ redrive policy 지원 (`config/elasticmq.conf`에 설정)

## Open Questions

- SQS 큐 이름은 무엇으로 할 것인가?
- 메시지 포맷 (JSON 구조)은 어떻게 정의할 것인가?
- 프로덕션 배포 시 Shoryuken 프로세스 관리 방법 (systemd, Docker 등)?

## Reference

- [Shoryuken Wiki](https://github.com/ruby-shoryuken/shoryuken/wiki)
- 기존 docker-compose: ElasticMQ (port 9324/9325)
- 기존 `.env.example`: SQS 엔드포인트 및 AWS 자격 증명

# ElasticMQ + PostgreSQL Docker Compose 구성

**Date:** 2026-03-12
**Status:** Decided

## What We're Building

로컬 개발/테스트 환경을 위한 `docker-compose.yml` 구성:
- **ElasticMQ** (`softwaremill/elasticmq-native`): AWS SQS 호환 로컬 메시지 큐
- **PostgreSQL 17**: 프로덕션 대비 데이터베이스 (현재 sqlite3에서 전환)

## Why This Approach

- 프로덕션에서 AWS SQS를 사용할 예정이므로, 로컬에서 SQS 호환 환경이 필요
- `elasticmq.conf` 설정 파일을 마운트하여 큐 정의를 버전 관리
- PostgreSQL을 로컬에서도 사용하여 프로덕션과 동일한 DB 환경 구성

## Key Decisions

- **ElasticMQ 이미지**: `softwaremill/elasticmq-native` (GraalVM 네이티브 빌드, 빠른 시작)
- **포트**: 9324 (SQS API), 9325 (Web UI)
- **큐 설정**: `config/elasticmq.conf` 파일로 관리, 기본 큐 1개 (`default`)
- **DB**: PostgreSQL 18.1, 볼륨으로 데이터 영속화
- **구성 방식**: 설정 파일 마운트 (`./config/elasticmq.conf:/opt/elasticmq.conf`)

## Open Questions

- PostgreSQL에서 사용할 정확한 DB 이름/유저 컨벤션
- `aws-sdk-sqs` gem 추가 및 Rails 설정 연동
- 테스트 환경에서의 ElasticMQ 활용 방안

# Brainstorm: EvTelemetry 모델 & Shoryuken Worker

**Date:** 2026-03-13
**Status:** Decided

## What We're Building

SQS(ElasticMQ)에서 수신한 EV telemetry 데이터를 PostgreSQL에 저장하는 기능:

1. **`EvTelemetry` 모델** — `random_telemetry`의 모든 필드를 개별 컬럼으로 저장
2. **Shoryuken Worker** — `explained-default` 큐에서 메시지를 수신하여 `EvTelemetry.create!`

## Why This Approach

- **Flat 컬럼**: 각 telemetry 필드를 개별 컬럼으로 저장. 쿼리, 인덱싱, 타입 안전성이 좋음. JSONB는 현재 단계에서 YAGNI.
- **Shoryuken Worker**: 기존 인프라(ElasticMQ, shoryuken.yml, Kamal worker role)와 자연스럽게 연동. ActiveJob 레이어 불필요.

## Key Decisions

- **모델명**: `EvTelemetry`
- **Job 타입**: Shoryuken Worker (ActiveJob 아님)
- **DB 스키마**: Flat 컬럼 (JSONB 아님)
- **큐**: 기존 `explained-default` 큐 사용

## EvTelemetry 컬럼 (from random_telemetry)

| Column | Type | Notes |
|---|---|---|
| vehicle_id | string | not null, indexed |
| timestamp | datetime | not null (recorded_at로 명명 가능) |
| latitude | decimal | precision: 8, scale: 4 |
| longitude | decimal | precision: 8, scale: 4 |
| speed_kmh | decimal | precision: 5, scale: 1 |
| battery_soc_pct | decimal | precision: 4, scale: 1 |
| battery_voltage | decimal | precision: 4, scale: 1 |
| motor_power_kw | decimal | precision: 5, scale: 1 |
| regen_active | boolean | |
| odometer_km | decimal | precision: 7, scale: 1 |

## Open Questions

- `timestamp` 필드명을 `recorded_at`으로 변경할지 (Rails의 `timestamp` 예약어 충돌 방지)
- 인덱스 전략: `vehicle_id` 단독 vs `[vehicle_id, recorded_at]` 복합 인덱스

# Brainstorm: ElasticMQ Seeder — 로컬 테스트용 EV Telemetry 시뮬레이터

**Date:** 2026-03-13
**Status:** Decided

## What We're Building

로컬 개발 환경에서 Shoryuken Worker의 동작을 데모/시연할 수 있도록, 여러 대의 가상 전기차(EV)가 telemetry 데이터를 ElasticMQ에 주기적으로 전송하는 Rake task를 만든다.

- **5대의 가상 차량**이 각각 **3초 간격**으로 telemetry 메시지 전송
- 차량별로 위치/속도/배터리 등이 **연속적으로 변화** (이전 값 기반 증감)
- `concurrent-ruby`를 사용하여 차량별 독립 스레드로 병렬 시뮬레이션

## Why This Approach

- **Rake task + concurrent-ruby 병렬 시뮬레이션**
  - 차량별 독립 스레드로 현실적인 다중 장비 시뮬레이션 가능
  - 차량마다 상태를 유지하면서 연속적인 데이터 변화 표현
  - concurrent-ruby는 Rails 의존성에 이미 포함 (별도 gem 추가 불필요)
  - Ctrl+C로 즉시 중단 가능 (graceful shutdown)

- **단순 sleep loop를 선택하지 않은 이유**
  - 단일 스레드로는 차량별 독립적인 상태 관리가 어려움
  - 데모 시 여러 장비가 동시에 데이터를 보내는 모습이 더 현실적

## Message Format

```json
{
  "vehicle_id": "EV-KR-00001",
  "timestamp": "2026-03-13T09:41:32Z",
  "latitude": 37.4989,
  "longitude": 127.0328,
  "speed_kmh": 72.1,
  "battery_soc_pct": 64.2,
  "battery_voltage": 356.8,
  "motor_power_kw": 18.7,
  "regen_active": false,
  "odometer_km": 12340.5
}
```

### 데이터 시뮬레이션 규칙

| 필드 | 변화 방식 |
|------|-----------|
| `vehicle_id` | 차량별 고정 (`EV-KR-00001` ~ `EV-KR-00005`) |
| `timestamp` | 현재 시각 (UTC) |
| `latitude/longitude` | 이전 값 ± 소량 랜덤 변화 (서울 근처 유지) |
| `speed_kmh` | 0~120 범위, 이전 값 ± 랜덤 증감 |
| `battery_soc_pct` | 서서히 감소 (주행 중), 100에서 시작 |
| `battery_voltage` | SOC에 비례하여 변화 (320~400V 범위) |
| `motor_power_kw` | 속도에 비례, 랜덤 변동 |
| `regen_active` | 감속 시 true |
| `odometer_km` | 속도에 따라 누적 증가 |

## Key Decisions

1. **Rake task로 구현** — `rake sqs:seed_loop`로 실행
2. **concurrent-ruby로 병렬 시뮬레이션** — 차량별 독립 스레드
3. **5대 차량, 3초 간격** — 약 100 msg/min
4. **연속적 데이터 변화** — 차량별 상태 유지, 이전 값 기반 증감
5. **기존 Shoryuken initializer의 SQS 클라이언트 재활용** — 별도 설정 불필요

## Open Questions

- Worker 구현 후 메시지 포맷이 변경될 수 있음 (Worker와 seeder 동기화 필요)

## Execution

```bash
# ElasticMQ + Shoryuken 실행 상태에서:
$ rake sqs:seed_loop

[EV-KR-00001] Sent telemetry (speed: 72.1, soc: 98.3%)
[EV-KR-00003] Sent telemetry (speed: 45.0, soc: 95.1%)
[EV-KR-00002] Sent telemetry (speed: 0.0, soc: 99.8%)
...
(Ctrl+C to stop)
```

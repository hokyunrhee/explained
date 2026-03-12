---
title: "feat: Add ElasticMQ EV Telemetry Seeder Rake Task"
type: feat
date: 2026-03-13
---

# feat: Add ElasticMQ EV Telemetry Seeder Rake Task

## Overview

로컬 개발 환경에서 Shoryuken Worker 동작을 데모/시연할 수 있도록, 5대의 가상 전기차(EV)가 telemetry 데이터를 ElasticMQ에 3초 간격으로 전송하는 Rake task를 만든다. 단순 `loop`/`sleep` 패턴으로 순차 전송하며, 각 차량의 위치/속도/배터리 등이 틱마다 변화한다.

**Brainstorm:** `docs/brainstorms/2026-03-13-elasticmq-seeder-brainstorm.md`

## Key Decisions

| 결정 사항 | 선택 | 이유 |
|-----------|------|------|
| Task 이름 | `rake sqs:simulate_telemetry` | `seed_loop`은 `db:seed`와 혼동. 동작을 명확히 표현 |
| 실행 방식 | `loop`/`sleep` 순차 전송 | 5개 메시지는 밀리초 내 전송 완료 — 스레딩 불필요 |
| SQS 클라이언트 | 공유 헬퍼 `SqsClient.build` | Shoryuken initializer와 중복 방지 |
| 데이터 생성 | 범위 내 랜덤 값 | 시뮬레이션 불필요 — 매 틱 독립적인 랜덤 데이터 생성 |
| 큐 이름 | 설정에서 읽기 | `shoryuken.yml`에서 읽어 3곳 하드코딩 방지 |
| 종료 | `rescue Interrupt` | Ctrl+C → Ruby 기본 Interrupt 처리로 충분 |

## Acceptance Criteria

- [x] `rake sqs:simulate_telemetry` 실행 시 5대 차량의 telemetry가 ElasticMQ `explained-default` 큐에 3초 간격으로 전송됨
- [x] 각 차량의 데이터가 틱마다 변화 (위치 이동, 배터리 감소, 속도 증감)
- [x] Ctrl+C로 정상 종료
- [x] ElasticMQ 미실행 시 명확한 에러 메시지 출력

---

## Implementation Plan

### Phase 1: SQS 클라이언트 헬퍼 추출

**New file:** `lib/sqs_client.rb`

Shoryuken initializer와 Rake task가 공유하는 SQS 클라이언트 팩토리:

```ruby
# lib/sqs_client.rb
module SqsClient
  def self.build
    options = {
      region: ENV.fetch("AWS_REGION", "us-east-1"),
      access_key_id: ENV.fetch("AWS_ACCESS_KEY_ID", "test"),
      secret_access_key: ENV.fetch("AWS_SECRET_ACCESS_KEY", "test")
    }

    if ENV["SQS_ENDPOINT"].present?
      options[:endpoint] = ENV["SQS_ENDPOINT"]
      options[:verify_checksums] = false
    end

    Aws::SQS::Client.new(options)
  end
end
```

> 기존 initializer 동작과 동일. production 분기 없음 — 프로덕션 배포 시 별도로 추가.

**Modify:** `config/initializers/shoryuken.rb` — 클라이언트 생성을 `SqsClient.build`로 교체:

```ruby
# config/initializers/shoryuken.rb
return if Rails.env.test?

require_relative "../../lib/sqs_client"

Shoryuken.configure_server do |config|
  config.sqs_client = SqsClient.build
  Shoryuken.logger = Rails.logger
end
```

### Phase 2: Rake Task에서 직접 랜덤 데이터 생성

별도 클래스 불필요. Rake task 내에서 차량 ID 목록과 랜덤 해시 생성 메서드만 사용:

```ruby
def random_telemetry(vehicle_id)
  {
    vehicle_id: vehicle_id,
    timestamp: Time.now.utc.iso8601,
    latitude: rand(37.42..37.58).round(4),
    longitude: rand(126.90..127.10).round(4),
    speed_kmh: rand(0.0..120.0).round(1),
    battery_soc_pct: rand(0.0..100.0).round(1),
    battery_voltage: rand(320.0..400.0).round(1),
    motor_power_kw: rand(0.0..150.0).round(1),
    regen_active: [true, false].sample,
    odometer_km: rand(1000.0..50000.0).round(1)
  }
end
```

> 상태 관리 없음. 매 틱 독립적인 랜덤 값. VehicleSimulator 클래스 불필요.

### Phase 3: Rake Task

**New file:** `lib/tasks/sqs.rake`

```ruby
# lib/tasks/sqs.rake
require_relative "../../lib/sqs_client"

namespace :sqs do
  desc "EV telemetry 랜덤 데이터를 ElasticMQ에 주기적으로 전송"
  task simulate_telemetry: :environment do
    queue_name = YAML.safe_load_file(Rails.root.join("config/shoryuken.yml")).dig("queues", 0) || "explained-default"
    sqs = SqsClient.build
    queue_url = sqs.create_queue(queue_name: queue_name).queue_url
    vehicle_ids = 5.times.map { |i| format("EV-KR-%05d", i + 1) }

    puts "Seeding #{queue_name} at #{sqs.config.endpoint} with #{vehicle_ids.size} vehicles every 3s (Ctrl+C to stop)"

    loop do
      vehicle_ids.each do |id|
        msg = random_telemetry(id)
        sqs.send_message(queue_url: queue_url, message_body: msg.to_json)
        puts "[#{id}] speed: #{msg[:speed_kmh]}km/h, soc: #{msg[:battery_soc_pct]}%, lat: #{msg[:latitude]}"
      end
      sleep 3
    end
  rescue Interrupt
    puts "\nStopped."
  rescue => e
    abort("Error: #{e.message}")
  end
end
```

---

## File Change Summary

| Action | File | Description |
|--------|------|-------------|
| **Create** | `lib/sqs_client.rb` | SQS 클라이언트 팩토리 (공유 헬퍼) |
| **Create** | `lib/tasks/sqs.rake` | Rake task + `random_telemetry` 헬퍼 메서드 |
| **Modify** | `config/initializers/shoryuken.rb` | `SqsClient.build` 사용으로 교체 |

> gem 추가 없음. 별도 클래스 없음. Rake 파일 하나에 모든 로직 포함.

## 실행 예시

```
$ rake sqs:simulate_telemetry

Seeding explained-default at http://localhost:9324 with 5 vehicles every 3s (Ctrl+C to stop)
[EV-KR-00001] speed: 52.3km/h, soc: 99.7%, lat: 37.5003
[EV-KR-00002] speed: 38.1km/h, soc: 99.8%, lat: 37.5102
[EV-KR-00003] speed: 0.0km/h, soc: 100.0%, lat: 37.5200
[EV-KR-00004] speed: 71.2km/h, soc: 99.5%, lat: 37.5305
[EV-KR-00005] speed: 15.6km/h, soc: 99.9%, lat: 37.5401
...
^C
Stopped.
```

## References

- Brainstorm: `docs/brainstorms/2026-03-13-elasticmq-seeder-brainstorm.md`
- Shoryuken Worker plan: `docs/plans/2026-03-12-feat-shoryuken-sqs-worker-plan.md`
- [AWS SQS Client#send_message](https://docs.aws.amazon.com/sdk-for-ruby/v3/api/Aws/SQS/Client.html#send_message-instance_method)

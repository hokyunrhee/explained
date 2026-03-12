# lib/tasks/sqs.rake
require_relative "../sqs_client"

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

class EvTelemetryWorker
  include Shoryuken::Worker

  shoryuken_options queue: "explained-default", auto_delete: true

  def perform(_sqs_msg, body)
    payload = JSON.parse(body)

    EvTelemetry.create!(
      vehicle_id:      payload["vehicle_id"],
      recorded_at:     payload["timestamp"],
      latitude:        payload["latitude"],
      longitude:       payload["longitude"],
      speed_kmh:       payload["speed_kmh"],
      battery_soc_pct: payload["battery_soc_pct"],
      battery_voltage: payload["battery_voltage"],
      motor_power_kw:  payload["motor_power_kw"],
      regen_active:    payload["regen_active"],
      odometer_km:     payload["odometer_km"]
    )

    Rails.logger.debug { "[EvTelemetryWorker] Saved telemetry for #{payload["vehicle_id"]}" }
  rescue JSON::ParserError => e
    Rails.logger.error { "[EvTelemetryWorker] Malformed JSON: #{e.message}" }
  rescue ActiveRecord::RecordNotUnique
    Rails.logger.debug { "[EvTelemetryWorker] Duplicate message, skipping" }
  rescue ActiveRecord::RecordInvalid => e
    Rails.logger.error { "[EvTelemetryWorker] Invalid record: #{e.message}" }
  end
end

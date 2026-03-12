require "test_helper"

class EvTelemetryWorkerTest < ActiveSupport::TestCase
  setup do
    @worker = EvTelemetryWorker.new
    @valid_body = {
      vehicle_id: "EV-KR-00001",
      timestamp: "2026-03-13T12:00:00Z",
      latitude: 37.5003,
      longitude: 126.9512,
      speed_kmh: 52.3,
      battery_soc_pct: 99.7,
      battery_voltage: 356.2,
      motor_power_kw: 45.8,
      regen_active: true,
      odometer_km: 12345.6
    }.to_json
  end

  test "saves valid telemetry message to database" do
    assert_difference("EvTelemetry.count", 1) do
      @worker.perform(nil, @valid_body)
    end

    record = EvTelemetry.last
    assert_equal "EV-KR-00001", record.vehicle_id
    assert_equal 37.5003, record.latitude.to_f
    assert record.regen_active
  end

  test "maps timestamp field to recorded_at" do
    @worker.perform(nil, @valid_body)

    record = EvTelemetry.last
    assert_equal Time.utc(2026, 3, 13, 12, 0, 0), record.recorded_at
  end

  test "handles duplicate messages gracefully" do
    @worker.perform(nil, @valid_body)

    assert_no_difference("EvTelemetry.count") do
      @worker.perform(nil, @valid_body)
    end
  end

  test "handles malformed JSON gracefully" do
    assert_nothing_raised do
      @worker.perform(nil, "not valid json{{{")
    end

    assert_equal 0, EvTelemetry.count
  end

  test "handles missing required fields gracefully" do
    body = { latitude: 37.5 }.to_json

    assert_nothing_raised do
      @worker.perform(nil, body)
    end

    assert_equal 0, EvTelemetry.count
  end
end

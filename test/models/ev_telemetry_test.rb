require "test_helper"

class EvTelemetryTest < ActiveSupport::TestCase
  setup do
    @valid_attrs = {
      vehicle_id: "EV-KR-00001",
      recorded_at: Time.utc(2026, 3, 13, 12, 0, 0),
      latitude: 37.5003,
      longitude: 126.9512,
      speed_kmh: 52.3,
      battery_soc_pct: 99.7,
      battery_voltage: 356.2,
      motor_power_kw: 45.8,
      regen_active: true,
      odometer_km: 12345.6
    }
  end

  test "creates valid record" do
    telemetry = EvTelemetry.create!(@valid_attrs)
    assert telemetry.persisted?
  end

  test "requires vehicle_id" do
    assert_raises(ActiveRecord::RecordInvalid) do
      EvTelemetry.create!(@valid_attrs.merge(vehicle_id: nil))
    end
  end

  test "requires recorded_at" do
    assert_raises(ActiveRecord::RecordInvalid) do
      EvTelemetry.create!(@valid_attrs.merge(recorded_at: nil))
    end
  end

  test "enforces uniqueness on vehicle_id and recorded_at" do
    EvTelemetry.create!(@valid_attrs)

    assert_raises(ActiveRecord::RecordNotUnique) do
      EvTelemetry.create!(@valid_attrs)
    end
  end

  test "allows same vehicle_id with different recorded_at" do
    EvTelemetry.create!(@valid_attrs)
    second = EvTelemetry.create!(@valid_attrs.merge(recorded_at: @valid_attrs[:recorded_at] + 1.second))
    assert second.persisted?
  end
end

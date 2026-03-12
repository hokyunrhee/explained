class CreateEvTelemetries < ActiveRecord::Migration[8.1]
  def change
    create_table :ev_telemetries do |t|
      t.string   :vehicle_id,      null: false
      t.datetime :recorded_at,     null: false
      t.decimal  :latitude,        precision: 10, scale: 6
      t.decimal  :longitude,       precision: 10, scale: 6
      t.decimal  :speed_kmh,       precision: 5,  scale: 1
      t.decimal  :battery_soc_pct, precision: 4,  scale: 1
      t.decimal  :battery_voltage, precision: 4,  scale: 1
      t.decimal  :motor_power_kw,  precision: 5,  scale: 1
      t.boolean  :regen_active
      t.decimal  :odometer_km,     precision: 7,  scale: 1

      t.datetime :created_at, default: -> { "CURRENT_TIMESTAMP" }, null: false
    end

    add_index :ev_telemetries, [:vehicle_id, :recorded_at], unique: true
  end
end

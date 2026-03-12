# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[8.1].define(version: 2026_03_12_220215) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"

  create_table "ev_telemetries", force: :cascade do |t|
    t.decimal "battery_soc_pct", precision: 4, scale: 1
    t.decimal "battery_voltage", precision: 4, scale: 1
    t.datetime "created_at", default: -> { "CURRENT_TIMESTAMP" }, null: false
    t.decimal "latitude", precision: 10, scale: 6
    t.decimal "longitude", precision: 10, scale: 6
    t.decimal "motor_power_kw", precision: 5, scale: 1
    t.decimal "odometer_km", precision: 7, scale: 1
    t.datetime "recorded_at", null: false
    t.boolean "regen_active"
    t.decimal "speed_kmh", precision: 5, scale: 1
    t.string "vehicle_id", null: false
    t.index ["vehicle_id", "recorded_at"], name: "index_ev_telemetries_on_vehicle_id_and_recorded_at", unique: true
  end
end

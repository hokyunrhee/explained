class EvTelemetry < ApplicationRecord
  validates :vehicle_id, :recorded_at, presence: true
end

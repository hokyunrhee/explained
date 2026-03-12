# config/initializers/shoryuken.rb
return if Rails.env.test?

require_relative "../../lib/sqs_client"

Shoryuken.configure_server do |config|
  config.sqs_client = SqsClient.build
  Shoryuken.logger = Rails.logger
end

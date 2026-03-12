# config/initializers/shoryuken.rb

# 테스트 환경에서는 SQS 클라이언트를 생성하지 않음 (Shoryuken::Testing 사용)
return if Rails.env.test?

sqs_client_options = { region: ENV.fetch("AWS_REGION", "us-east-1") }

sqs_client_options[:access_key_id] = ENV.fetch("AWS_ACCESS_KEY_ID", "test")
sqs_client_options[:secret_access_key] = ENV.fetch("AWS_SECRET_ACCESS_KEY", "test")

# ElasticMQ 엔드포인트 (개발 환경 전용)
if ENV["SQS_ENDPOINT"].present? && !Rails.env.production?
  sqs_client_options[:endpoint] = ENV["SQS_ENDPOINT"]
  sqs_client_options[:verify_checksums] = false
end

Shoryuken.configure_server do |config|
  config.sqs_client = Aws::SQS::Client.new(sqs_client_options)
  Shoryuken.logger = Rails.logger
end

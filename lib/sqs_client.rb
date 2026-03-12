# lib/sqs_client.rb
module SqsClient
  def self.build
    options = {
      region: ENV.fetch("AWS_REGION", "ap-northeast-2"),
      access_key_id: ENV.fetch("AWS_ACCESS_KEY_ID", "test"),
      secret_access_key: ENV.fetch("AWS_SECRET_ACCESS_KEY", "test")
    }

    if ENV.fetch("SQS_ENDPOINT", "http://localhost:9324").present? && !Rails.env.production?
      options[:endpoint] = ENV.fetch("SQS_ENDPOINT", "http://localhost:9324")
      options[:verify_checksums] = false
    end

    Aws::SQS::Client.new(options)
  end
end

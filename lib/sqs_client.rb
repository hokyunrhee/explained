# lib/sqs_client.rb
module SqsClient
  def self.build
    options = {
      region: ENV.fetch("AWS_REGION", "us-east-1"),
      access_key_id: ENV.fetch("AWS_ACCESS_KEY_ID", "test"),
      secret_access_key: ENV.fetch("AWS_SECRET_ACCESS_KEY", "test")
    }

    if ENV["SQS_ENDPOINT"].present?
      options[:endpoint] = ENV["SQS_ENDPOINT"]
      options[:verify_checksums] = false
    end

    Aws::SQS::Client.new(options)
  end
end

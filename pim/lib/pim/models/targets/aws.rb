# frozen_string_literal: true

module Pim
  class AwsTarget < Target
    sti_type "aws"

    attribute :region, :string
    attribute :instance_type, :string
    attribute :ami_name_prefix, :string
    attribute :s3_bucket, :string
    attribute :s3_prefix, :string
    attribute :subnet_id, :string
    attribute :security_group_ids, :string
    attribute :iam_role, :string
    attribute :cleanup_s3, :boolean

    def deploy(image, build: nil, **options)
      require_relative "../../services/deployers/aws_deployer"
      deployer = Pim::AwsDeployer.new(target: self, image: image, build: build)
      deployer.deploy(**options)
    end

    def region
      super || 'us-east-1'
    end

    def ami_name_prefix
      super || 'pim'
    end

    def s3_prefix
      super || 'pim-imports/'
    end

    def iam_role
      super || 'vmimport'
    end

    def cleanup_s3
      val = super
      val.nil? ? true : val
    end
  end
end

# frozen_string_literal: true

module Pim
  class ProxmoxTarget < Target
    sti_type "proxmox"

    attribute :host, :string
    attribute :node, :string
    attribute :storage, :string
    attribute :api_token_id, :string
    attribute :api_token_secret, :string
    attribute :vm_id_start, :integer
    attribute :bridge, :string
    attribute :ssh_key, :string

    def deploy(image, build: nil, **options)
      require_relative "../../services/deployers/proxmox_deployer"
      deployer = Pim::ProxmoxDeployer.new(target: self, image: image, build: build)
      deployer.deploy(**options)
    end
  end
end

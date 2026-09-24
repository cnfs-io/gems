# frozen_string_literal: true

module Pcs
  # A machine at the site. Its type (a subclass) says how it's set up; its
  # status says how far along it is:
  #
  #   discovered --key--> keyed --configure--> configured --provision--> provisioned
  #
  # Types installed over PXE (Debian) skip keying: the install lays down the
  # key. Operations do the work and then fire these events; nothing else
  # changes status.
  class Host < FlatRecord::Base
    file_layout :individual
    source "hosts"
    sti_column :type

    HOSTNAME = /\A[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?\z/
    ROLES = %w[cp node].freeze
    ARCHES = %w[amd64 arm64].freeze

    attribute :hostname, :string
    attribute :type, :string
    attribute :role, :string, default: "node"
    attribute :arch, :string, default: "amd64"
    attribute :status, :string
    attribute :site_id, :string
    # Boot the installer, not the disk, when it next PXE boots (set by the
    # install; see PxeTarget). Wipes its disk, so never on by default.
    attribute :pxe_install, :boolean, default: false

    belongs_to :site, class_name: "Pcs::Site"
    before_validation { self.site_id ||= Site.first&.id }
    has_many :interfaces, class_name: "Pcs::Interface", foreign_key: :host_id, dependent: :destroy

    validates :hostname, format: { with: HOSTNAME, message: "must be a lowercase DNS label" }, allow_blank: true
    validates :hostname, uniqueness: true, allow_blank: true
    validates :role, inclusion: { in: ROLES }
    validates :arch, inclusion: { in: ARCHES }
    validates :type, inclusion: { in: ->(_) { Host.types }, message: "is not a known host type" }, allow_nil: true

    # action: :save persists each transition (ActiveModel's integration
    # doesn't by default); an invalid host can't transition.
    state_machine :status, initial: :discovered, action: :save do
      event :key do
        transition discovered: :keyed
      end

      event :configure do
        transition keyed: :configured, if: :configuration_complete?
        transition discovered: :configured, if: ->(host) { !host.requires_key? && host.configuration_complete? }
      end

      event :provision do
        transition configured: :provisioned
      end
    end

    def self.types
      sti_types.keys
    end

    # How a type reads in the UI; subclasses with brand names override it.
    def self.label
      sti_type.to_s.capitalize
    end

    # [[label, type], ...] for choosing a type in forms.
    def self.type_choices
      sti_types.map { |type, klass| [klass.label, type] }
    end

    # [[label, id], ...] for choosing a host in forms.
    def self.choices
      all.map { |host| [host.name, host.id] }
    end

    # The hostname, or where it was found until it has one.
    def name
      hostname.presence || primary_interface&.reachable_ip || "host #{id}"
    end

    # Whether pcs must install its key (over SSH, or by hand for some KVMs)
    # before the host can be configured.
    def requires_key?
      true
    end

    # What's still needed before the host can be configured.
    def missing_configuration
      iface = primary_interface
      {
        type: type,
        hostname: hostname,
        mac: iface&.mac,
        configured_ip: iface&.configured_ip
      }.select { |_, value| value.blank? }.keys
    end

    def configuration_complete?
      missing_configuration.empty?
    end

    def primary_interface
      interfaces.first
    end

    def fqdn
      [hostname, site&.domain].compact.join(".")
    end

    def cp?
      role == "cp"
    end

    # Whether pcs installs this host's OS over PXE.
    def pxe?
      false
    end

    # Who pcs logs in as: the user its installs create, unless the device
    # comes with its own (KVMs log in as root).
    def ssh_user
      Pcs.settings.install.user
    end

    # How to install pcs's key over a password login, as argv; nil when the
    # key is added by hand (in the device's own UI).
    def key_install_command(public_key)
      ["sh", "-c", KEY_INSTALL, "key", public_key]
    end

    # Appends $1 to authorized_keys unless it's already there.
    KEY_INSTALL = <<~SH.tr("\n", " ").strip
      mkdir -p ~/.ssh && chmod 700 ~/.ssh && touch ~/.ssh/authorized_keys &&
      (grep -qxF "$1" ~/.ssh/authorized_keys || echo "$1" >> ~/.ssh/authorized_keys) &&
      chmod 600 ~/.ssh/authorized_keys
    SH
  end
end

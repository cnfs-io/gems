# frozen_string_literal: true

# :nodoc:
module Pcs
  # The site's machines at /hosts, and `pcs hosts list|show|...`.
  class HostsResource < Termino::Resource
    model Host

    field :hostname
    field :type, :select, choices: -> { Host.type_choices }
    field :role, :select, choices: Host::ROLES
    field :arch, :select, choices: Host::ARCHES
    field :status, :state, colors: { "keyed" => :warning, "configured" => :primary, "provisioned" => :success }
    field :disk
    field :pxe_install, :boolean

    # What each state event's button runs, in the background (a job).
    OPERATIONS = {
      "key" => Operations::Key, "configure" => Operations::Configure, "provision" => Operations::Install
    }.freeze

    # Choosing a type makes the host that type (its class, and so its fields
    # and behaviour), saved with the rest of the edit.
    def assign(record, values)
      klass = Host.sti_types[values["type"].to_s]
      record = record.becomes(klass) if klass && !record.instance_of?(klass)
      super
    end

    def event_label(event) = event == "provision" ? "Install" : super

    # Runs the event's operation as a job, and shows its page.
    def fire(record, event)
      request.redirect Termino::JobsResource.record_path(start_job(record, event))
    rescue Termino::Job::Busy => e
      app.flash["alert"] = e.message
      request.redirect self.class.record_path(record)
    end

    # A device's password (for keying) reaches the operation, never the job record.
    def start_job(record, event)
      password = request.params["password"].presence if event == "key"
      Termino::Job.start(OPERATIONS.fetch(event), label: "#{event_label(event)} #{record.name}", subject: record,
                                                  args: { host_id: record.id }, secrets: { password: }.compact)
    end
  end

  App.resource HostsResource
end

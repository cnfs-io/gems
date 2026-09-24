# frozen_string_literal: true

require "rack"

# A host's event buttons, which run its operations as background jobs.
RSpec.describe "host operations on the web" do
  let(:app) { Rack::MockRequest.new(Pcs::App.app) }
  let(:env) { { "HTTP_HOST" => "localhost" } }

  let!(:node) do
    control_plane
    host(Pcs::DebianHost, hostname: "n1", disk: "/dev/sda", configured_ip: "10.0.0.11")
  end

  # Jobs use Pcs.settings: point them at this example's directories, and
  # at a pcm that runs nothing.
  # (and at a pcm and downloader that do nothing), inside a project, so
  # job logs land in its tmp/.
  around do |example|
    @tmpdir.join("config.ru").write("")
    Dir.chdir(@tmpdir) { example.run }
  end

  before do
    Pcs.reset_settings!
    Pcs.instance_variable_set(:@settings, settings)
    allow(Pcs::Adapters::Pcm).to receive(:new).and_return(pcm)
    allow(Pcs::Adapters::Download).to receive(:new).and_return(download)
  end

  after { Pcs.reset_settings! }

  def get(path)
    app.get(path, env).tap { |res| keep_cookie(res) }
  end

  def post(path, form, params = {})
    token = get(form).body.scan(/<form action="([^"]*)".*?name="_csrf" value="([^"]+)"/m).to_h.fetch(path)
    app.post(path, env.merge(params: params.merge("_csrf" => token))).tap { |res| keep_cookie(res) }
  end

  def keep_cookie(res)
    env["HTTP_COOKIE"] = res["set-cookie"][/termino\.session=[^;]+/] if res["set-cookie"]
  end

  def finished(job_id)
    Timeout.timeout(5) do
      loop do
        job = Termino::Job.find(job_id)
        break job unless job.active?

        sleep 0.02
      end
    end
  end

  let(:host_page) { "/hosts/#{node.id}" }

  it "configures a host from its page, as a job with a log" do
    expect(get(host_page).body).to include(%(action="#{host_page}/events/configure"), ">Configure</button>")

    res = post("#{host_page}/events/configure", host_page)
    expect(res.status).to eq(303)
    job_id = res["location"][%r{/jobs/(\d+)\z}, 1]
    job = finished(job_id)

    expect(job).to have_attributes(status: "succeeded", label: "Configure n1", subject: "Pcs::Host/#{node.id}")
    expect(Pcs::Host.find(node.id).status).to eq("configured")
    page = get("/jobs/#{job_id}").body
    expect(page).to include("succeeded", "→ mark n1 configured", "MAC-aabbcc000001.ipxe")
    jobs = get("/jobs").body
    expect(jobs).to include("Configure n1")
    expect(jobs).not_to include("New job")

    expect(get(host_page).body).to include(">Install</button>")
  end

  it "runs one job at a time for a host, and refreshes a running job's page" do
    Termino::Job.create!(label: "Install n1", operation: "Pcs::Operations::Install", status: "running",
                         subject: "Pcs::Host/#{node.id}")
    post("#{host_page}/events/configure", host_page)
    expect(get(host_page).body).to include("Install n1 is still running")

    expect(get("/jobs/1")["refresh"]).to eq("2")
  end
end

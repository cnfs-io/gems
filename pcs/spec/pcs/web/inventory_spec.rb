# frozen_string_literal: true

require "rack"

# The inventory pages, requested the way a browser would.
RSpec.describe "inventory pages" do
  let(:app) { Rack::MockRequest.new(Pcs::App.app) }
  let(:env) { { "HTTP_HOST" => "localhost" } }

  def get(path)
    app.get(path, env).tap { |res| keep_cookie(res) }
  end

  # Submits the form at `form` to `path`, with the page's CSRF token.
  def post(path, form, params)
    token = get(form).body.scan(/<form action="([^"]*)".*?name="_csrf" value="([^"]+)"/m).to_h.fetch(path)
    app.post(path, env.merge(params: params.merge("_csrf" => token))).tap { |res| keep_cookie(res) }
  end

  def keep_cookie(res)
    env["HTTP_COOKIE"] = res["set-cookie"][/termino\.session=[^;]+/] if res["set-cookie"]
  end

  it "shows the site and its hosts, with their state and interfaces" do
    h = host(Pcs::DebianHost, hostname: "n1", status: "provisioned")

    expect(get("/").body).to include("sg.lan", "Hosts provisioned", 'href="/networks"')
    expect(get("/hosts").body).to include("n1", "Debian", "text-success")
    expect(get("/hosts/#{h.id}").body).to include("aa:bb:cc:00:00:01", "primary")
    expect(get("/networks/#{network.id}").body).to include(">n1</a>")
  end

  it "changes a host's type, and so its fields" do
    h = host(hostname: "n1")
    expect(get("/hosts/#{h.id}/edit").body).not_to include('name="disk"')

    res = post("/hosts/#{h.id}", "/hosts/#{h.id}/edit", "hostname" => "n1", "type" => "debian", "role" => "node",
                                                        "arch" => "amd64", "disk" => "/dev/sda")
    expect(res.status).to eq(303)
    expect(Pcs::Host.find(h.id)).to have_attributes(class: Pcs::DebianHost, disk: "/dev/sda", status: "discovered")
    expect(get("/hosts/#{h.id}").body).to include("To configure: set configured ip, control plane ip.")
  end

  it "doesn't take the status from a form" do
    h = host(hostname: "n1")
    post("/hosts/#{h.id}", "/hosts/#{h.id}/edit", "hostname" => "n1", "role" => "node", "arch" => "amd64",
                                                  "status" => "provisioned")
    expect(Pcs::Host.find(h.id).status).to eq("discovered")
  end
end

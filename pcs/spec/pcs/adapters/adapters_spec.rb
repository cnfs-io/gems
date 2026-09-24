# frozen_string_literal: true

RSpec.describe Pcs::Adapters::SystemCmd do
  it "passes arguments as argv, never through a shell" do
    result = described_class.new.run("echo", "$HOME; rm -rf /")
    expect(result.stdout).to eq("$HOME; rm -rf /\n")
  end

  it "reports failures and missing programs" do
    expect(described_class.new.run("false")).not_to be_success
    expect(described_class.new.run("no-such-program-xyz").status).to eq(127)
    expect { described_class.new.run!("false") }.to raise_error(Pcs::Adapters::SystemCmd::Failed, /`false` failed/)
  end
end

RSpec.describe Pcs::Adapters::Nmap do
  let(:xml) { File.read(File.join(__dir__, "..", "..", "fixtures", "nmap.xml")) }

  it "ping-scans with sudo (for MACs) and parses the hosts that are up" do
    system = FakeSystem.new.on("sudo", stdout: xml)
    found = described_class.new(system:).scan("10.0.0.0/24")

    expect(system.commands).to eq([%w[sudo -n nmap -sn -oX - 10.0.0.0/24]])
    expect(found.map(&:to_h)).to eq([
                                      { ip: "10.0.0.1", mac: "d8:3a:dd:11:22:33", vendor: "Raspberry Pi Trading",
                                        hostname: "router.lan" },
                                      { ip: "10.0.0.50", mac: "aa:bb:cc:00:00:01", vendor: nil, hostname: nil },
                                      { ip: "10.0.0.2", mac: nil, vendor: nil, hostname: nil }
                                    ])
  end

  it "says what to do when it can't run" do
    system = FakeSystem.new.on("sudo", stderr: "sudo: a password is required", status: 1)
    expect { described_class.new(system:).scan("10.0.0.0/24") }
      .to raise_error(Pcs::Error, /allow passwordless sudo for nmap.*scan.sudo = false/)

    system = FakeSystem.new.on("nmap", stderr: "No such file or directory - nmap", status: 127)
    expect { described_class.new(system:, sudo: false).scan("10.0.0.0/24") }.to raise_error(Pcs::Error, /install nmap/)
  end

  it "can run without sudo" do
    system = FakeSystem.new.on("nmap", stdout: "<nmaprun/>")
    described_class.new(system:, sudo: false).scan("10.0.0.0/24")
    expect(system.commands.first.first).to eq("nmap")
  end
end

RSpec.describe Pcs::Adapters::Pcm do
  it "drives pcm with argv" do
    system = FakeSystem.new.on("pcm", "ps", stdout: "dnsmasq-dnsmasq-1\n")
    pcm = described_class.new(system:)
    pcm.up("dnsmasq")
    pcm.restart("dnsmasq")
    expect(pcm.running?("dnsmasq")).to be(true)
    expect(system.commands).to eq([
                                    %w[pcm up dnsmasq],
                                    %w[pcm __compose restart dnsmasq],
                                    ["pcm", "ps", "--filter", "label=com.docker.compose.project=dnsmasq", "--format",
                                     "{{.Names}}"]
                                  ])
  end

  it "isn't running when pcm lists nothing" do
    expect(described_class.new(system: FakeSystem.new.on("pcm", "ps", stdout: "")).running?("netboot")).to be(false)
  end
end

RSpec.describe Pcs::Adapters::Ssh do
  it "quotes argv for the remote shell" do
    expect(described_class.command(["echo", "a b", "$(reboot)"])).to eq("echo a\\ b \\$\\(reboot\\)")
  end

  it "isn't reachable when nothing answers" do
    ssh = described_class.new(host: "127.0.0.1", port: 1, user: "pcs", key_path: "/nonexistent",
                              known_hosts: @tmpdir.join("known_hosts").to_s, timeout: 2)
    expect(ssh.reachable?).to be(false)
  end
end

# frozen_string_literal: true

RSpec.describe Pcs::Commands::NewSite do
  let(:local) do
    Module.new do
      module_function

      def interfaces
        [Pcs::Local::Iface.new("eth0", "10.0.0.2", 24, "d8:3a:dd:11:22:33"),
         Pcs::Local::Iface.new("wlan0", "10.0.5.7", 24, nil)]
      end

      def hostname = "cp1"
      def arch = "arm64"
      def timezone = "Asia/Singapore"
    end
  end

  let(:command) do
    fake = local
    Class.new(described_class) { define_method(:local) { fake } }.for(Pcs).new
  end

  it "creates the site, its networks and this machine as its control plane" do
    Dir.chdir(@tmpdir) do
      expect { command.call(name: "sg") }.to output(%r{network primary: 10\.0\.0\.0/24.*control plane: cp1}m).to_stdout
    end
    project = @tmpdir.join("sg")
    expect(project.join("pcs.rb").read).to include("Pcs.configure")

    FlatRecord.configure { |c| c.data_path = project.join("data").to_s }
    site = Pcs::Site.current
    expect(site).to have_attributes(name: "sg", domain: "sg.lan", timezone: "Asia/Singapore")
    expect(Pcs::Network.pluck(:name, :subnet, :primary)).to eq([["primary", "10.0.0.0/24", true],
                                                                ["wlan0", "10.0.5.0/24", false]])
    cp = Pcs::Host.find_by!(role: "cp")
    expect(cp).to have_attributes(class: Pcs::DebianHost, hostname: "cp1", arch: "arm64", status: "provisioned")
    expect(cp.interfaces.pluck(:name, :configured_ip, :mac))
      .to eq([["eth0", "10.0.0.2", "d8:3a:dd:11:22:33"], ["wlan0", "10.0.5.7", nil]])
  end

  it "takes the domain and timezone as options" do
    Dir.chdir(@tmpdir) do
      expect do
        command.call(name: "rok", domain: "rok.example", timezone: "UTC")
      end.to output.to_stdout
    end
    FlatRecord.configure { |c| c.data_path = @tmpdir.join("rok", "data").to_s }
    expect(Pcs::Site.current).to have_attributes(domain: "rok.example", timezone: "UTC")
  end
end

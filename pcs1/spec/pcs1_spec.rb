# frozen_string_literal: true

RSpec.describe Pcs1 do
  it "has a version number" do
    expect(Pcs1::VERSION).not_to be_nil
  end

  describe ".root" do
    it "returns the test project directory" do
      expect(Pcs1.root).to eq(Pathname.new(test_dir))
    end
  end

  describe ".configure" do
    it "yields the config object" do
      Pcs1.configure do |c|
        c.log_level = :debug
      end
      expect(Pcs1.config.log_level).to eq(:debug)
    end
  end

  describe ".reset!" do
    it "clears cached state" do
      _root = Pcs1.root
      _config = Pcs1.config
      Pcs1.reset!
      # After reset, accessing root triggers find_root again
      expect(Pcs1.instance_variable_get(:@root)).to be_nil
      expect(Pcs1.instance_variable_get(:@config)).to be_nil
      expect(Pcs1.instance_variable_get(:@site)).to be_nil
    end
  end

  describe ".resolve_template" do
    it "finds gem templates" do
      path = Pcs1.resolve_template("dnsmasq.conf.erb")
      expect(path).to exist
      expect(path.to_s).to include("templates/dnsmasq.conf.erb")
    end

    it "prefers project templates over gem templates" do
      project_template = Pathname.new(test_dir) / "templates" / "dnsmasq.conf.erb"
      FileUtils.mkdir_p(project_template.dirname)
      File.write(project_template, "custom")

      path = Pcs1.resolve_template("dnsmasq.conf.erb")
      expect(path.to_s).to start_with(test_dir)
    end

    it "raises for missing templates" do
      expect { Pcs1.resolve_template("nonexistent.erb") }.to raise_error(Pcs1::Error)
    end
  end
end

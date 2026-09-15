# frozen_string_literal: true

RSpec.describe "Global config (~/.config/pim/pim.rb)" do
  let(:global_path) { Pim.global_config_path }

  after do
    FileUtils.rm_f(global_path)
    Pim.reset!
  end

  it "lives under XDG_CONFIG_HOME" do
    expect(global_path).to eq(File.join(ENV["XDG_CONFIG_HOME"], "pim", "pim.rb"))
  end

  it "is loaded before the project's pim.rb, which wins" do
    FileUtils.mkdir_p(File.dirname(global_path))
    File.write(global_path, <<~RUBY)
      Pim.configure do |config|
        config.vm do |vm|
          vm.network = "host"
          vm.usb = ["058f:6387"]
        end
      end
    RUBY

    Dir.mktmpdir do |dir|
      FileUtils.mkdir_p(File.join(dir, "data"))
      File.write(File.join(dir, "pim.rb"), 'Pim.configure { |c| c.vm { |vm| vm.network = "bridged" } }')
      Pim.boot!(project_dir: dir)
    end

    expect(Pim.config.vm.network).to eq("bridged")
    expect(Pim.config.vm.usb).to eq(["058f:6387"])
  end

  it "is optional" do
    Dir.mktmpdir do |dir|
      FileUtils.mkdir_p(File.join(dir, "data"))
      File.write(File.join(dir, "pim.rb"), "Pim.configure { |c| }\n")
      expect { Pim.boot!(project_dir: dir) }.not_to raise_error
    end

    expect(Pim.config.vm.disk).to eq("clone")
  end
end

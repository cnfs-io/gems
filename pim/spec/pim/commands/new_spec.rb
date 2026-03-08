# frozen_string_literal: true

RSpec.describe Pim::Commands::New do
  let(:tmp_dir) { Dir.mktmpdir }

  after { FileUtils.remove_entry(tmp_dir) }

  it "creates a project directory" do
    Dir.chdir(tmp_dir) do
      expect { subject.call(name: "testproj") }.to output.to_stdout
      expect(Dir.exist?(File.join(tmp_dir, "testproj"))).to be true
      expect(File.exist?(File.join(tmp_dir, "testproj", "pim.rb"))).to be true
    end
  end
end

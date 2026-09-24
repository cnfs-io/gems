# frozen_string_literal: true

RSpec.describe Pim::ScriptLoader do
  let(:project_dir) { Dir.mktmpdir }
  let(:scripts_dir) { File.join(project_dir, "resources", "scripts") }

  subject { described_class.new(project_dir: project_dir) }

  before do
    FileUtils.mkdir_p(File.join(scripts_dir, "fedora"))
    File.write(File.join(scripts_dir, "base.sh"), "debian base")
    File.write(File.join(scripts_dir, "finalize.sh"), "debian finalize")
    File.write(File.join(scripts_dir, "fedora", "base.sh"), "fedora base")
  end

  after { FileUtils.remove_entry(project_dir) }

  it "prefers the distro's script, falling back to the shared one" do
    expect(subject.resolve_scripts(%w[base finalize], distro: "fedora")).to eq([
      File.join(scripts_dir, "fedora", "base.sh"),
      File.join(scripts_dir, "finalize.sh")
    ])
  end

  it "uses the shared scripts without a distro" do
    expect(subject.find_script("base")).to eq(File.join(scripts_dir, "base.sh"))
  end

  it "raises for a missing script" do
    expect { subject.resolve_scripts(%w[nope], distro: "fedora") }.to raise_error(/Script not found: nope.sh/)
  end
end

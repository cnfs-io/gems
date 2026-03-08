# frozen_string_literal: true

RSpec.describe Pim::Build do
  describe "scaffold defaults" do
    let!(:project_dir) { TestProject.create_and_boot }

    after { TestProject.cleanup(project_dir) }

    it "returns all build recipes" do
      builds = described_class.all
      expect(builds.map(&:id)).to include("default")
    end

    it "returns build by id" do
      build = described_class.find("default")
      expect(build.profile).to eq("default")
      expect(build.iso).to eq("debian-13-amd64")
      expect(build.distro).to eq("debian")
    end

    it "raises RecordNotFound for unknown id" do
      expect { described_class.find("nonexistent") }.to raise_error(FlatRecord::RecordNotFound)
    end

    it "returns empty array when no builds.yml exists" do
      TestProject.write_records(project_dir, "builds", [])
      TestProject.boot(project_dir)
      expect(described_class.all).to eq([])
    end
  end

  describe "associations" do
    let!(:project_dir) { TestProject.create }

    after { TestProject.cleanup(project_dir) }

    before do
      TestProject.write_records(project_dir, "profiles", [
        { "id" => "default", "hostname" => "debian", "username" => "ansible", "password" => "changeme" },
        { "id" => "dev", "parent_id" => "default", "packages" => "vim git" }
      ])
      TestProject.write_records(project_dir, "isos", [
        { "id" => "debian-12", "name" => "Debian 12", "url" => "https://example.com/debian.iso",
          "architecture" => "amd64", "checksum" => "sha256:abc123" }
      ])
      TestProject.write_records(project_dir, "builds", [
        { "id" => "dev-debian", "profile" => "dev", "iso" => "debian-12", "distro" => "debian" },
        { "id" => "dev-fedora", "profile" => "dev", "iso" => "debian-12", "distro" => "fedora",
          "disk_size" => "40G", "memory" => 4096, "cpus" => 4 }
      ])
      TestProject.boot(project_dir)
    end

    describe "#resolved_profile" do
      it "returns the Profile with parent chain resolved" do
        build = described_class.find("dev-debian")
        profile = build.resolved_profile
        expect(profile).to be_a(Pim::Profile)
        expect(profile.id).to eq("dev")
        expect(profile.to_h["hostname"]).to eq("debian")
        expect(profile.to_h["packages"]).to eq("vim git")
      end
    end

    describe "#resolved_iso" do
      it "returns the Iso record" do
        build = described_class.find("dev-debian")
        iso = build.resolved_iso
        expect(iso).to be_a(Pim::Iso)
        expect(iso.id).to eq("debian-12")
      end
    end

    describe "#resolved_target" do
      it "returns the Target subclass instance when target is set" do
        TestProject.append_records(project_dir, "targets", [
          { "id" => "proxmox-sg", "type" => "proxmox", "host" => "192.168.1.100" }
        ])
        TestProject.write_records(project_dir, "builds", [
          { "id" => "dev-debian", "profile" => "dev", "iso" => "debian-12", "distro" => "debian", "target" => "proxmox-sg" }
        ])
        TestProject.boot(project_dir)

        build = described_class.find("dev-debian")
        target = build.resolved_target
        expect(target).to be_a(Pim::ProxmoxTarget)
        expect(target.host).to eq("192.168.1.100")
      end

      it "returns nil when no target is set" do
        TestProject.write_records(project_dir, "builds", [
          { "id" => "dev-debian", "profile" => "dev", "iso" => "debian-12", "distro" => "debian" }
        ])
        TestProject.boot(project_dir)
        build = described_class.find("dev-debian")
        expect(build.resolved_target).to be_nil
      end
    end
  end

  describe "build behavior" do
    let!(:project_dir) { TestProject.create }

    after { TestProject.cleanup(project_dir) }

    before do
      TestProject.write_records(project_dir, "profiles", [
        { "id" => "default", "hostname" => "debian", "username" => "ansible", "password" => "changeme" },
        { "id" => "dev", "parent_id" => "default", "packages" => "vim git" }
      ])
      TestProject.write_records(project_dir, "isos", [
        { "id" => "debian-12", "name" => "Debian 12", "url" => "https://example.com/debian.iso",
          "architecture" => "amd64", "checksum" => "sha256:abc123" }
      ])
      TestProject.write_records(project_dir, "builds", [
        { "id" => "dev-debian", "profile" => "dev", "iso" => "debian-12", "distro" => "debian" },
        { "id" => "dev-fedora", "profile" => "dev", "iso" => "debian-12", "distro" => "fedora",
          "disk_size" => "40G", "memory" => 4096, "cpus" => 4 }
      ])
      TestProject.boot(project_dir)
    end

    describe "#arch" do
      it "defaults to host architecture when not set" do
        build = described_class.find("dev-debian")
        expect(build.arch).to eq(Pim::ArchitectureResolver.new.host_arch)
      end

      it "returns configured arch when set" do
        TestProject.append_records(project_dir, "builds", [
          { "id" => "cross-build", "profile" => "dev", "iso" => "debian-12", "distro" => "debian", "arch" => "x86_64" }
        ])
        TestProject.boot(project_dir)

        build = described_class.find("cross-build")
        expect(build.arch).to eq("x86_64")
      end
    end

    describe "#build_method" do
      it "defaults to 'qemu'" do
        build = described_class.find("dev-debian")
        expect(build.build_method).to eq("qemu")
      end
    end

    describe "#automation" do
      it "infers preseed for debian" do
        build = described_class.find("dev-debian")
        expect(build.automation).to eq("preseed")
      end

      it "infers kickstart for fedora" do
        build = described_class.find("dev-fedora")
        expect(build.automation).to eq("kickstart")
      end

      it "returns explicit automation when set" do
        TestProject.append_records(project_dir, "builds", [
          { "id" => "cloud", "profile" => "dev", "iso" => "debian-12", "distro" => "ubuntu", "automation" => "cloud-init" }
        ])
        TestProject.boot(project_dir)

        expect(described_class.find("cloud").automation).to eq("cloud-init")
      end
    end

    describe "build config overrides" do
      it "exposes disk_size, memory, cpus overrides" do
        build = described_class.find("dev-fedora")
        expect(build.disk_size).to eq("40G")
        expect(build.memory).to eq(4096)
        expect(build.cpus).to eq(4)
      end

      it "returns defaults for unset overrides" do
        build = described_class.find("dev-debian")
        expect(build.disk_size).to eq("20G")
        expect(build.memory).to eq(2048)
        expect(build.cpus).to eq(2)
      end
    end

    describe "defaults" do
      it "defaults ssh_user to ansible" do
        build = described_class.find("dev-debian")
        expect(build.ssh_user).to eq("ansible")
      end

      it "defaults ssh_timeout to 1800" do
        build = described_class.find("dev-debian")
        expect(build.ssh_timeout).to eq(1800)
      end

      it "allows overriding ssh_user" do
        TestProject.append_records(project_dir, "builds", [
          { "id" => "custom", "profile" => "dev", "iso" => "debian-12", "distro" => "debian", "ssh_user" => "root" }
        ])
        TestProject.boot(project_dir)

        build = described_class.find("custom")
        expect(build.ssh_user).to eq("root")
      end

      it "allows overriding ssh_timeout" do
        TestProject.append_records(project_dir, "builds", [
          { "id" => "custom", "profile" => "dev", "iso" => "debian-12", "distro" => "debian", "ssh_timeout" => 600 }
        ])
        TestProject.boot(project_dir)

        build = described_class.find("custom")
        expect(build.ssh_timeout).to eq(600)
      end
    end
  end
end

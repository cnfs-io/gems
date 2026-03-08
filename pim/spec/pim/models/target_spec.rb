# frozen_string_literal: true

RSpec.describe Pim::Target do
  describe "scaffold defaults" do
    let!(:project_dir) { TestProject.create_and_boot }

    after { TestProject.cleanup(project_dir) }

    it "returns all targets" do
      expect(described_class.all.map(&:id)).to include("local")
    end

    it "returns target by id" do
      target = described_class.find("local")
      expect(target.type).to eq("local")
    end

    it "raises RecordNotFound for unknown id" do
      expect { described_class.find("nonexistent") }.to raise_error(FlatRecord::RecordNotFound)
    end

    it "returns empty array when no targets exist" do
      TestProject.write_records(project_dir, "targets", [])
      TestProject.boot(project_dir)
      expect(described_class.all).to eq([])
    end
  end

  describe "STI and subclass behavior" do
    let!(:project_dir) { TestProject.create }

    after { TestProject.cleanup(project_dir) }

    before do
      TestProject.write_records(project_dir, "targets", [
        { "id" => "local", "type" => "local" },
        { "id" => "proxmox", "type" => "proxmox", "host" => "192.168.1.100", "node" => "pve1", "storage" => "local-lvm" },
        { "id" => "proxmox-dev", "type" => "proxmox", "parent_id" => "proxmox", "node" => "pve-dev", "name" => "Dev PVE" },
        { "id" => "aws-us", "type" => "aws", "region" => "us-east-1", "instance_type" => "t3.medium" }
      ])
      TestProject.boot(project_dir)
    end

    describe "STI type resolution" do
      it "returns LocalTarget for type=local" do
        expect(described_class.find("local")).to be_a(Pim::LocalTarget)
      end

      it "returns ProxmoxTarget for type=proxmox" do
        expect(described_class.find("proxmox")).to be_a(Pim::ProxmoxTarget)
      end

      it "returns AwsTarget for type=aws" do
        expect(described_class.find("aws-us")).to be_a(Pim::AwsTarget)
      end

      it "Target.all returns mixed subclass instances" do
        classes = described_class.all.map(&:class).uniq
        expect(classes).to include(Pim::LocalTarget, Pim::ProxmoxTarget, Pim::AwsTarget)
      end
    end

    describe "subclass-specific attributes" do
      it "ProxmoxTarget has host, node, storage" do
        target = described_class.find("proxmox")
        expect(target.host).to eq("192.168.1.100")
        expect(target.node).to eq("pve1")
        expect(target.storage).to eq("local-lvm")
      end

      it "AwsTarget has region, instance_type" do
        target = described_class.find("aws-us")
        expect(target.region).to eq("us-east-1")
        expect(target.instance_type).to eq("t3.medium")
      end
    end

    describe "scoped queries" do
      it "ProxmoxTarget.all returns only proxmox targets" do
        proxmox = Pim::ProxmoxTarget.all
        expect(proxmox.map(&:id)).to contain_exactly("proxmox", "proxmox-dev")
      end

      it "AwsTarget.all returns only aws targets" do
        aws = Pim::AwsTarget.all
        expect(aws.map(&:id)).to contain_exactly("aws-us")
      end

      it "LocalTarget.all returns only local targets" do
        local = Pim::LocalTarget.all
        expect(local.map(&:id)).to contain_exactly("local")
      end
    end

    describe "parent_id inheritance" do
      it "parent returns the parent target" do
        child = described_class.find("proxmox-dev")
        expect(child.parent.id).to eq("proxmox")
      end

      it "parent returns nil when no parent_id" do
        root = described_class.find("proxmox")
        expect(root.parent).to be_nil
      end

      it "parent_chain returns root to self" do
        child = described_class.find("proxmox-dev")
        chain = child.parent_chain
        expect(chain.map(&:id)).to eq(["proxmox", "proxmox-dev"])
      end

      it "resolved_attributes merges parent attributes" do
        child = described_class.find("proxmox-dev")
        attrs = child.resolved_attributes
        expect(attrs["host"]).to eq("192.168.1.100")
        expect(attrs["storage"]).to eq("local-lvm")
        expect(attrs["node"]).to eq("pve-dev")
        expect(attrs["name"]).to eq("Dev PVE")
      end

      it "to_h returns resolved attributes" do
        child = described_class.find("proxmox-dev")
        h = child.to_h
        expect(h["host"]).to eq("192.168.1.100")
        expect(h["node"]).to eq("pve-dev")
      end

      it "raw_to_h returns only direct attributes" do
        child = described_class.find("proxmox-dev")
        raw = child.raw_to_h
        expect(raw).not_to have_key("host")
        expect(raw["node"]).to eq("pve-dev")
      end

      it "detects circular parent_id references" do
        TestProject.write_records(project_dir, "targets", [
          { "id" => "a", "type" => "local", "parent_id" => "b" },
          { "id" => "b", "type" => "local", "parent_id" => "a" }
        ])
        TestProject.boot(project_dir)

        expect { described_class.find("a").parent_chain }.to raise_error(/Circular/)
      end
    end

    describe "#deploy" do
      it "LocalTarget#deploy returns true" do
        target = described_class.find("local")
        expect(target.deploy("/some/path.qcow2")).to be true
      end

      it "ProxmoxTarget#deploy delegates to ProxmoxDeployer" do
        target = described_class.find("proxmox")
        image = instance_double(Pim::Image, exists?: false, id: 'test', path: '/tmp/test.qcow2')
        expect { target.deploy(image) }.to raise_error(Pim::ProxmoxDeployer::Error, /Image file missing/)
      end

      it "AwsTarget#deploy delegates to AwsDeployer" do
        target = described_class.find("aws-us")
        image = instance_double(Pim::Image, exists?: false, id: 'test', path: '/tmp/test.qcow2')
        expect { target.deploy(image) }.to raise_error(Pim::AwsDeployer::Error, /Image file missing/)
      end
    end
  end
end

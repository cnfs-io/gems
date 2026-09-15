# frozen_string_literal: true

RSpec.describe "Pim::Iso.parse_checksum" do
  let(:hash_a) { "a" * 64 }
  let(:hash_b) { "B" * 64 }

  def parse(body, filename)
    Pim::Iso.parse_checksum(body, filename)
  end

  it "reads sha256sum text mode (hash  file)" do
    body = "#{hash_a}  debian-13.7.0-amd64-netinst.iso\n#{hash_b}  debian-edu.iso\n"
    expect(parse(body, "debian-edu.iso")).to eq("b" * 64)
  end

  it "reads sha256sum binary mode (hash *file)" do
    body = "#{hash_a} *ubuntu-26.04-live-server-amd64.iso\n#{hash_b} *ubuntu-26.04.1-live-server-amd64.iso\n"
    expect(parse(body, "ubuntu-26.04.1-live-server-amd64.iso")).to eq("b" * 64)
  end

  it "reads BSD style inside a PGP-signed file" do
    body = <<~SUMS
      -----BEGIN PGP SIGNED MESSAGE-----
      Hash: SHA256

      # Fedora-Workstation-Live-44-1.7.x86_64.iso: 2851612672 bytes
      SHA256 (Fedora-Workstation-Live-44-1.7.x86_64.iso) = #{hash_a}
      -----BEGIN PGP SIGNATURE-----
    SUMS
    expect(parse(body, "Fedora-Workstation-Live-44-1.7.x86_64.iso")).to eq(hash_a)
  end

  it "accepts a file holding only the hash, without a trailing newline" do
    expect(parse(hash_b, "TrueNAS-SCALE-25.10.7.iso")).to eq("b" * 64)
  end

  it "returns nil when the file is not listed" do
    body = "#{hash_a}  one.iso\n#{hash_b}  two.iso\n"
    expect(parse(body, "three.iso")).to be_nil
  end

  it "does not guess among several bare hashes" do
    expect(parse("#{hash_a}\n#{hash_b}\n", "x.iso")).to be_nil
  end
end

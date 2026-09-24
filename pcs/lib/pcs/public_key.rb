# frozen_string_literal: true

module Pcs
  # The public half of pcs's SSH key, the only key material that ever leaves
  # the control plane (it goes into preseeds and authorized_keys).
  module PublicKey
    FORMAT = %r{\A(ssh-ed25519|ssh-rsa|ecdsa-sha2-nistp\d+|sk-\S+@openssh\.com) [A-Za-z0-9+/]+={0,3}\z}

    module_function

    # "<type> <key> pcs" from key_path (the private key's path, or the .pub
    # itself). Refuses anything that isn't a single public key.
    def read(key_path)
      path = key_path.to_s.end_with?(".pub") ? key_path.to_s : "#{key_path}.pub"
      raise Pcs::Error, "no public key at #{path} (ssh-keygen -t ed25519 creates one)" unless File.exist?(path)

      text = File.read(path)
      raise Pcs::Error, "#{path} holds a private key" if text.include?("PRIVATE KEY")

      key = text.strip.split[0, 2].join(" ")
      raise Pcs::Error, "#{path} isn't an SSH public key" unless key.match?(FORMAT)

      "#{key} pcs"
    end
  end
end

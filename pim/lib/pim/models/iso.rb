# frozen_string_literal: true

require 'pathname'
require 'digest'
require 'net/http'
require 'openssl'

module Pim
  class Iso < FlatRecord::Base
    source "isos"
    merge_strategy :deep_merge

    attribute :name, :string
    attribute :url, :string
    attribute :checksum, :string
    attribute :checksum_url, :string
    attribute :filename, :string
    attribute :architecture, :string

    # --- Operations ---

    def download(force: false)
      filepath = iso_path

      if filepath.exist? && !force
        print "File exists. Re-download? (y/N) "
        response = $stdin.gets.chomp
        return false unless response.downcase == 'y'
      end

      filepath.dirname.mkpath
      puts "Downloading #{resolved_filename}..."
      Pim::HTTP.download(url, filepath.to_s)
      puts 'Verifying checksum...'
      verify
    end

    def verify(silent: false)
      filepath = iso_path

      unless filepath.exist?
        puts "Error: File '#{resolved_filename}' not found in #{iso_dir}" unless silent
        return false
      end

      expected = resolved_checksum
      unless expected
        puts "Error: No checksum available for #{resolved_filename}" unless silent
        return false
      end

      puts "Verifying #{resolved_filename}..." unless silent
      actual = Digest::SHA256.file(filepath).hexdigest

      if actual == expected
        puts "OK Checksum matches: sha256:#{actual[0..15]}..." unless silent
        true
      else
        puts "FAIL Checksum mismatch!" unless silent
        puts "  Expected: sha256:#{expected[0..15]}..." unless silent
        puts "  Got:      sha256:#{actual[0..15]}..." unless silent
        false
      end
    end

    # Returns the SHA256 checksum string.
    # Uses inline `checksum` if present, otherwise downloads and parses `checksum_url`.
    def resolved_checksum
      if checksum && !checksum.to_s.strip.empty?
        checksum.to_s.sub('sha256:', '')
      elsif checksum_url && !checksum_url.to_s.strip.empty?
        fetch_checksum_from_url
      end
    end

    def downloaded?
      iso_path.exist?
    end

    def iso_path
      iso_dir / resolved_filename
    end

    def to_h
      attributes.compact
    end

    private

    def resolved_filename
      filename || "#{id}.iso"
    end

    def iso_dir
      Pathname.new(File.join(Pim::XDG_CACHE_HOME, 'pim', 'isos'))
    end

    def fetch_checksum_from_url
      uri = URI.parse(checksum_url)
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = (uri.scheme == 'https')
      http.verify_mode = OpenSSL::SSL::VERIFY_PEER if http.use_ssl?

      response = http.get(uri.request_uri)
      raise "Failed to fetch checksums: #{response.code}" unless response.is_a?(Net::HTTPSuccess)

      target = resolved_filename
      response.body.each_line do |line|
        hash, name = line.strip.split(/\s+/, 2)
        return hash if name&.strip == target
      end

      nil
    end
  end
end

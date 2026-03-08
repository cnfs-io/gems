# frozen_string_literal: true

require 'net/http'
require 'uri'
require 'openssl'
require 'digest'

module Pim
  module HTTP
    # Download a file with redirect following and progress reporting
    def self.download(url, destination, redirect_limit: 5)
      raise 'Too many redirects' if redirect_limit == 0

      uri = URI.parse(url)
      http = Net::HTTP.new(uri.host, uri.port)
      if uri.scheme == 'https'
        http.use_ssl = true
        http.verify_mode = OpenSSL::SSL::VERIFY_PEER
      end

      http.start do
        request = Net::HTTP::Get.new(uri.request_uri)
        http.request(request) do |response|
          case response
          when Net::HTTPRedirection
            return download(response['location'], destination, redirect_limit: redirect_limit - 1)
          when Net::HTTPSuccess
            total_size = response['content-length'].to_i
            downloaded = 0
            File.open(destination, 'wb') do |file|
              response.read_body do |chunk|
                file.write(chunk)
                downloaded += chunk.size
                if total_size > 0
                  percentage = (downloaded.to_f / total_size * 100).round(1)
                  print "\rProgress: #{format_bytes(downloaded)} / #{format_bytes(total_size)} (#{percentage}%)"
                else
                  print "\rDownloaded: #{format_bytes(downloaded)}"
                end
              end
            end
            puts
          else
            raise "HTTP Error: #{response.code} #{response.message}"
          end
        end
      end
    end

    # Verify SHA256 checksum of a file
    def self.verify_checksum(filepath, expected_checksum)
      expected = expected_checksum.to_s.sub(/^sha256:/, '')
      actual = Digest::SHA256.file(filepath).hexdigest
      actual == expected
    end

    def self.format_bytes(bytes)
      units = ['B', 'KB', 'MB', 'GB', 'TB']
      return '0 B' if bytes == 0

      exp = (Math.log(bytes) / Math.log(1024)).floor
      exp = [exp, units.size - 1].min
      format('%.2f %s', bytes.to_f / (1024**exp), units[exp])
    end

  end
end

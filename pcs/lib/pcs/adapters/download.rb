# frozen_string_literal: true

require "fileutils"
require "net/http"
require "uri"

module Pcs
  module Adapters
    # Fetches a URL to a file, following redirects. The file appears only
    # once the download is complete (it's written beside it, then renamed).
    class Download
      REDIRECTS = 5

      def call(url, path)
        FileUtils.mkdir_p(File.dirname(path))
        partial = "#{path}.part"
        fetch(URI(url), partial)
        File.rename(partial, path)
        path
      ensure
        FileUtils.rm_f(partial) if partial
      end

      private

      def fetch(uri, path, redirects = REDIRECTS)
        Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == "https") do |http|
          http.request(Net::HTTP::Get.new(uri)) do |response|
            next save(response, path) if response.is_a?(Net::HTTPSuccess)

            return fetch(redirect(uri, response, redirects), path, redirects - 1)
          end
        end
      end

      # Where a redirect points, or an error for any other response.
      def redirect(uri, response, redirects)
        unless response.is_a?(Net::HTTPRedirection)
          raise Pcs::Error, "couldn't fetch #{uri}: #{response.code} #{response.message}"
        end
        raise Pcs::Error, "too many redirects fetching #{uri}" if redirects.zero?

        URI.join(uri, response["location"])
      end

      def save(response, path)
        File.open(path, "wb") { |file| response.read_body { |chunk| file.write(chunk) } }
      end
    end
  end
end

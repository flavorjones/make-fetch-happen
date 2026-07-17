module ArtifactUrl
  def self.normalize(url)
    return nil if url.blank?
    uri = URI.parse(url.strip)
    return nil unless uri.is_a?(URI::HTTP)
    uri.scheme = "https"
    uri.fragment = nil
    uri.path = uri.path.chomp("/")
    uri.to_s
  rescue URI::InvalidURIError
    nil
  end
end

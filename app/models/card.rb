class Card < ApplicationRecord
  validates :artifact_url, presence: true, uniqueness: true
  validates :fizzy_card_number, presence: true, uniqueness: true

  def self.extract_artifact_url(description_html)
    return nil if description_html.blank?
    doc = Nokogiri::HTML5.fragment(description_html)
    ref_row = doc.css("tr").find { |tr| tr.at_css("th")&.text&.strip == "ref" }
    return nil unless ref_row
    cell = ref_row.at_css("td")
    return nil unless cell
    value = cell.at_css("a")&.[]("href") || cell.text
    ArtifactUrl.normalize(value)
  end
end

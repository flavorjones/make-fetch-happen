class ScanCardsJob < ApplicationJob
  def perform
    fizzy = FizzyClient.build
    seen_numbers = []

    fizzy.cards.list(account_id: FizzyClient.account_id, board_ids: [ FizzyClient.board_id ]).each do |card_hash|
      artifact_url = Card.extract_artifact_url(card_hash["description_html"])
      next unless artifact_url

      card = Card.find_or_initialize_by(fizzy_card_number: card_hash["number"])
      card.update!(artifact_url: artifact_url, title: card_hash["title"])
      seen_numbers << card_hash["number"]
    end

    Card.where.not(fizzy_card_number: seen_numbers).destroy_all
  end
end

class Card < ApplicationRecord
  validates :artifact_url, presence: true, uniqueness: true
  validates :fizzy_card_number, presence: true, uniqueness: true
end

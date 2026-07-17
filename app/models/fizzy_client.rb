module FizzyClient
  def self.build
    Fizzy.client(
      access_token: ENV.fetch("FIZZY_TOKEN"),
      base_url: ENV.fetch("FIZZY_BASE_URL", "https://app.fizzy.do")
    )
  end

  def self.account_id
    ENV.fetch("FIZZY_ACCOUNT_ID")
  end

  def self.board_id
    ENV.fetch("FIZZY_BOARD_ID")
  end
end

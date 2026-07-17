class CardsController < ApplicationController
  def index
    @cards = Card.order(updated_at: :desc).page(params[:page]).per(50)
  end
end

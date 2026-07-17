ENV["RAILS_ENV"] ||= "test"
ENV["FIZZY_ACCOUNT_ID"] ||= "test-account"
ENV["FIZZY_BOARD_ID"] ||= "test-board"
require_relative "../config/environment"
require "rails/test_help"

module ActiveSupport
  class TestCase
    # Run tests in parallel with specified workers
    parallelize(workers: :number_of_processors)

    # Setup all fixtures in test/fixtures/*.yml for all tests in alphabetical order.
    fixtures :all

    # Add more helper methods to be used by all tests here...
  end
end

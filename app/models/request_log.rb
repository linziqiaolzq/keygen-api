# frozen_string_literal: true

class RequestLog < ApplicationRecord
  include DateRangeable
  include Limitable
  include Pageable
  include Searchable

  SEARCH_ATTRIBUTES = [:request_id, :status, :method, :url, :ip].freeze
  SEARCH_RELATIONSHIPS = {}.freeze

  belongs_to :account

  validates :account, presence: { message: "must exist" }

  scope :current_period, -> {
    date_start = 2.weeks.ago.beginning_of_day
    date_end = Time.current.end_of_day

    where created_at: (date_start..date_end)
  }

  # FIXME(ezekg) Rip out pg_search and replace with scopes
  scope :search_request_id, -> (term) {
    query = <<~SQL
      to_tsvector('simple', request_id::text)
      @@
      to_tsquery('simple', ? || ':*')
    SQL

    where(query.squish, term.to_s)
  }

  scope :search_method, -> (term) {
    where(method: term.upcase)
  }

  scope :search_status, -> (term) {
    where(status: term.to_s)
  }

  scope :search_url, -> (term) {
    where('url LIKE ?', "%#{term}%")
  }

  scope :search_ip, -> (term) {
    query = <<~SQL
      to_tsvector('simple', ip::text)
      @@
      to_tsquery('simple', ? || ':*')
    SQL

    where(query.squish, term.to_s)
  }
end

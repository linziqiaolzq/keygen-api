# frozen_string_literal: true

module Searchable
  extend ActiveSupport::Concern

  included do
    include PgSearch::Model

    def self.search(attributes:, relationships: {})
      attributes.each do |attribute|
        scope, against = nil

        case attribute
        when Hash
          scope, against = attribute.first
        when Symbol
          scope = against = attribute
        else
          throw InvalidSearchAttribute.new("invalid search attribute type '#{attribute.class.name.underscore}' for '#{self.name.underscore}'")
        end

        pg_search_scope "search_#{scope}", lambda { |query|
          # Remove `@` so that searching on partial email is doable e.g. `User.search_email('@keygen.sh')`
          query = query.gsub('@', ' ') if against == :email

          # Skip prefix search on metadata
          prefix =
            against != :metadata

          {
            against: against,
            query: query,
            using: {
              tsearch: {
                dictionary: 'simple',
                prefix: prefix,
              }
            }
          }
        }
      end

      # I believe it will be impossible to speed up these searches with database
      # indexes. May want to revisit this in the future, as it is very slow.
      relationships.each do |relationship, attributes|
        pg_search_scope "search_#{relationship}", lambda { |query|
          query = query.gsub('@', ' ') if attributes.include?(:email)

          {
            associated_against: { relationship => attributes },
            query: query,
            using: {
              tsearch: {
                dictionary: 'simple',
                prefix: false,
              }
            }
          }
        }
      end
    end
  end

  class InvalidSearchAttribute < StandardError; end
end
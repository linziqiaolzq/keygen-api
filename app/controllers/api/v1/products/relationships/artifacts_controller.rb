# frozen_string_literal: true

module Api::V1::Products::Relationships
  class ArtifactsController < Api::V1::BaseController
    before_action :scope_to_current_account!
    before_action :require_active_subscription!
    before_action :authenticate_with_token!
    before_action :set_product, only: %i[index show]
    before_action :set_artifact, only: %i[show]

    def index
      artifacts = apply_pagination(policy_scope(apply_scopes(product.release_artifacts)).preload(:platform, :arch, :filetype))
      authorize artifacts

      render jsonapi: artifacts
    end

    def show
      authorize artifact

      if artifact.downloadable?
        download = artifact.download!(ttl: artifact_query[:ttl])

        BroadcastEventService.call(
          event: 'artifact.downloaded',
          account: current_account,
          resource: artifact,
        )

        # Show we support `Prefer: no-redirect` for browser clients?
        render jsonapi: artifact, status: :see_other, location: download.url
      else
        render jsonapi: artifact
      end
    end

    private

    attr_reader :product,
                :artifact

    def set_product
      @product = current_account.products.find(params[:product_id])
      authorize product, :show?

      Current.resource = product
    end

    def set_artifact
      scoped_artifacts = policy_scope(release.artifacts).joins(:release)

      @artifact = FindByAliasService.call(scope: scoped_artifacts, identifier: params[:id], aliases: :filename, order: <<~SQL.squish)
        releases.semver_major        DESC,
        releases.semver_minor        DESC,
        releases.semver_patch        DESC,
        releases.semver_prerelease   DESC NULLS FIRST,
        releases.semver_build        DESC NULLS FIRST
      SQL
    end

    typed_query do
      on :show do
        if current_bearer&.has_role?(:admin, :developer, :sales_agent, :support_agent, :product)
          query :ttl, type: :integer, coerce: true, optional: true
        end
      end
    end
  end
end

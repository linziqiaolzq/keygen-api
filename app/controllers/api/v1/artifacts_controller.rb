# frozen_string_literal: true

module Api::V1
  class ArtifactsController < Api::V1::BaseController
    has_scope(:product) { |c, s, v| s.for_product(v) }

    before_action :scope_to_current_account!
    before_action :require_active_subscription!
    before_action :authenticate_with_token
    before_action :set_artifact, only: %i[show update destroy]

    def index
      # We're applying scopes after the policy scope because our policy scope
      # may include a UNION, and scopes/preloading need to be applied after
      # the UNION query has been performed. E.g. for LIMIT.
      artifacts = apply_pagination(apply_scopes(policy_scope(current_account.release_artifacts)).preload(:platform, :arch, :filetype))
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

    def create
      artifact = current_account.release_artifacts.new(artifact_params)
      authorize artifact

      artifact.save!

      upload = artifact.upload!

      BroadcastEventService.call(
        event: 'artifact.created',
        account: current_account,
        resource: artifact,
      )

      # Show we support `Prefer: no-redirect` for browser clients?
      render jsonapi: artifact, status: :temporary_redirect, location: upload.url
    end

    def update
      authorize artifact

      artifact.update!(artifact_params)

      BroadcastEventService.call(
        event: 'artifact.updated',
        account: current_account,
        resource: artifact,
      )

      render jsonapi: artifact, status: :temporary_redirect, location: upload.url
    end

    def destroy
      authorize artifact

      artifact.yank!

      BroadcastEventService.call(
        event: 'artifact.deleted',
        account: current_account,
        resource: artifact,
      )
    rescue ReleaseYankService::YankedReleaseError => e
      render_unprocessable_entity detail: e.message
    end

    private

    attr_reader :artifact

    def set_artifact
      scoped_artifacts = policy_scope(current_account.release_artifacts).joins(:release).for_channel(
        artifact_query.fetch(:channel) { 'stable' },
      )

      # NOTE(ezekg) Fetch the latest version of the artifact since we have no
      #             other qualifiers outside of a :filename.
      @artifact = FindByAliasService.call(scope: scoped_artifacts, identifier: params[:id], aliases: :filename, order: <<~SQL.squish)
        releases.semver_major        DESC,
        releases.semver_minor        DESC,
        releases.semver_patch        DESC,
        releases.semver_prerelease   DESC NULLS FIRST,
        releases.semver_build        DESC NULLS FIRST
      SQL

      Current.resource = artifact
    end

    typed_parameters format: :jsonapi do
      options strict: true

      on :create do
        param :data, type: :hash do
          param :type, type: :string, inclusion: %w[artifact artifacts]
          param :attributes, type: :hash do
            param :filename, type: :string
            param :filesize, type: :integer, optional: true
            param :filetype, type: :string, optional: true, transform: -> (_, key) {
              [:filetype_attributes, { key: }]
            }
            param :platform, type: :string, optional: true, transform: -> (_, key) {
              [:platform_attributes, { key: }]
            }
            param :arch, type: :string, optional: true, transform: -> (_, key) {
              [:platform_attributes, { key: }]
            }
            param :signature, type: :string, optional: true
            param :checksum, type: :string, optional: true
            param :metadata, type: :hash, allow_non_scalars: true, optional: true
          end
          param :relationships, type: :hash do
            param :release, type: :hash do
              param :data, type: :hash do
                param :type, type: :string, inclusion: %w[release releases]
                param :id, type: :string
              end
            end
          end
        end
      end

      on :update do
        param :data, type: :hash do
          param :type, type: :string, inclusion: %w[artifact artifacts]
          param :attributes, type: :hash do
            param :signature, type: :string, optional: true
            param :checksum, type: :string, optional: true
            param :metadata, type: :hash, allow_non_scalars: true, optional: true
          end
          param :relationships, type: :hash do
            param :release, type: :hash do
              param :data, type: :hash do
                param :type, type: :string, inclusion: %w[release releases]
                param :id, type: :string
              end
            end
          end
        end
      end
    end

    typed_query do
      on :show do
        query :channel, type: :string, inclusion: %w[stable rc beta alpha dev], optional: true
        if current_bearer&.has_role?(:admin, :developer, :sales_agent, :support_agent, :product)
          query :ttl, type: :integer, coerce: true, optional: true
        end
      end
    end
  end
end

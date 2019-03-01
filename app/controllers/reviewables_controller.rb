class ReviewablesController < ApplicationController
  requires_login

  PER_PAGE = 10

  before_action :version_required, only: [:update, :perform]

  def index
    min_score = params[:min_score].nil? ? SiteSetting.min_score_default_visibility : params[:min_score].to_i
    offset = params[:offset].to_i

    if params[:type].present?
      unless ['ReviewableUser', 'ReviewableQueuedPost', 'ReviewableFlaggedPost'].include?(params[:type])
        raise Discourse::InvalidParameter.new(:type)
      end
    end

    total_rows = Reviewable.list_for(current_user, status: :pending, min_score: min_score).count
    reviewables = Reviewable.list_for(
      current_user,
      status: :pending,
      limit: PER_PAGE,
      offset: offset,
      type: params[:type],
      min_score: min_score
    ).to_a

    # This is a bit awkward, but ActiveModel serializers doesn't seem to serialize STI
    hash = {}
    json = {
      reviewables: reviewables.map do |r|
        result = r.serializer.new(r, root: nil, hash: hash, scope: guardian).as_json
        hash[:bundled_actions].uniq!
        hash['actions'].uniq!
        result
      end,
      meta: {
        total_rows_reviewables: total_rows,
        load_more_reviewables: review_path(offset: offset + PER_PAGE, min_score: min_score),
        min_score: min_score,
        type: params[:type],
        types: meta_types
      }
    }
    json.merge!(hash)

    render_json_dump(json, rest_serializer: true)
  end

  def show
    reviewable = Reviewable.viewable_by(current_user).where(id: params[:reviewable_id]).first
    raise Discourse::NotFound.new if reviewable.blank?

    render_serialized(
      reviewable,
      reviewable.serializer,
      rest_serializer: true,
      root: 'reviewable',
      meta: {
        types: meta_types
      }
    )
  end

  def update
    reviewable = Reviewable.viewable_by(current_user).where(id: params[:reviewable_id]).first
    raise Discourse::NotFound.new if reviewable.blank?

    editable = reviewable.editable_for(guardian)
    raise Discourse::InvalidAccess.new unless editable.present?

    # Validate parameters are all editable
    edit_params = params[:reviewable] || {}
    edit_params.each do |name, value|
      if value.is_a?(ActionController::Parameters)
        value.each do |pay_name, pay_value|
          raise Discourse::InvalidAccess.new unless editable.has?("#{name}.#{pay_name}")
        end
      else
        raise Discourse::InvalidAccess.new unless editable.has?(name)
      end
    end

    begin
      if reviewable.update_fields(edit_params, current_user, version: params[:version].to_i)
        result = edit_params.merge(version: reviewable.version)
        render json: result
      else
        render_json_error(reviewable.errors)
      end
    rescue Reviewable::UpdateConflict
      return render_json_error(I18n.t('reviewables.conflict'), status: 409)
    end
  end

  def perform
    reviewable = Reviewable.viewable_by(current_user).where(id: params[:reviewable_id]).first
    raise Discourse::NotFound.new if reviewable.blank?

    args = {
      version: params[:version].to_i
    }

    begin
      result = reviewable.perform(current_user, params[:action_id].to_sym, args)
    rescue Reviewable::InvalidAction => e
      # Consider InvalidAction an InvalidAccess
      raise Discourse::InvalidAccess.new(e.message)
    rescue Reviewable::UpdateConflict
      return render_json_error(I18n.t('reviewables.conflict'), status: 409)
    end

    if result.success?
      render_serialized(result, ReviewablePerformResultSerializer)
    else
      render_json_error(result.errors)
    end
  end

protected

  def version_required
    if params[:version].blank?
      render_json_error(I18n.t('reviewables.missing_version'), status: 422)
    end
  end

  def meta_types
    {
      created_by: 'user',
      target_created_by: 'user'
    }
  end

end

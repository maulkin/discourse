require_dependency 'reviewable'

class ReviewableFlaggedPost < Reviewable

  def post
    @post ||= (target || Post.with_deleted.find_by(id: target_id))
  end

  def build_actions(actions, guardian, args)
    return unless pending?
    return if post.blank?

    build_action(actions, :agree_and_keep, 'thumbs-up')

    if post.user_deleted?
      build_action(actions, :agree_and_restore, 'far-eye')
    elsif !post.hidden?
      build_action(actions, :agree_and_hide, 'far-eye-slash')
    end

    if post.hidden?
      build_action(actions, :disagree_and_restore, 'thumbs-down')
    else
      build_action(actions, :disagree, 'thumbs-down')
    end

    build_action(actions, :ignore, 'external-link-alt')
  end

  def perform_ignore(performed_by, args)
    actions = PostAction.active
      .where(post_id: target_id)
      .where(post_action_type_id: PostActionType.notify_flag_type_ids)

    actions.each do |action|
      action.deferred_at = Time.zone.now
      action.deferred_by_id = performed_by.id
      # so callback is called
      action.save
      action.add_moderator_post_if_needed(performed_by, :deferred, args[:post_was_deleted])
    end

    update_flag_stats(:ignored, actions.map(&:user_id))

    if actions.first.present?
      DiscourseEvent.trigger(:flag_reviewed, post)
      DiscourseEvent.trigger(:flag_deferred, actions.first)
    end

    create_result(:success, :ignored) { |result| result.recalculate_score = true }
  end

  def perform_agree_and_keep(performed_by, args)
    agree(performed_by, args)
  end

  def perform_agree_and_hide(performed_by, args)
    agree(performed_by, args) do |pa|
      post.hide!(pa.post_action_type_id)
    end
  end

  def perform_agree_and_restore(performed_by, args)
    agree(performed_by, args) do
      PostDestroyer.new(performed_by, post).recover
    end
  end

  def perform_disagree_and_restore(performed_by, args)
    result = perform_disagree(performed_by, args)
    PostDestroyer.new(performed_by, post).recover
    result
  end

  def perform_disagree(performed_by, args)

    # -1 is the automatic system cleary
    action_type_ids =
      if performed_by.id == Discourse::SYSTEM_USER_ID
        PostActionType.auto_action_flag_types.values
      else
        PostActionType.notify_flag_type_ids
      end

    actions = PostAction.active.where(post_id: target_id).where(post_action_type_id: action_type_ids)

    actions.each do |action|
      action.disagreed_at = Time.zone.now
      action.disagreed_by_id = performed_by.id
      # so callback is called
      action.save
      action.add_moderator_post_if_needed(performed_by, :disagreed)
    end

    update_flag_stats(:disagreed, actions.map(&:user_id))

    # reset all cached counters
    cached = {}
    action_type_ids.each do |atid|
      column = "#{PostActionType.types[atid]}_count"
      cached[column] = 0 if ActiveRecord::Base.connection.column_exists?(:posts, column)
    end

    Post.with_deleted.where(id: target_id).update_all(cached)

    if actions.first.present?
      DiscourseEvent.trigger(:flag_reviewed, post)
      DiscourseEvent.trigger(:flag_disagreed, actions.first)
    end

    # Undo hide/silence if applicable
    if post&.hidden?
      post.unhide!
      UserSilencer.unsilence(post.user) if UserSilencer.was_silenced_for?(post)
    end

    create_result(:success, :rejected) { |result| result.recalculate_score = true }
  end

  def update_flag_stats(status, user_ids)
    return unless [:agreed, :disagreed, :ignored].include?(status)

    # Don't count self-flags
    user_ids -= [post&.user_id]
    return if user_ids.blank?

    result = DB.query(<<~SQL, user_ids: user_ids)
      UPDATE user_stats
      SET flags_#{status} = flags_#{status} + 1
      WHERE user_id IN (:user_ids)
      RETURNING user_id, flags_agreed + flags_disagreed + flags_ignored AS total
    SQL

    Jobs.enqueue(
      :truncate_user_flag_stats,
      user_ids: result.select { |r| r.total > Jobs::TruncateUserFlagStats.truncate_to }.map(&:user_id)
    )
  end

  def self.counts_for(posts)
    result = {}

    counts = DB.query(<<~SQL, pending: Reviewable.statuses[:pending])
      SELECT r.target_id AS post_id,
        rs.reviewable_score_type,
        count(*) as total
      FROM reviewables AS r
      INNER JOIN reviewable_scores AS rs ON rs.reviewable_id = r.id
      WHERE r.type = 'ReviewableFlaggedPost'
        AND r.status = :pending
      GROUP BY r.target_id, rs.reviewable_score_type
    SQL

    counts.each do |c|
      result[c.post_id] ||= {}
      result[c.post_id][c.reviewable_score_type] = c.total
    end

    result
  end

  def agree(performed_by, args)
    actions = PostAction.active
      .where(post_id: target_id)
      .where(post_action_type_id: PostActionType.notify_flag_types.values)

    trigger_spam = false
    actions.each do |action|
      action.agreed_at = Time.zone.now
      action.agreed_by_id = performed_by.id
      # so callback is called
      action.save
      action.add_moderator_post_if_needed(performed_by, :agreed, args[:post_was_deleted])
      trigger_spam = true if action.post_action_type_id == PostActionType.types[:spam]
    end

    update_flag_stats(:agreed, actions.map(&:user_id))

    DiscourseEvent.trigger(:confirmed_spam_post, post) if trigger_spam

    if actions.first.present?
      DiscourseEvent.trigger(:flag_reviewed, post)
      DiscourseEvent.trigger(:flag_agreed, actions.first)
      yield(actions.first) if block_given?
    end

    create_result(:success, :approved) { |result| result.recalculate_score = true }
  end

protected

  def build_action(actions, id, icon)
    actions.add(id) do |action|
      action.icon = icon
      action.title = "reviewables.actions.#{id}.title"
      action.description = "reviewables.actions.#{id}.description"
    end
  end

end

# == Schema Information
#
# Table name: reviewables
#
#  id                      :bigint(8)        not null, primary key
#  type                    :string           not null
#  status                  :integer          default(0), not null
#  created_by_id           :integer          not null
#  reviewable_by_moderator :boolean          default(FALSE), not null
#  reviewable_by_group_id  :integer
#  claimed_by_id           :integer
#  category_id             :integer
#  topic_id                :integer
#  score                   :float            default(0.0), not null
#  target_id               :integer
#  target_type             :string
#  target_created_by_id    :integer
#  payload                 :json
#  version                 :integer          default(0), not null
#  meta_topic_id           :integer
#  latest_score            :datetime
#  created_at              :datetime         not null
#  updated_at              :datetime         not null
#
# Indexes
#
#  index_reviewables_on_status              (status)
#  index_reviewables_on_status_and_score    (status,score)
#  index_reviewables_on_status_and_type     (status,type)
#  index_reviewables_on_type_and_target_id  (type,target_id) UNIQUE
#

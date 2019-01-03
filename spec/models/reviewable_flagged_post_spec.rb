require 'rails_helper'

RSpec.describe ReviewableFlaggedPost, type: :model do

  def pending_count
    ReviewableFlaggedPost.default_visible.pending.count
  end

  describe "flag_stats" do
    let(:user) { Fabricate(:user) }
    let(:post) { Fabricate(:post) }
    let(:user_post) { Fabricate(:post, user: user) }
    let(:reviewable) { PostActionCreator.spam(user, post).reviewable }

    it "increases flags_agreed when agreed" do
      expect(user.user_stat.flags_agreed).to eq(0)
      reviewable.perform(Discourse.system_user, :agree_and_keep)
      expect(user.user_stat.reload.flags_agreed).to eq(1)
    end

    it "increases flags_disagreed when disagreed" do
      expect(user.user_stat.flags_disagreed).to eq(0)
      reviewable.perform(Discourse.system_user, :disagree)
      expect(user.user_stat.reload.flags_disagreed).to eq(1)
    end

    it "increases flags_ignored when ignored" do
      expect(user.user_stat.flags_ignored).to eq(0)
      reviewable.perform(Discourse.system_user, :ignore)
      expect(user.user_stat.reload.flags_ignored).to eq(1)
    end

    it "doesn't increase stats when you flag yourself" do
      expect(user.user_stat.flags_agreed).to eq(0)
      self_flag = PostActionCreator.spam(user, user_post).reviewable
      self_flag.perform(Discourse.system_user, :agree_and_keep)
      expect(user.user_stat.reload.flags_agreed).to eq(0)
    end
  end

  describe "actions" do
    let(:user) { Fabricate(:user) }
    let(:moderator) { Fabricate(:moderator) }
    let(:post) { Fabricate(:post) }
    let!(:result) { PostActionCreator.spam(user, post) }
    let(:reviewable) { result.reviewable }
    let(:score) { result.reviewable_score }
    let(:guardian) { Guardian.new(moderator) }

    describe "actions_for" do
      it "returns appropriate defaults" do
        actions = reviewable.actions_for(guardian)
        expect(actions.has?(:agree_and_hide)).to eq(true)
        expect(actions.has?(:agree_and_keep)).to eq(true)
        expect(actions.has?(:disagree)).to eq(true)
        expect(actions.has?(:ignore)).to eq(true)

        expect(actions.has?(:disagree_and_restore)).to eq(false)
      end

      it "returns `agree_and_restore` if the post is user deleted" do
        post.update(user_deleted: true)
        expect(reviewable.actions_for(guardian).has?(:agree_and_restore)).to eq(true)
      end

      it "returns appropriate actions for a hidden post" do
        post.update(hidden: true, hidden_at: Time.now)
        expect(reviewable.actions_for(guardian).has?(:agree_and_hide)).to eq(false)
        expect(reviewable.actions_for(guardian).has?(:disagree_and_restore)).to eq(true)
      end
    end

    it "agrees with the flags and hides the post" do
      reviewable.perform(moderator, :agree_and_keep)
      expect(reviewable).to be_approved
      expect(score.reload).to be_agreed
      expect(post).not_to be_hidden
    end

    it "agrees with the flags and hides the post" do
      reviewable.perform(moderator, :agree_and_hide)
      expect(reviewable).to be_approved
      expect(score.reload).to be_agreed
      expect(post).to be_hidden
    end

    it "agrees with the flags and restores the post" do
      post.update(user_deleted: true)
      reviewable.perform(moderator, :agree_and_restore)
      expect(reviewable).to be_approved
      expect(score.reload).to be_agreed
      expect(post.user_deleted?).to eq(false)
    end

    it "ignores the flags" do
      reviewable.perform(moderator, :ignore)
      expect(reviewable).to be_ignored
      expect(score.reload).to be_ignored
    end

    it "disagrees with the flags" do
      reviewable.perform(moderator, :disagree)
      expect(reviewable).to be_rejected
      expect(score.reload).to be_disagreed
    end

    it "disagrees with the flags and restores the post" do
      post.update(hidden: true, hidden_at: Time.now)
      reviewable.perform(moderator, :disagree_and_restore)
      expect(reviewable).to be_rejected
      expect(score.reload).to be_disagreed
      expect(post.user_deleted?).to eq(false)
    end

  end

  describe "pending count" do
    let(:user) { Fabricate(:user) }
    let(:moderator) { Fabricate(:moderator) }
    let(:post) { Fabricate(:post) }

    it "increments the numbers correctly" do
      expect(pending_count).to eq(0)

      result = PostActionCreator.off_topic(user, post)
      expect(pending_count).to eq(1)

      result.reviewable.perform(Discourse.system_user, :disagree)
      expect(pending_count).to eq(0)
    end

    it "respects min_score_default_visibility" do
      SiteSetting.min_score_default_visibility = 7.5
      expect(pending_count).to eq(0)

      PostActionCreator.off_topic(user, post)
      expect(pending_count).to eq(0)

      PostActionCreator.spam(moderator, post)
      expect(pending_count).to eq(1)
    end

    it "should reset counts when a topic is deleted" do
      PostActionCreator.off_topic(user, post)
      expect(pending_count).to eq(1)

      PostDestroyer.new(moderator, post).destroy
      expect(pending_count).to eq(0)
    end

    it "should not review non-human users" do
      post = create_post(user: Discourse.system_user)
      reviewable = PostActionCreator.off_topic(user, post).reviewable
      expect(reviewable).to be_blank
      expect(pending_count).to eq(0)
    end

    it "should ignore handled flags" do
      post = create_post
      reviewable = PostActionCreator.off_topic(user, post).reviewable
      expect(post.hidden).to eq(false)
      expect(post.hidden_at).to be_blank

      reviewable.perform(moderator, :ignore)
      expect(pending_count).to eq(0)

      post.reload
      expect(post.hidden).to eq(false)
      expect(post.hidden_at).to be_blank

      post.hide!(PostActionType.types[:off_topic])

      post.reload
      expect(post.hidden).to eq(true)
      expect(post.hidden_at).to be_present
    end

  end

end

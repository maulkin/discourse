import computed from "ember-addons/ember-computed-decorators";

export default Ember.Controller.extend({
  queryParams: ["min_score", "type"],
  type: null,
  min_score: null,
  reviewables: null,

  @computed
  allTypes() {
    return ["flagged_post", "queued_post", "user"].map(type => {
      return {
        id: `Reviewable${type.classify()}`,
        name: I18n.t(`review.types.reviewable_${type}.title`)
      };
    });
  },

  actions: {
    remove(ids) {
      if (!ids) {
        return;
      }

      let newList = this.get("reviewables").reject(reviewable => {
        return ids.indexOf(reviewable.id) !== -1;
      });
      this.set("reviewables", newList);
    },

    apply() {
      this.set("type", this.get("filterType"));
      this.set("min_score", this.get("filterScore"));
    },

    loadMore() {
      return this.get("reviewables").loadMore();
    }
  }
});

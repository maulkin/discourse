export default Discourse.Route.extend({
  queryParams: {
    min_score: { refreshModel: true },
    type: { refreshModel: true }
  },

  model(params) {
    return this.store.findAll("reviewable", params);
  },

  setupController(controller, model) {
    let meta = model.resultSetMeta;

    controller.setProperties({
      reviewables: model,
      type: meta.type,
      filterType: meta.type,
      min_score: meta.min_score,
      filterScore: meta.min_score
    });
  }
});

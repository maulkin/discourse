import DropdownSelectBox from "select-kit/components/dropdown-select-box";
import computed from "ember-addons/ember-computed-decorators";

export default DropdownSelectBox.extend({
  pluginApiIdentifiers: ["admin-agree-flag-dropdown"],
  classNames: ["agree-flag", "admin-agree-flag-dropdown"],
  adminTools: Ember.inject.service(),
  nameProperty: "label",
  allowInitialValueMutation: false,
  headerIcon: "thumbs-o-up",

  computeHeaderContent() {
    let content = this._super(...arguments);
    content.name = `${I18n.t("admin.flags.agree")}...`;
    return content;
  },

  @computed("adminTools", "post.user")
  spammerDetails(adminTools, user) {
    return adminTools.spammerDetails(user);
  },

  canDeleteSpammer: Ember.computed.and(
    "spammerDetails.canDelete",
    "post.flaggedForSpam"
  ),

  computeContent() {
    const content = [];
    const canDeleteSpammer = this.get("canDeleteSpammer");

    if (canDeleteSpammer) {
      content.push({
        title: I18n.t("admin.flags.delete_spammer_title"),
        icon: "exclamation-triangle",
        id: "delete-spammer",
        action: () => this.send("deleteSpammer"),
        label: I18n.t("admin.flags.delete_spammer")
      });
    }

    return content;
  },

  mutateValue(value) {
    const computedContentItem = this.get("computedContent").findBy(
      "value",
      value
    );
    Ember.get(computedContentItem, "originalContent.action")();
  },

  actions: {
    deleteSpammer() {
      let spammerDetails = this.get("spammerDetails");
      this.attrs.removeAfter(spammerDetails.deleteUser());
    },

    perform(action) {
      let flaggedPost = this.get("post");
      this.attrs.removeAfter(flaggedPost.agreeFlags(action));
    }
  }
});

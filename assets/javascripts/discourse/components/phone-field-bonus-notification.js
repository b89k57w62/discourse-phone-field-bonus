import Component from "@ember/component";

export default Component.extend({
  classNames: ["phone-field-bonus-notification"],
  
  actions: {
    dismiss() {
      this.set("visible", false);
    }
  },
  
  didInsertElement() {
    this._super(...arguments);

    setTimeout(() => {
      if (!this.isDestroyed) {
        this.set("visible", false);
      }
    }, 5000);
  }
}); 
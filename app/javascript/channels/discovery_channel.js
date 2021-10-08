import consumer from "./consumer"

consumer.subscriptions.create("DiscoveryChannel", {
  connected() {
    // Called when the subscription is ready for use on the server
  },

  disconnected() {
    // Called when the subscription has been terminated by the server
  },

  received(data) {
    document.body.insertAdjacentHTML("beforeend", JSON.stringify(data));
    document.body.insertAdjacentHTML("beforeend", "<br>");
  }
});

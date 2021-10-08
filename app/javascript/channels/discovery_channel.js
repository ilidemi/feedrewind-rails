import consumer from "./consumer"

window.discoverySubscribe = (blogId, dataHandler) => {
    return consumer.subscriptions.create({channel: "DiscoveryChannel", blog_id: blogId}, {
        connected() {
            // Called when the subscription is ready for use on the server
        },

        disconnected() {
            // Called when the subscription has been terminated by the server
        },

        received(data) {
            dataHandler(data);
        }
    });
};

window.discoveryUnsubscribe = (subscription) => {
    consumer.subscriptions.remove(subscription);
};
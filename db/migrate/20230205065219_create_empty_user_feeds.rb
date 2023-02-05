class CreateEmptyUserFeeds < ActiveRecord::Migration[6.1]
  def change
    User.all.each do |user|
      next if UserRss.exists?(user_id: user.id)

      PublishPostsService.create_empty_user_feed(user)
    end
  end
end

class AddUserName < ActiveRecord::Migration[6.1]
  def change
    add_column :users, :name, :text

    User.all.each do |user|
      user.update_attribute("name", user.email[...user.email.index("@")])
    end

    change_column_null :users, :name, false
  end
end

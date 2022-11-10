web: bundle exec rails server -p $PORT
worker: bundle exec bin/delayed_job -n 4 start
release: rake db:migrate

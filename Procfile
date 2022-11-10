web: bundle exec rails server -p $PORT
worker: bundle exec bin/delayed_job -n 1 start
release: rake db:migrate

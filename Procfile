web: bundle exec rails server -p $PORT
worker: bundle exec bin/delayed_job -n 10 start
release: rake db:migrate

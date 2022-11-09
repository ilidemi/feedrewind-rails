web: bundle exec rails server -p $PORT
worker: bundle exec bin/delayed_job -n 100 start
release: rake db:migrate

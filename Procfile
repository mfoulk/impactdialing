web:  bundle exec rails server thin -p $PORT 
dialer: bundle exec ruby lib/predictive_dialer.rb
new_simulator: bundle exec ruby simulator/newest_simulator.rb
worker:  rake environment jobs:work
worker_job: rake environment resque:work QUEUE=worker_job
answered_worker: rake environment resque:work QUEUE=answered_worker
clock:   rake environment resque:scheduler
debiter: bundle exec ruby lib/debit.rb
answers: bundle exec ruby lib/process_voter_response.rb

